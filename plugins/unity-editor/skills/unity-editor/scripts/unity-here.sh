#!/usr/bin/env bash
# unity-here.sh — run Unity Editor tools against THE instance matching the current repo.
# Usage:
#   unity-here.sh --status            # preflight: show matched instance or fail
#   unity-here.sh <tool> [args...]    # run a Pipeline tool on the matched instance
set -uo pipefail

UNITY_BIN="$HOME/.unity/bin/unity"

if [[ ! -x "$UNITY_BIN" ]]; then
  echo "ERROR: unity CLI not found at $UNITY_BIN" >&2
  echo "Install: curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash" >&2
  exit 2
fi

find_root() {
  local dir
  dir="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$dir" && -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then
    echo "$dir"; return 0
  fi
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then
      echo "$dir"; return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ROOT="$(find_root)" || { echo "ERROR: not inside a Unity project (no Assets/ + ProjectSettings/ upward from $PWD)" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"

# Prints the matched instance's state ("ready", "busy", ...), or NONE.
match_state() {
  "$UNITY_BIN" status --json 2>/dev/null | python3 -c '
import json, os, sys
root = os.path.realpath(sys.argv[1])
try:
    d = json.load(sys.stdin)
except Exception:
    print("NONE"); raise SystemExit
for i in (d.get("data") or {}).get("instances") or []:
    if os.path.realpath(i.get("project", "")) == root:
        print(i.get("state", "unknown")); raise SystemExit
print("NONE")
' "$ROOT"
}

fail_no_instance() {
  echo "ERROR: no connected Editor for: $ROOT" >&2
  echo "Live instances (Pipeline package only):" >&2
  "$UNITY_BIN" status >&2 || true
  echo "Fix: open this project in Unity Editor (Pipeline package must be installed)," >&2
  echo "or cd into the repo that matches a live instance. This script never auto-opens." >&2
  exit 1
}

# Wait for ready. Two distinct non-ready cases:
#  - busy/compiling states: wait up to UH_WAIT (default 60s) — big compiles take a while
#  - NONE: instance drops off `unity status` for a few seconds DURING a domain reload;
#    retry up to UH_NONE_WAIT (default 12s) before concluding there is no Editor.
WAIT_MAX="${UH_WAIT:-60}"
NONE_MAX="${UH_NONE_WAIT:-12}"
busy_elapsed=0
none_elapsed=0
STATE="$(match_state)"
while [[ "$STATE" != "ready" ]]; do
  if [[ "$STATE" == "NONE" ]]; then
    if (( none_elapsed >= NONE_MAX )); then fail_no_instance; fi
    echo "No matching instance (domain reload in progress?). Retrying... (${none_elapsed}s/${NONE_MAX}s)" >&2
    none_elapsed=$((none_elapsed + 2))
  else
    none_elapsed=0
    if (( busy_elapsed >= WAIT_MAX )); then
      echo "ERROR: Editor still not ready (state: $STATE) after ${WAIT_MAX}s for: $ROOT" >&2
      exit 1
    fi
    echo "Editor busy (state: $STATE). Waiting... (${busy_elapsed}s/${WAIT_MAX}s)" >&2
    busy_elapsed=$((busy_elapsed + 2))
  fi
  sleep 2
  STATE="$(match_state)"
done

if [[ "${1:-}" == "--status" ]]; then
  "$UNITY_BIN" status --json | python3 -c '
import json, os, sys
root = os.path.realpath(sys.argv[1])
d = json.load(sys.stdin)
for i in (d.get("data") or {}).get("instances") or []:
    if os.path.realpath(i.get("project", "")) == root:
        print(json.dumps(i, indent=1)); raise SystemExit
' "$ROOT"
  exit 0
fi

[[ $# -ge 1 ]] || { echo "Usage: unity-here.sh --status | <tool> [args...]" >&2; exit 2; }

exec "$UNITY_BIN" command --project-path "$ROOT" --json "$@"

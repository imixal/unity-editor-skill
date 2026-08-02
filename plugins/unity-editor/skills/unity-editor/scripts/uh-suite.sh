#!/usr/bin/env bash
# uh-suite.sh — run the full EditMode suite async and diff failures against the
# project's known-failure baseline. The suite carries dozens of pre-existing red
# tests, so raw pass/fail counts are meaningless — only the delta matters.
#
# Usage:
#   uh-suite.sh              # run, report NEW failures vs baseline (exit 1 if any) and FIXED ones
#   uh-suite.sh --baseline   # run, then store the current failure set as the baseline
#
# Baseline file: <repo-root>/.uh-baseline-fails.txt (commit or gitignore, your call).
set -uo pipefail
UH="$(cd "$(dirname "$0")" && pwd)/unity-here.sh"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASE="$ROOT/.uh-baseline-fails.txt"

timeout 100 "$UH" run_tests --mode editor --async_tests true >/dev/null 2>&1

status=""
for i in $(seq 1 120); do
  sleep 5
  # Double-encoded result: match unquoted words only.
  status="$(timeout 30 "$UH" test_status 2>/dev/null || true)"
  case "$status" in
    *completed*|*finished*) break ;;
  esac
done

results="$(timeout 60 "$UH" test_status 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
if not d.get("success"):
    sys.exit("FAIL: " + "; ".join(e.get("message", "?") for e in d.get("errors") or []))
r = d["data"]["result"]
r = json.loads(r) if isinstance(r, str) else r
res = r.get("results") or r.get("Results") or []
if not res:
    sys.exit("ERROR: 0 test results — run cancelled, timed out, or assembly broken. Not a pass.")
print(len(res))
for t in res:
    if t.get("Status") == "Failed":
        print(t.get("FullName", "?"))
')" || { echo "$results"; exit 1; }

total="$(echo "$results" | head -1)"
fails="$(echo "$results" | tail -n +2 | sort)"
nfails="$(echo "$fails" | grep -c . || true)"
echo "suite: $total tests, $nfails failed"

if [[ "${1:-}" == "--baseline" ]]; then
  echo "$fails" > "$BASE"
  echo "baseline saved to $BASE"
  exit 0
fi

if [[ ! -f "$BASE" ]]; then
  echo "no baseline yet — saving current failures as baseline ($BASE); rerun after your changes"
  echo "$fails" > "$BASE"
  exit 0
fi

new="$(comm -13 <(sort "$BASE") <(echo "$fails") | grep . || true)"
fixed="$(comm -23 <(sort "$BASE") <(echo "$fails") | grep . || true)"
echo "NEW failures vs baseline:"
echo "${new:-  none}"
echo "FIXED vs baseline:"
echo "${fixed:-  none}"
[[ -z "$new" ]]

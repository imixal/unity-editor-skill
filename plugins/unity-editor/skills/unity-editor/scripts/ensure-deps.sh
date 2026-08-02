#!/usr/bin/env bash
# ensure-deps.sh — verify (and optionally install) everything the unity-editor skill needs:
#   python3, git, the Unity CLI (~/.unity/bin/unity), and — when run from inside a
#   Unity project — the com.unity.pipeline package in that project.
#
# Usage:
#   ensure-deps.sh            # report only, exit 0 when everything is present
#   ensure-deps.sh --install  # also install the Unity CLI and the Pipeline package
set -uo pipefail
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

UNITY_BIN="$HOME/.unity/bin/unity"
ok=true

if command -v python3 >/dev/null 2>&1; then
  echo "OK       python3 ($(python3 -V 2>&1))"
else
  echo "MISSING  python3 — install it (macOS: xcode-select --install, or python.org)"
  ok=false
fi

if command -v git >/dev/null 2>&1; then
  echo "OK       git ($(git --version))"
else
  echo "MISSING  git"
  ok=false
fi

if [[ -x "$UNITY_BIN" ]]; then
  echo "OK       unity CLI ($("$UNITY_BIN" --version 2>/dev/null | head -1))"
else
  if $INSTALL; then
    echo "...      installing Unity CLI (beta channel)"
    curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash
    if [[ -x "$UNITY_BIN" ]]; then
      echo "OK       unity CLI installed"
    else
      echo "FAILED   unity CLI install — see output above"
      ok=false
    fi
  else
    echo "MISSING  unity CLI at $UNITY_BIN — rerun with --install, or run:"
    echo "         curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash"
    ok=false
  fi
fi

# Per-project check: only meaningful when run from inside a Unity project.
ROOT=""
dir="$PWD"
while [[ "$dir" != "/" ]]; do
  if [[ -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then ROOT="$dir"; break; fi
  dir="$(dirname "$dir")"
done

if [[ -n "$ROOT" ]]; then
  if grep -q 'com\.unity\.pipeline' "$ROOT/Packages/manifest.json" 2>/dev/null; then
    echo "OK       com.unity.pipeline present in $ROOT"
  else
    if $INSTALL && [[ -x "$UNITY_BIN" ]]; then
      echo "...      installing com.unity.pipeline into $ROOT"
      if (cd "$ROOT" && "$UNITY_BIN" pipeline install); then
        echo "OK       com.unity.pipeline installed (Editor will recompile; wait for it to settle)"
      else
        echo "FAILED   unity pipeline install — run it manually from $ROOT"
        ok=false
      fi
    else
      echo "MISSING  com.unity.pipeline in $ROOT — run: cd '$ROOT' && unity pipeline install"
      ok=false
    fi
  fi
else
  echo "note     not inside a Unity project — skipped the per-project Pipeline package check"
fi

if $ok; then
  echo "All dependencies OK"
  exit 0
else
  echo "Some dependencies missing — see above"
  exit 1
fi

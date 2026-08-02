#!/usr/bin/env bash
# uh-build.sh — the one call to make after Write/Edit on .cs files.
# Refresh (so Unity actually imports the edit) + recompile + poll + surface
# compile errors from the console, because recompile_status alone reports
# up_to_date/failed:false both when the edit wasn't imported yet AND when an
# assembly is genuinely broken.
#
# Usage:
#   uh-build.sh                                          # build + report error CS lines
#   uh-build.sh 'typeof(Foo).GetMethod("Bar") != null'   # + reflection proof the symbol landed
#
# Exit: 0 = clean (and symbol present, if given); 1 = compile errors / symbol missing.
set -uo pipefail
UH="$(cd "$(dirname "$0")" && pwd)/unity-here.sh"

"$UH" clear_console >/dev/null 2>&1
# Refresh may exceed the ~30s transport cap while imports run — that timeout is normal.
timeout 60 "$UH" menu --path 'Assets/Refresh' >/dev/null 2>&1 || true
timeout 100 "$UH" recompile >/dev/null 2>&1

for i in $(seq 1 60); do
  sleep 3
  # data.result is a double-encoded JSON string: nested quotes are escaped, so
  # match unquoted words, never '"status": "completed"'.
  s="$(timeout 30 "$UH" recompile_status 2>/dev/null || true)"
  case "$s" in
    *completed*|*up_to_date*) break ;;
  esac
done

errs="$(timeout 60 "$UH" get_console_logs --severity error --limit 100 2>/dev/null \
  | grep -o 'error CS[^"\\]\{0,200\}' | sort -u)"
if [[ -n "$errs" ]]; then
  echo "COMPILE ERRORS:"
  echo "$errs"
  exit 1
fi

if [[ $# -ge 1 && -n "$1" ]]; then
  out="$(timeout 60 "$UH" eval "return ($1) ? \"UH-SYMBOL-OK\" : \"UH-SYMBOL-MISSING\";" 2>/dev/null || true)"
  case "$out" in
    *UH-SYMBOL-OK*)
      echo "compile clean + symbol verified" ;;
    *UH-SYMBOL-MISSING*|*"Compilation Failed"*)
      echo "SYMBOL MISSING: console shows no error CS, but the assembly did not pick up the change."
      echo "Check: grep -E 'error CS' ~/Library/Logs/Unity/Editor.log | tail -20"
      echo "eval output was: $(echo "$out" | head -c 500)"
      exit 1 ;;
    *)
      echo "verification eval failed: $(echo "$out" | head -c 500)"
      exit 1 ;;
  esac
else
  echo "compile clean (no error CS in console)"
fi

#!/usr/bin/env bash
# install.sh — install the unity-editor skill for Cursor, Claude Code (plain skill),
# or any agentskills.io-compatible client.
#
# Usage:
#   ./install.sh            # auto: install into every detected client (~/.cursor, ~/.claude, ~/.agents)
#   ./install.sh cursor     # only ~/.cursor/skills/
#   ./install.sh claude     # only ~/.claude/skills/
#   ./install.sh agents     # only ~/.agents/skills/ (cross-tool standard dir)
#
# Claude Code users can install via the plugin marketplace instead:
#   /plugin marketplace add imixal/unity-editor-skill
#   /plugin install unity-editor@unity-skills
#
# An existing install is backed up to unity-editor.bak before being replaced.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/plugins/unity-editor/skills/unity-editor"

targets=()
case "${1:-auto}" in
  cursor) targets=("$HOME/.cursor/skills") ;;
  claude) targets=("$HOME/.claude/skills") ;;
  agents) targets=("$HOME/.agents/skills") ;;
  auto)
    [[ -d "$HOME/.cursor" ]] && targets+=("$HOME/.cursor/skills")
    [[ -d "$HOME/.claude" ]] && targets+=("$HOME/.claude/skills")
    [[ -d "$HOME/.agents" ]] && targets+=("$HOME/.agents/skills")
    if [[ ${#targets[@]} -eq 0 ]]; then
      targets=("$HOME/.agents/skills")
    fi
    ;;
  *)
    echo "Usage: $0 [cursor|claude|agents]" >&2
    exit 2
    ;;
esac

for t in "${targets[@]}"; do
  mkdir -p "$t"
  if [[ -e "$t/unity-editor" ]]; then
    rm -rf "$t/unity-editor.bak"
    mv "$t/unity-editor" "$t/unity-editor.bak"
    echo "backed up existing install -> $t/unity-editor.bak"
  fi
  cp -R "$SRC" "$t/unity-editor"
  echo "installed -> $t/unity-editor"
done

echo
"$SRC/scripts/ensure-deps.sh" || {
  echo
  echo "Run '$SRC/scripts/ensure-deps.sh --install' to install the missing pieces."
}

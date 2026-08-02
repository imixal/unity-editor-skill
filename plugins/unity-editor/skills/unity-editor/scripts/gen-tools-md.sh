#!/usr/bin/env bash
# gen-tools-md.sh — regenerate references/tools.md from the connected Editor's tool list.
# Run from inside a Unity repo with its Editor connected.
set -euo pipefail
UNITY_BIN="$HOME/.unity/bin/unity"
OUT="$(dirname "$0")/../references/tools.md"
mkdir -p "$(dirname "$OUT")"
"$UNITY_BIN" list --json | python3 -c "
import json, sys, datetime
d = json.load(sys.stdin)
tools = d['data']['tools']
lines = ['# Unity Pipeline Editor Tools', '',
         f'Generated from \`unity list --json\` — {len(tools)} tools.',
         'A bare positional binds only when the tool has exactly one REQUIRED param (eval, eval_file);',
         'everything else needs --flag value (bare positionals are silently misparsed, never an error).',
         'Params typed jobject/jarray/jtoken take a JSON literal string; all other values are raw strings.', '']
for t in sorted(tools, key=lambda x: x['name']):
    params = []
    for p in t.get('parameters') or []:
        s = f\"{p['name']}:{p['type']}\"
        if p.get('default') is not None:
            s += f\"={p['default']}\"
        if p.get('required'):
            s += ' (req)'
        params.append(s)
    psuffix = (' — params: ' + ', '.join(params)) if params else ''
    lines.append(f\"- **{t['name']}**: {t['description']}{psuffix}\")
print('\n'.join(lines))
" > "$OUT"
echo "Wrote $OUT"

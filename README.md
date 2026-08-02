# unity-editor skill

Drive a **running** Unity Editor from the terminal — from Claude Code, Cursor, or any [Agent Skills](https://agentskills.io) client. Execute C# in the Editor process, run EditMode/PlayMode tests, read the console, recompile and *actually verify* the compile, edit scenes/prefabs/ScriptableObjects — all through the Unity CLI + `com.unity.pipeline` package, no MCP server needed.

The skill is not just tool bindings: it encodes guardrails distilled from dozens of real agent sessions — the traps that silently waste hours (`recompile_status` reporting clean while an assembly is broken, `Total: 0` test runs read as passes, prefab variants flattened by `SaveAsPrefabAsset`, double-encoded JSON responses that no grep can match, timeouts that lose the response but not the work).

## What's inside

```
plugins/unity-editor/skills/unity-editor/
├── SKILL.md              # the skill: rules, recipes, failure modes
├── references/tools.md   # all 140 Pipeline tools with param schemas
└── scripts/
    ├── unity-here.sh     # guard: targets THE Editor matching your repo, never the wrong one
    ├── uh-build.sh       # refresh + recompile + poll + surface real compile errors
    ├── uh-suite.sh       # full test suite, diffed against a known-failures baseline
    ├── ensure-deps.sh    # dependency check / install
    └── gen-tools-md.sh   # regenerate references/tools.md after package upgrades
```

## Requirements

- macOS or Linux, `python3`, `git`
- [Unity CLI](https://docs.unity3d.com/) at `~/.unity/bin/unity`
- `com.unity.pipeline` package in the target Unity project
- A **running** Unity Editor with that project open (the skill never launches one)

Check / install everything:

```bash
plugins/unity-editor/skills/unity-editor/scripts/ensure-deps.sh            # report
plugins/unity-editor/skills/unity-editor/scripts/ensure-deps.sh --install  # install Unity CLI + Pipeline package
```

The skill also runs this check itself when it detects a missing dependency.

## Install

### Claude Code (plugin marketplace)

```
/plugin marketplace add imixal/unity-editor-skill
/plugin install unity-editor@unity-skills
```

### Cursor (2.4+), or plain Claude Code, or any Agent Skills client

```bash
git clone https://github.com/imixal/unity-editor-skill
cd unity-editor-skill
./install.sh            # auto-detects ~/.cursor, ~/.claude, ~/.agents
./install.sh cursor     # or target one client explicitly
```

Cursor discovers skills in `~/.cursor/skills/` (and also reads `~/.claude/skills/` and `~/.agents/skills/`).

## Usage

Open your Unity project in the Editor, then just ask your agent things like:

- "run the OfflineEarnings tests in the editor"
- "what's in the unity console?"
- "recompile and check for errors"
- "set maxOffset to 24 on the BackgroundParallaxView in the open scene"
- "enter play mode and measure draw calls before/after my change"

The agent preflights with `unity-here.sh --status`, refuses to touch the wrong Editor instance, and follows the skill's verified recipes.

## License

MIT

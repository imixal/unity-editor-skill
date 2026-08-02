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

## Why this instead of an MCP server?

Most terminal-to-Unity bridges (unity-mcp and friends) expose the Editor as an MCP server. This skill takes a different route — plain CLI + instructions — and that buys real advantages:

**No server, no per-client config.** An MCP setup means keeping a bridge process alive and registering it in every client (Claude Code, Cursor, each with its own config). Here the transport is one CLI binary; install the skill folder and any client that can run shell commands works — including CI.

**No context tax.** An MCP server loads its tool schemas into the agent's context up front, every session — with 140 Editor tools that's a lot of tokens spent before the first request. The skill lists tools in `references/tools.md`; the agent reads only what it needs, when it needs it.

**Operational knowledge, not just plumbing.** A protocol gives you tool calls; it can't tell the agent that `recompile_status: completed` sometimes lies while the broken assembly's old DLL stays loaded, that a `Total: 0` test run is never a pass, that `SaveAsPrefabAsset` flattens a prefab variant, or that a timed-out call may have finished its work. All of that came out of real sessions, and it's encoded in SKILL.md — plus `uh-build.sh` and `uh-suite.sh`, which make the two most error-prone workflows deterministic scripts instead of re-improvised tool sequences.

**Right Editor, guaranteed.** The guard script resolves the Editor instance from the repo owning your CWD and refuses everything else. A port-bound MCP bridge will happily send commands into whichever project it's connected to — including the wrong one.

**Composable in the shell.** CLI calls pipe into `grep`/`python3`/`timeout`, run in loops, background jobs, and CI — things a tool-call interface can't naturally express.

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

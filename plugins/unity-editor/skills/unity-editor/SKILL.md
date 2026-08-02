---
name: unity-editor
description: Drive a running Unity Editor from the terminal via Unity CLI + Pipeline package. Use for ANY Unity Editor operation - executing C# in the Editor (eval), reading console logs, running EditMode/PlayMode tests, recompiling and checking compile status, scene/prefab/GameObject/component edits, asset database operations, menu items. Triggers - "run in editor", "unity console", "unity tests", "recompile", "prefab", "scene", "GameObject", RunCommand-style C# execution, "another Unity instance is running" batchmode conflict.
---

# Unity Editor via Unity CLI

Talk to a **running** Unity Editor through `unity command` (Unity CLI + com.unity.pipeline package).

`SKILL_DIR` below means the directory containing this SKILL.md (in Claude Code it is available as `${CLAUDE_SKILL_DIR}`; in other hosts, resolve it from where you read this file).

## Dependencies

Everything needed: `python3`, `git`, the Unity CLI (`~/.unity/bin/unity`), and the `com.unity.pipeline` package inside the target Unity project. Check them any time with:

    $SKILL_DIR/scripts/ensure-deps.sh            # report only
    $SKILL_DIR/scripts/ensure-deps.sh --install  # also install Unity CLI + Pipeline package (confirm with the user first)

Run the check whenever the guard script exits 2 (CLI missing) or an open project never shows up in `--status` (Pipeline package missing from its `Packages/manifest.json`).

## Non-negotiable rules

1. **Every Editor call goes through the guard script** — never call `unity command` directly:
   `$SKILL_DIR/scripts/unity-here.sh <tool> [args...]`
   It resolves the Unity project root from CWD and refuses if no connected Editor matches. It NEVER auto-opens an Editor: if it fails, report to the user and stop.
2. **cd into the target repo first.** The guard targets the project that owns the CWD.
3. **No screen captures** (`screenshot`, `capture_game_view`, `capture_scene_view`) — skill policy; remove this rule in your copy if you want them.
4. **Arg passing.** A bare positional binds only when the tool has exactly **one required param** — in practice `eval` and `eval_file` only. Everything else takes `--flag value`; bare positionals are silently misparsed, never an error (bare `run_tests EditMode Foo` ran a full multi-thousand-test suite; bare `menu 'Assets/Refresh'` executes nothing and dumps every registered menu item, because `menu`'s `path` is *optional* — always `--path`). Params typed `jobject`/`jarray`/`jtoken` in references/tools.md take a JSON literal: `set_component_properties --target <ref> --properties '{"maxOffset":24}'`. All other values are raw strings. Param lookup: `grep -n '^- \*\*<tool>\*\*' $SKILL_DIR/references/tools.md`.
5. On `"success": false`, `data` is `null` and the cause is in `errors[].message` — read it before parsing anything (`d['data']['result']` crashes with NoneType). Bash exit code 6 = the tool reached the Editor and failed: your code/args, not connectivity — don't re-run `--status`, don't blind-retry.

## Preflight

    $SKILL_DIR/scripts/unity-here.sh --status

Exit 0 + instance JSON → proceed. Exit 1 → no matching Editor (guard retries a NONE match ~12s, `UH_NONE_WAIT`, to ride out domain-reload disconnects; busy states up to 60s, `UH_WAIT`): show the user the live-instance output, ask them to open the project. Exit 2 → not a Unity project dir / CLI missing (run `ensure-deps.sh`).

- `"state": "unreachable"` = busy (compile or asset import), not dead.
- `"state": "ready"` only means the RPC handler is up — right after an Editor restart, assemblies may not exist yet.
- `--status` keeps failing for a project that IS open? Check its `Packages/manifest.json` for `com.unity.pipeline` — without the package the instance never appears (`ensure-deps.sh --install` adds it).
- Port changes across domain reloads; PID + project path are the instance identity — a changed port is not a second Editor.

## Timeouts

- `--timeout N` is a **CLI option in seconds** (default 30), and the pipeline transport caps at ~30s regardless of value or position. It does NOT reach the tools' own ms-denominated `timeout` params — `--timeout 300000` is inert.
- **Anything expected to exceed ~30s must go async + poll** (`run_tests --async_tests true` → `test_status`; `recompile` → `recompile_status`). Raising timeouts is not a path.
- **`eval` has no async route.** For a long eval: expect the ~30s timeout, make the body idempotent, and detect completion via side effects (files written, a probe eval) — a `timed out after 30000ms` error means **the response was lost, not that the work failed** (a 300s atlas-pack eval "timed out" with the atlas fully written). Verify side effects before retrying; a blind retry double-applies. Split whole-project sweeps into chunks when possible.
- The guard itself can wait up to 60s before the tool even runs — prefix calls with a shell cap: `timeout 100 $UH ...`. A shell-timeout-killed `run_tests` looks exactly like a clean 0-test run (see Tests).
- Agent harnesses commonly block long bare `sleep`s. Poll with a **bounded** loop (an `until` with no cap hangs forever on a wedged compile): `for i in $(seq 1 40); do $UH recompile_status 2>/dev/null | grep -qE 'completed|up_to_date' && break; sleep 3; done` — or run in background.

## Output contract

- Guard progress lines ("Editor busy...", "No matching instance...") go to **stderr** → pipe parsers with `2>/dev/null`, never `2>&1`.
- `data.result` is a **double-encoded JSON string** for `recompile_status`, `test_status`, `console` — `json.loads` twice. Never grep a raw response for `"status": "completed"`: the nested JSON is escaped (`\"status\":\"completed\"`, no space) and can never match — that exact loop once burned a 10-minute timeout on a suite that finished in 47s. Use unquoted `grep -E 'completed|up_to_date'`, or the canonical parser:

      $UH <tool> ... 2>/dev/null | python3 -c '
      import sys,json
      d=json.load(sys.stdin)
      if not d["success"]: sys.exit("FAIL: "+"; ".join(e["message"] for e in d["errors"]))
      r=d["data"]["result"]
      r=json.loads(r) if isinstance(r,str) else r
      print(json.dumps(r) if isinstance(r,(dict,list)) else r)'

- Key casing flips: sync `run_tests` → `Summary`/`Results`/`Total`; async `test_status` → lowercase `status`/`summary`/`results`, but items keep `FullName`/`Status`.
- Raw full-suite `test_status` can exceed 500 KB, a bare `menu` dump ~58 KB — filter in-process, never let raw output land in context.
- Unknown `--flags` are **silently accepted** as tool params — a misspelled flag returns a plausible empty result, not an error (`get_console_logs --types error` → `total: 0` → false "compiles clean", shipped a bad fix). Verify flag names in references/tools.md.
- One `$UH` call per Bash invocation when parsing — chained calls concatenate top-level JSON docs (unparseable) and hide mid-chain failures. In zsh, quote separators: `echo '==='` (unquoted leading `=` triggers equals-expansion).

## Recipes

All from repo root. `UH=$SKILL_DIR/scripts/unity-here.sh`.

**Run C# in the Editor**:

    $UH eval 'return UnityEngine.Application.unityVersion;'

Multi-line: write a `.cs` file to a scratch/temp directory (a file-write tool, not a heredoc — heredocs got shell-mangled), then `$UH eval_file /path/snippet.cs`. The file is a script body (statements + `return`), not a class. **Never write scratch eval files anywhere under `Assets/`** — they get imported as real scripts, can break the build, and get swept into commits.

**eval C# dialect** (each rule = a compile-error round trip saved):

- **No `using` directives** — they parse as using-*statements*: one `Identifier expected` per line + `'X' is a namespace but is used like a type`. Fully qualify everything.
- **Extension methods don't resolve** — call through the static class: `R3.ObservableSubscribeExtensions.Subscribe(obs, cb)`, `VContainer.IObjectResolverExtensions.Resolve<T>(container)`, `System.Linq.Enumerable.Select(...)`.
- All Editor assemblies are loaded (Addressables, Localization, TMP...). `does not exist in the namespace ... (are you missing an assembly reference?)` almost always means **wrong namespace**, not a missing assembly. Probe cheap before writing 40 lines: `$UH eval 'return System.Type.GetType("Foo, Assembly-CSharp")?.FullName;'`.
- Runtime errors return the message only, **no stack trace**. Wrap non-trivial bodies: `try { ... } catch (System.Exception e) { return e.ToString(); }`.
- Ignore trailing `Unreachable code detected` — wrapper artifact (code appended after your `return`), never your bug. Other diagnostics' line numbers map to your file.
- `GameObject.Find` misses inactive objects — use `UnityEngine.Object.FindObjectsByType<T>(UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None)` for popups/UI.
- Never trigger an import/reimport **and read its result in the same eval** — the read races the import and NREs. Split into two calls. Re-resolve object handles after any `DestroyImmediate` (destroyed-object errors).

**Prefer dedicated tools over eval** — intent → tool:

| Intent | Tool |
|---|---|
| find object (+hierarchyPath back) | `find_gameobjects --name X` / `--type T` / `--hierarchy_path P` |
| read serialized field | `get_serialized_fields --target <ref> --field fieldName` |
| write serialized field (incl. `a.Array.data[3].b`) | `set_serialized_field --target <ref> --field f --value '<json>'` |
| read/write component props | `get_component_properties` / `set_component_properties --properties '{...}'` |
| scene tree | `get_scene_hierarchy` |
| private injected field | `$UH eval 'return typeof(T).GetField("_x", System.Reflection.BindingFlags.NonPublic\|System.Reflection.BindingFlags.Instance).GetValue(obj);'` |

`<ref>` (objectref params): scene objects take a hierarchy path string or instanceId — live-verified: `set_component_properties --target 'MainUICanvas/backgroundParent' --type 'BackgroundParallaxView' --properties '{"maxOffset":24}'`; assets take their `Assets/...` path (per tools.md ObjectRef: guid/fileId/path). For struct value shapes (Vector2 etc.), **read the field first with `get_serialized_fields` and mirror the returned shape** rather than guessing the JSON encoding.

**Menu item**: `$UH menu --path 'Assets/Refresh'` (`--path` required — see rule 4). `$UH menu` with no args lists every registered item: the way to verify a custom `[MenuItem]` compiled and registered (pipe through grep).

**Console** — `console` is the richer tool (stack traces + cursor):

    $UH clear_console                       # BEFORE the operation, to isolate its output
    $UH console --tail 40 --level error     # level defaults to log → SDK/analytics noise
    $UH console --since <cursor>            # incremental follow — replaces marker-count polling

Traps: the buffer survives sessions — errors from hours ago look current (clear first / check `timestampUtc`); the buffer is empty right after an Editor restart — empty ≠ no errors. `get_console_logs --severity error --limit N` also works (`--types`/`--count` are silently swallowed, see Output contract).

**Compile after editing .cs** — use the wrapper; it exists because `recompile_status` lies:

    $SKILL_DIR/scripts/uh-build.sh                                        # refresh + recompile + poll + surface error CS
    $SKILL_DIR/scripts/uh-build.sh 'typeof(Foo).GetMethod("Bar") != null' # + reflection proof the symbol landed

**`recompile_status` is not proof, in either direction.** It returns `up_to_date` when Unity hasn't imported your edit yet (refresh first — `recompile` alone often no-ops), and `completed`/`failed:false`/`errors:[]` while an assembly is actually broken — the old DLL stays loaded (cost one session 45 min + a forced Unity restart). Ground truth = console `error CS` after a clear, plus a reflection probe for the new symbol. Symbol missing but status clean? `grep -E "error CS" ~/Library/Logs/Unity/Editor.log | tail -20` (Linux: `~/.config/unity3d/Editor.log`). Do NOT escalate through Refresh/ForceUpdate/CleanBuildCache/`--focus`/restart — all five were tried live; none helped. Also: a new .cs in an asmdef-less folder lands in Assembly-CSharp — invisible to `Tests` asmdefs; its fixture then runs as `Total: 0`.

**Tests**:

    $UH list_tests --mode editor
    $UH run_tests --mode editor --filter 'FixtureOrTestName'              # sync: ONE small fixture only
    # mode is case-insensitive; accepted values all|editor|playmode (live-verified)
    $UH run_tests --mode editor --filter 'X' --async_tests true          # anything bigger → poll test_status
    $SKILL_DIR/scripts/uh-suite.sh [--baseline]                          # full suite, diffed vs known failures

- **`Total: 0` is a failure, never a pass**: filter matched nothing, assembly didn't build, or a shell timeout killed the run. Assert `Total > 0`.
- `--filter` is a **substring** match — `SimulationTests` also runs `AnomalySimulationTests`. Accepts bare or fully-qualified names, single tests too. Run groups with `--filter_type className|category|assembly` instead of a shell loop. `[Explicit]` fixtures need `--include_explicit true`.
- Async `run_tests` returns an all-zero `Summary` immediately — real results only via `test_status` (double-encoded, see Output contract).
- A large project's full suite can carry **pre-existing failures** — only the delta vs baseline means anything; `uh-suite.sh` reports exactly that. Never run the full suite sync, never read raw pass/fail counts as truth.
- Sync per-fixture extraction:

      $UH run_tests --mode editor --filter X 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print(r['Summary']);[print(t['FullName'],'::',str(t.get('Message'))[:150]) for t in r['Results'] if t['Status']!='Passed']"

- `run_tests` has its own `timeout` param in **seconds** (default 300) — distinct from the CLI `--timeout`.
- Batchmode test runners (`Unity -batchmode -runTests ...`) **cannot run while the Editor holds the project lock** (`It looks like another Unity instance is running`) — that conflict is precisely this skill's trigger. Batch may also use a different Unity version: failure counts are not comparable across the two.
- `$UH save_all` before test runs — a dirty scene modal freezes every command. Wedged async run (`running` forever, play-mode exceptions in console): `cancel_tests`, fall back to per-fixture sync.

**Play Mode observation** — it works; never tell the user "I can't enter play mode":

    $UH set_autotick --enable true          # required in practice while unfocused; idempotent
    $UH clear_console && $UH editor_play    # success returns BEFORE the scene/DI is usable
    # poll readiness: until $UH eval '<scene root / presenter> != null' returns true; do sleep 4; done
    # then probe state via eval / eval_file, follow output via console --since <cursor>
    $UH editor_stop && $UH set_autotick --enable false

Poisoned session (DI never injects; `ObjectDisposedException`/`MissingReferenceException` from the *previous* run in console): `editor_stop → clear_console → editor_play`. Probes installed via eval (`Subscribe`, `EditorApplication.update +=`) accumulate until `editor_stop`. `get_performance_stats` returns drawCalls/setPassCalls/triangles/memory for A/B measurements — but a synthetic probe scene may not reproduce the real one. Editor state reaches disk with a ~2s autosave lag — poll the file, don't sample once.

**Asset & prefab writes from eval**:

- ScriptableObject/asset edit closer — always all four, then **re-read AND grep the on-disk file before committing** (the Editor can re-serialize its unchanged in-memory copy over your edit between eval and `git add`):

      so.ApplyModifiedPropertiesWithoutUndo();
      UnityEditor.EditorUtility.SetDirty(asset);
      UnityEditor.AssetDatabase.SaveAssets();
      UnityEditor.AssetDatabase.ImportAsset(path, UnityEditor.ImportAssetOptions.ForceUpdate);

- **Never `SaveAsPrefabAsset` over a prefab *variant*** — it flattens it (drops stripped-MonoBehaviour blocks, nulls references; caused real damage + a bad commit). Variants: edit in place via `SerializedObject` / `set_serialized_field`. `LoadPrefabContents → mutate → SaveAsPrefabAsset → UnloadPrefabContents` is for non-variants only. The `save_prefab_contents` tool covers just rename/set-active — eval is correct for structural edits.
- After `git checkout`/revert of an asset, the AssetDatabase serves the **stale pre-checkout version** to eval until `UnityEditor.AssetDatabase.ImportAsset(path, UnityEditor.ImportAssetOptions.ForceUpdate | UnityEditor.ImportAssetOptions.ForceSynchronousImport);`.
- `AssetDatabase.SaveAssets()` / `save_all` are **global flushes**: whatever the user has dirty in the Editor lands on disk — and in *your* diff (it happened: a user's layout edits rode into a commit). `git status --porcelain` before/after any saving eval; attribute unexpected diffs to the Editor. Stage files explicitly, never `git add -A` after Editor work (rides along user edits; can split .asset/.meta pairs). Never `git checkout` a whole .asset/.unity the user may have touched — surgically strip only your keys. Don't assume `HEAD~1` is your baseline; users commit mid-session.
- A serialized value in a scene/prefab **beats a changed C# default** — after changing a `[SerializeField]` default, grep scenes/prefabs for the field name; if present, the asset must change too.
- Externally-written assets (loc tables etc.) need `menu --path 'Assets/Refresh'` before the Editor sees them — `recompile` does not import.
- Never hand-parse .prefab/.unity YAML for structure or values — stripped/nested-prefab fileID entries break naive parsers. Use `get_scene_hierarchy`, `get_serialized_fields`, or eval over `AssetDatabase.LoadAssetAtPath<T>(path)`.

## Stalls & stuck commands

Verified: losing Editor focus is NOT the usual stall cause (`set_autotick` is typically already on — it is not the fix). Real causes, in likelihood order:

1. **Asset import in flight** — the Editor reports `state: unreachable` and EVERY command, `--status` included, blocks. Diagnose: `pgrep -fl AssetImportWorker`. Don't retry in the foreground; wait in background:
   `for i in $(seq 1 40); do timeout 25 $UH --status 2>/dev/null | grep -q '"state": "ready"' && { <work>; break; }; sleep 5; done` (backgrounded).
2. **Domain reload in flight.** The instance drops off `unity status` for a few seconds → "no connected Editor" though the Editor is fine. The guard retries NONE ~12s; if it still fails right after a compile/package op, re-run `--status` before concluding the Editor is closed. A `success:false` from `recompile_status` right after `recompile` means the same thing — keep polling, don't diagnose.
3. **Reload triggered inside your own call.** Never trigger a domain reload from `eval` (`AssetDatabase.Refresh()` with pending script edits, `EditorApplication.isPlaying = true`, compilation requests) — the reload tears down the handler and the response never comes back. Use the async tools (`recompile`, `package_add/remove`) and poll their `*_status`. `menu --path 'Assets/Refresh'` itself routinely exceeds the 30s transport cap during imports — treat that timeout as normal (`|| true`), then poll.
4. **Long sync test run** — see Tests; the transport caps at ~30s, so sync is for one small fixture only.
5. **Modal dialog** ("Save scene?", import conflict) freezes ALL commands until the user clicks in the Editor. `save_all` first; if commands suddenly stall mid-session, ask the user to check for a dialog.

## What stays native (do NOT round-trip through the Editor)

- File reads, greps, script creation/editing → native file/search tools, then `uh-build.sh`.
- Asset text search → ripgrep. Use `find_assets`/`search` only for AssetDB-semantic queries (by type, label, guid).

## Maintenance

Tool list changed (package upgrade)? Regenerate the reference:

    cd <unity-repo> && $SKILL_DIR/scripts/gen-tools-md.sh

Package/CLI management: `unity pipeline list|install|upgrade`, `unity status`, `unity upgrade` (CLI self-update). Binary: `~/.unity/bin/unity`.

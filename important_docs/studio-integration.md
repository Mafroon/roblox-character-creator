# Studio integration: Rojo file sync + Studio MCP

Date: 2026-09-16
Applies to: all scripts (moved this day from flat `.txt` to the Rojo `src/` tree — see commits `39552d1` and `edd531b`).

## What was set up

### 1. Rojo file sync (file system = source of truth)

- **Rokit 1.2.0** installed (official installer, `%USERPROFILE%\.rokit\bin`); `rokit.toml` pins `rojo-rbx/rojo@7.6.1`. New machine setup: install Rokit, then `rokit install` in this folder. Note: Rokit 1.2.0 requires an explicit `rokit trust rojo-rbx/rojo` before `rokit install` works.
- **Rojo Studio plugin** installed to `%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm` (via `rojo plugin install`). Studio auto-loads it on next start.
- **`default.project.json`** maps `src/` into the DataModel and declares all `ReplicatedStorage` remotes with exact classes (the `ElementChosenEvent`/`ResetElementChoiceEvent` BindableEvent-vs-RemoteEvent pitfall is now codified in the project file).
- **Encoding migration**: all sources converted Windows-1251 → UTF-8 (one-time commit `39552d1`), then renamed/moved (commit `edd531b`). `.gitattributes` now has `*.luau -text`; old commits remain cp1251 — use `iconv -f cp1251 -t utf-8` to read pre-`39552d1` diffs.
- **Headerless snippets** (`CameraLockScript`, `HoverEffect1/2/3`) live in `snippets/` and are intentionally NOT in the project file until their real Studio placement is confirmed.

### 2. Studio MCP (agent bridge: scripts, properties, output, playtest)

Built into Studio itself (`%LOCALAPPDATA%\Roblox\Versions\*\StudioMCP.exe`, launched via `%LOCALAPPDATA%\Roblox\mcp.bat`). Tool list and client setup: `D:\creator-docs\content\en-us\studio\mcp.md`. Key tools: `script_read`/`multi_edit`/`script_grep`, `search_game_tree`/`inspect_instance`, `execute_luau`, `get_console_output`, `start_stop_play`, `screen_capture`, input simulation, `list_roblox_studios`.

- Registered for ZCode at **workspace scope**: `.zcode/config.json` → `mcp.servers.Roblox_Studio` → `cmd.exe /c C:\Users\Andrey\AppData\Local\Roblox\mcp.bat` (stdio). `.zcode/` is gitignored — if the file goes missing, recreate it with that content.
- Studio-side switch: **Assistant → ⋯ → Manage MCP Servers → "Enable Studio as MCP server"** (persists per user once enabled). ZCode picks the server up at session start, so restart the ZCode session after enabling.

## Daily workflow

1. `rojo serve` in this folder (default port **34872**).
2. Open the game place in Studio → Plugins → Rojo → Connect.
3. Edit files in `src/**` — they hot-sync into Studio within a second. Do NOT edit those scripts inside Studio anymore; Studio-side edits get overwritten on the next sync from files.
4. For console/properties/playtesting from the agent: ask for the Studio MCP tools (`get_console_output` after a playtest, `execute_luau` for quick property/instance work in Edit mode).
5. GUI layout (frames, buttons, `LoadingScreen`, `EntranceGui`, `ServerStorage.Gender` rigs) stays hand-built in Studio — the project deliberately does not manage it.

## Safety rules (do not skip)

- Every node in `default.project.json` has `$ignoreUnknownInstances: true`. Rojo's default when `$path` is set is **false, i.e. delete unknown instances** (per rojo.space docs v7 → Project format). Removing the flag or adding a bare directory `$path` over a service with hand-built content can destroy Studio work on connect. Verify with `rojo build -o test.rbxlx` after project-file changes.
- If Studio and repo ever diverge (e.g. an emergency fix was pasted straight into Studio), reconcile BEFORE the next Rojo connect: Rojo overwrites managed scripts with file content.

## Remaining checklist (as of this note; Studio was closed during setup)

1. Open Studio, enable "Studio as MCP server" (Assistant → ⋯ → Manage MCP Servers), restart the ZCode session.
2. Verify MCP: `list_roblox_studios` → `search_game_tree` → `get_console_output`.
3. **Drift audit before first Rojo connect**: `script_read` every Studio script, diff vs `src/**`; confirm instance names (`HoverBorder` may actually be `UniversalBorderEffect` in MainMenuGui; `LoadingScript` name check) and remotes' classes (BindableEvents!). Reconcile differences by asking which side wins.
4. Decide placements for `snippets/*` from the live game tree; move confirmed ones into `src/` + project file.
5. First `rojo serve` connect with the game place open; confirm only declared scripts/remotes are touched and GUI frames survive.
6. End-to-end: edit a file → see it in Studio; `execute_luau` print → read via `get_console_output`; short playtest of loading → menu flow.

## Troubleshooting

- MCP server not showing / tools missing: restart both Studio and the ZCode session; check that `mcp.bat` exists and the toggle in Assistant is on; Settings → MCP shows connection status.
- Rojo plugin missing in Studio after install: restart Studio (plugins load at startup).
- `rojo serve` port conflict: another serve is running — use `rojo serve --port <port>` and connect the plugin to that port.
- Cyrillic mojibake in old diffs: that history is cp1251; `git show <rev> | iconv -f cp1251 -t utf-8`.

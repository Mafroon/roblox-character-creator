# AGENTS.md — rb_scripts

## Purpose

Roblox **Luau** scripts for a character-creation game (gender/race/skin customization, element selection, inventory, loading screen, place teleport), stored as a **Rojo project**: `default.project.json` maps the `src/` tree into Studio containers, and `rojo serve` live-syncs edits into a running Studio session. Headerless one-off snippets live in `snippets/` (not synced).

| File | Destination in Studio |
|---|---|
| `src/ReplicatedStorage/ColorPicker.luau` | ModuleScript `ColorPicker` in `ReplicatedStorage` |
| `src/ReplicatedStorage/SceneEffects.luau` | ModuleScript `SceneEffects` in `ReplicatedStorage` — camera yaw rig + menu show/hide tweens |
| `src/ReplicatedStorage/InventoryController.luau` | ModuleScript `InventoryController` in `ReplicatedStorage` — inventories, color palettes, randomizer, equip labels |
| `src/ReplicatedStorage/ElementMenu.luau` | ModuleScript `ElementMenu` in `ReplicatedStorage` — element info frames |
| `src/ServerScriptService/InventoryServer.server.luau` | Script in `ServerScriptService` |
| `src/ServerScriptService/Teleport.server.luau` | Script in `ServerScriptService` (`GAME_PLACE_ID = 95945939718701` hardcoded) |
| `src/ServerScriptService/MaleFemale.server.luau` | gender-change server script |
| `src/ServerScriptService/ReplaceAvatarWithRig.server.luau` | Script in `ServerScriptService` (custom spawn, `CharacterAutoLoads = false`) |
| `src/ReplicatedFirst/LoadingScript.client.luau` | LocalScript `LoadingScript` in `ReplicatedFirst` |
| `src/StarterGui/MainMenuGui/SceneTransition.client.luau` | LocalScript in `StarterGui/MainMenuGui` — orchestrator; requires the 3 modules above |
| `src/StarterGui/MainMenuGui/HoverBorder.client.luau` | LocalScript in `MainMenuGui` (instance name in Studio may be `UniversalBorderEffect` — verify before renaming) |
| `src/StarterGui/ElementMenuGui/HoverBorder2.client.luau` | LocalScript in `ElementMenuGui`; **load-bearing** — the only script wiring `PlayButton` → `ElementChosenEvent` (final transition); do not prune |
| `src/StarterGui/CreationMenuGui/RotateScript.client.luau` | LocalScript in CreationMenuGui |
| `snippets/CameraLockScript.luau` | camera setup snippet (menu scene) — placement not yet confirmed |
| `snippets/HoverEffect*.luau` | button hover snippets (inside menu GUIs) — placement not yet confirmed |

## Tooling & workflow

- **Rojo 7.6.1** pinned in `rokit.toml` (installed via [Rokit](https://github.com/rojo-rbx/rokit); `rokit install` after cloning). The Studio plugin is installed (`rojo plugin install`).
- **Daily loop**: run `rojo serve` in this folder → in Studio open the game place → Plugins → Rojo → Connect (port 34872). Edits to `src/**` hot-sync into Studio. The GUI instances themselves (frames, buttons) stay hand-built in Studio — the project only manages scripts and the `ReplicatedStorage` remotes.
- **Safety**: every node in `default.project.json` sets `$ignoreUnknownInstances: true`. With `$path` set, Rojo's default is to DELETE unknown instances on sync — never remove that flag, and never map a bare `$path` directory over a service that holds hand-built content.
- **Studio MCP** (AI-agent bridge; built into Studio, `StudioMCP.exe`): enables reading/editing scripts, inspecting/changing properties, `get_console_output`, and playtest control from the agent. Enable in Studio: Assistant → ⋯ → Manage MCP Servers → "Enable Studio as MCP server". Registered for ZCode in `.zcode/config.json` (workspace scope, gitignored — recreate via the important_docs note if missing).

## CRITICAL: file encoding (changed 2026-09-16)

Sources are **UTF-8** with **CRLF** line endings (comments are Russian). Git stores files byte-for-byte (`.gitattributes`: `*.luau -text`) so it never rewrites encoding or line endings — keep that rule when adding files.

- Do **not** convert sources to any other encoding; tooling (Rojo, Studio, agents) assumes UTF-8.
- History caveat: commits before `39552d1` store the same files as **Windows-1251** — reading old diffs in a UTF-8 terminal shows mojibake; pipe through `iconv -f cp1251 -t utf-8` to read them.

## Cross-file contract (do not rename unilaterally)

Scripts communicate through instances expected in the DataModel — renaming in one file breaks the others. The `ReplicatedStorage` remotes below are also **declared in `default.project.json`** with their exact classes, so a fresh Rojo connect creates any that are missing:

- **Module requires**: `SceneTransition` requires the ModuleScripts `SceneEffects`, `InventoryController`, `ElementMenu` from `ReplicatedStorage` by exact name (via `WaitForChild`). Module init signatures are documented in each file's header comment.

- **ReplicatedStorage**: RemoteEvents `RequestTeleport`, `ChangeGenderEvent`, `ChangePartColorEvent`, `EquipItem`; RemoteFunctions `GetInventoryItems`, `GetPlayerSkinColor`, `GetEquippedItems` (snapshot of worn items + chosen category colors, invoked by `InventoryController.init` at startup); BindableEvents `StartGameEvent` (client-only: fired by LoadingScript, awaited by SceneTransition), `ElementChosenEvent` and `ResetElementChoiceEvent` (client→client signals between `HoverBorder2` and `SceneTransition` — the code uses `.Event`/`:Fire()`, so the instances MUST be BindableEvents, not RemoteEvents, or both scripts error at startup); ModuleScript `ColorPicker`.
- **PlayerGui ScreenGuis**: `MainMenuGui`, `ElementMenuGui`, `CreationMenuGui`, `LoadingScreen`, `EntranceGui` (plus many named child frames/buttons).
- **ServerStorage.Gender**: rig models `Male` and `Female`.
- **`_G.PlayerSkinColors`**: server-side skin-color sync between server scripts (InventoryServer and others) — intentional `_G` usage, not a leftover.

## Conventions

- Comments, `print`/`warn` messages, and variable docs are in **Russian**; keep new comments consistent.
- Luau with occasional type annotations (e.g. `HoverBorder2`); server scripts use tabs for indentation. Rojo naming: `*.server.luau` → Script, `*.client.luau` → LocalScript, plain `*.luau` → ModuleScript.
- `HoverEffect1/2/3` are alternative iterations of the same effect, not files to merge — ask which variant is current before editing them together. `HoverBorder`/`HoverBorder2` used to be alternatives too, but `HoverBorder2` is now the only ElementMenuGui script on the critical path (element choice → final transition) — treat it as required, not superseded.
- Remote invocation hygiene (keep on new code): server validates client remote args against whitelists — equip/color categories (`VALID_EQUIP_CATEGORIES` in `InventoryServer`), teleport elements (`VALID_ELEMENTS` in `Teleport`), gender (`"male"/"female"` in `MaleFemale`).
- Client/server split follows Roblox rules: server logic in `ServerScriptService` scripts, UI logic in LocalScripts; client→server only via the RemoteEvents listed above.
- `Teleport.server.luau` passes the chosen element via `TeleportOptions:SetTeleportData({ element = ... })` — the receiving place reads this key.

## Local docs & resources

- **`D:\creator-docs`** — local git clone of the official **Roblox Creator Documentation** repo (source of <https://create.roblox.com/docs>). Use it as the offline, authoritative reference for engine APIs and guides instead of relying on memory: grep/read the markdown under `content/en-us/`. Sections most relevant to this project: `luau`, `scripting`, `ui`, `avatar`, `characters`, `reference` (Engine API reference), plus `studio/mcp.md` (Studio MCP tools) and `projects/external-tools.md` (Rojo/Rokit). It is a separate, independent git repository — treat it as read-only reference material; never commit project changes there.
- **`important_docs/`** (this repo) — folder for useful information collected while working on the project: notes, API excerpts, Studio setup details, decisions. Anything that should survive the session goes there as a markdown file (UTF-8). See `important_docs/README.md` for conventions; start with `important_docs/studio-integration.md` for the Rojo/MCP setup.

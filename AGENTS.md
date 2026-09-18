# AGENTS.md — rb_scripts

## Purpose

Roblox **Luau** scripts for a character-creation game (gender/race/skin customization, element selection, inventory, loading screen, place teleport), stored as a **Rojo project**: `default.project.json` maps the `src/` tree into Studio containers, and `rojo serve` live-syncs edits into a running Studio session. `README.md` describes the project for GitHub; this file is the agent-facing contract.

| File | Destination in Studio |
|---|---|
| `src/ReplicatedStorage/ColorPicker.luau` | ModuleScript `ColorPicker` in `ReplicatedStorage` — HSV/RGB picker, event-driven sliders (`UserInputService.InputChanged`) |
| `src/ReplicatedStorage/ColorPalettes.luau` | ModuleScript `ColorPalettes` in `ReplicatedStorage` — shared palettes + `getPleasantColor` (server randomizer & client randomizer) |
| `src/ReplicatedStorage/SceneEffects.luau` | ModuleScript `SceneEffects` in `ReplicatedStorage` — camera yaw rig + menu show/hide tweens |
| `src/ReplicatedStorage/InventoryController.luau` | ModuleScript `InventoryController` in `ReplicatedStorage` — inventories, color palettes, randomizer, equip labels |
| `src/ReplicatedStorage/ElementMenu.luau` | ModuleScript `ElementMenu` in `ReplicatedStorage` — element info frames + exported `ElementMenu.ELEMENTS` config |
| `src/ServerScriptService/InventoryServer.server.luau` | Script in `ServerScriptService` |
| `src/ServerScriptService/Teleport.server.luau` | Script in `ServerScriptService` (`GAME_PLACE_ID = 95945939718701` hardcoded) |
| `src/ServerScriptService/MaleFemale.server.luau` | gender-change server script |
| `src/ServerScriptService/ReplaceAvatarWithRig.server.luau` | Script in `ServerScriptService` (custom spawn, `CharacterAutoLoads = false`) |
| `src/ServerScriptService/PlayerDataManager.luau` | ModuleScript in `ServerScriptService` — per-player skin colors (replaced former `_G.PlayerSkinColors`) |
| `src/ServerScriptService/AnimationController.luau` | ModuleScript in `ServerScriptService` — idle replay (replaced former `_G.ReplayCharacterIdle`) |
| `src/ServerScriptService/RigParts.luau` | ModuleScript in `ServerScriptService` — R15 skin-part names shared by InventoryServer/MaleFemale |
| `src/ReplicatedFirst/LoadingScript.client.luau` | LocalScript `LoadingScript` in `ReplicatedFirst` |
| `src/StarterGui/MainMenuGui/SceneTransition.client.luau` | LocalScript in `StarterGui/MainMenuGui` — orchestrator; requires the ReplicatedStorage modules above |
| `src/StarterGui/MainMenuGui/CameraLockScript.client.luau` | LocalScript in `MainMenuGui` — sets the menu camera once (deliberately NOT re-bound every RenderStepped; transitions own the camera afterwards) |
| `src/StarterGui/MainMenuGui/MainContainer/SlotHover.client.luau` | LocalScript in `MainMenuGui/MainContainer` — single hover script for Slot1–3 (replaced the three per-slot `HoverEffect` LocalScripts, deleted 2026-09-17) |
| `src/StarterGui/HoverBorder.client.luau` | LocalScript `HoverBorder` at **`StarterGui` root** (clones to `PlayerGui` root at runtime; verified 2026-09-17 — not inside `MainMenuGui`) |
| `src/StarterGui/ElementMenuGui/HoverBorder2.client.luau` | LocalScript in `ElementMenuGui`; **load-bearing** — the only script wiring `PlayButton` → `ElementChosenEvent` (final transition); do not prune |
| `src/StarterGui/CreationMenuGui/LeftRight/RotateScript.client.luau` | LocalScript `RotateScript` inside `CreationMenuGui/LeftRight` (verified 2026-09-17) |

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

- **Module requires**: `SceneTransition` requires the ModuleScripts `SceneEffects`, `InventoryController`, `ElementMenu` from `ReplicatedStorage` by exact name (via `WaitForChild`). `InventoryController` additionally requires `ColorPicker` and `ColorPalettes`; `InventoryServer`/`MaleFemale`/`ReplaceAvatarWithRig` require the sibling SSS modules `PlayerDataManager`/`AnimationController`/`RigParts` via `script.Parent:WaitForChild(...)`. Module init signatures are documented in each file's header comment.
- **Server shared state**: no `_G` — per-player skin colors live in `PlayerDataManager`, idle replay in `AnimationController` (both ModuleScripts in `ServerScriptService`, also declared in `default.project.json`).
- **Element config**: `ElementMenu.ELEMENTS` is the single table of element button/infoFrame names, display names, and colors; `HoverBorder2` builds its lookup from it. Keep `VALID_ELEMENTS` in `Teleport.server.luau` in sync manually (it is the server-side security whitelist and stays independent by design).

- **ReplicatedStorage**: RemoteEvents `RequestTeleport`, `ChangeGenderEvent`, `ChangePartColorEvent`, `EquipItem`; RemoteFunctions `GetInventoryItems`, `GetPlayerSkinColor`, `GetEquippedItems` (snapshot of worn items + chosen category colors, invoked by `InventoryController.init` at startup); BindableEvents `StartGameEvent` (client-only: fired by LoadingScript, awaited by SceneTransition), `ElementChosenEvent` and `ResetElementChoiceEvent` (client→client signals between `HoverBorder2` and `SceneTransition` — the code uses `.Event`/`:Fire()`, so the instances MUST be BindableEvents, not RemoteEvents, or both scripts error at startup); ModuleScript `ColorPicker`.
- **ScreenGuis**: `MainMenuGui`, `ElementMenuGui`, `CreationMenuGui`, `EntranceGui` live in `StarterGui` (reach scripts as `PlayerGui` clones); **`LoadingScreen` lives in `ReplicatedFirst`** — `LoadingScript` does `ReplicatedFirst:WaitForChild("LoadingScreen")` on it (plus many named child frames/buttons).
- **ServerStorage.Gender**: rig models `Male` and `Female` (R15 — torsos are swapped via `ReplaceBodyPartR15`; part-name lists are R15-only, see `RigParts`).

## Conventions

- Comments, `print`/`warn` messages, and variable docs are in **Russian**; keep new comments consistent.
- Luau with type annotations; the small shared modules (`ColorPalettes`, `PlayerDataManager`, `AnimationController`, `RigParts`) are `--!strict`, larger GUI scripts are annotated non-strict. Server scripts use tabs for indentation. Rojo naming: `*.server.luau` → Script, `*.client.luau` → LocalScript, plain `*.luau` → ModuleScript.
- `HoverBorder`/`HoverBorder2` are NOT alternatives: `HoverBorder2` is the only ElementMenuGui script on the critical path (element choice → final transition) — treat it as required, not superseded. The former per-slot `HoverEffect` scripts in `Slot1–3` were replaced by the single `SlotHover` LocalScript in `MainContainer` (2026-09-17); the old `snippets/HoverEffect*.luau` drafts and `snippets/CameraLockScript.luau` were removed from the repo — `CameraLockScript` is now under Rojo with the live values (camera Y = 4).
- Remote invocation hygiene (keep on new code): server validates client remote args against whitelists — equip/color categories (`VALID_EQUIP_CATEGORIES` in `InventoryServer`), teleport elements (`VALID_ELEMENTS` in `Teleport`), gender (`"male"/"female"` in `MaleFemale`).
- Client/server split follows Roblox rules: server logic in `ServerScriptService` scripts, UI logic in LocalScripts; client→server only via the RemoteEvents listed above.
- `Teleport.server.luau` passes the chosen element via `TeleportOptions:SetTeleportData({ element = ... })` — the receiving place reads this key.

## Local docs & resources

- **`D:\creator-docs`** — local git clone of the official **Roblox Creator Documentation** repo (source of <https://create.roblox.com/docs>). Use it as the offline, authoritative reference for engine APIs and guides instead of relying on memory: grep/read the markdown under `content/en-us/`. Sections most relevant to this project: `luau`, `scripting`, `ui`, `avatar`, `characters`, `reference` (Engine API reference), plus `studio/mcp.md` (Studio MCP tools) and `projects/external-tools.md` (Rojo/Rokit). It is a separate, independent git repository — treat it as read-only reference material; never commit project changes there.
- **`important_docs/`** (this repo) — folder for useful information collected while working on the project: notes, API excerpts, Studio setup details, decisions. Anything that should survive the session goes there as a markdown file (UTF-8). See `important_docs/README.md` for conventions; start with `important_docs/studio-integration.md` for the Rojo/MCP setup.

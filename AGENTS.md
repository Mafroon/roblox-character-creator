# AGENTS.md — rb_scripts

## Purpose

Flat collection of standalone Roblox **Luau** script snippets stored as `.txt` files (no build system, no package manager); version-controlled with git. Each file is copy-pasted into a specific container in Roblox Studio for a character-creation game (gender/race/skin customization, element selection, inventory, loading screen, place teleport). The placement is documented in the first comment line of most files:

| File | Destination in Studio |
|---|---|
| `CameraLockScript` | camera setup snippet (menu scene) |
| `ColorPicker` | ModuleScript in `ReplicatedStorage` |
| `HoverBorder`, `HoverBorder2` | LocalScripts in `StarterGui` (MainMenuGui / ElementMenuGui); **`HoverBorder2` is load-bearing** — the only script wiring `PlayButton` → `ElementChosenEvent` (final transition); do not prune |
| `HoverEffect`, `HoverEffect2`, `HoverEffect3` | button hover snippets (inside menu GUIs) |
| `InventoryServer` | Script in `ServerScriptService` |
| `LoadingScript` | LocalScript in `ReplicatedFirst` |
| `MaleFemale` | gender-change server script |
| `ReplaceAvatarWithRig` | Script in `ServerScriptService` (custom spawn, `CharacterAutoLoads = false`) |
| `RotateScript` | LocalScript in CreationMenuGui |
| `SceneTransition` | LocalScript in `StarterGui` (MainMenuGui) — orchestrator; requires the 3 modules below |
| `SceneEffects` | ModuleScript `SceneEffects` in `ReplicatedStorage` — camera yaw rig + menu show/hide tweens |
| `InventoryController` | ModuleScript `InventoryController` in `ReplicatedStorage` — inventories, color palettes, randomizer, equip labels |
| `ElementMenu` | ModuleScript `ElementMenu` in `ReplicatedStorage` — element info frames |
| `Teleport` | Script in `ServerScriptService` (`GAME_PLACE_ID = 95945939718701` hardcoded) |

## CRITICAL: file encoding

Files are **Windows-1251** (Cyrillic comments) with **CRLF** line endings. Read/Grep tools report them as "unsupported/binary encoding" or mangle the text.

- To read: `iconv -f cp1251 -t utf-8 file.txt`
- To write: convert edits back to cp1251 and preserve CRLF. Do not silently re-encode files to UTF-8.
- Git is configured to store files byte-for-byte (`.gitattributes`: `*.txt -text`) so it never rewrites encoding or line endings. Diffs shown in UTF-8 terminals will still have mojibake in Cyrillic comments — pipe through `iconv` to read them.

## Cross-file contract (do not rename unilaterally)

Scripts communicate through instances expected in the DataModel — renaming in one file breaks the others:

- **Module requires**: `SceneTransition` requires the ModuleScripts `SceneEffects`, `InventoryController`, `ElementMenu` from `ReplicatedStorage` by exact name (via `WaitForChild`). Module init signatures are documented in each file's header comment.

- **ReplicatedStorage**: RemoteEvents `RequestTeleport`, `ChangeGenderEvent`, `ChangePartColorEvent`, `EquipItem`; RemoteFunctions `GetInventoryItems`, `GetPlayerSkinColor`, `GetEquippedItems` (snapshot of worn items + chosen category colors, invoked by `InventoryController.init` at startup); BindableEvents `StartGameEvent` (client-only: fired by LoadingScript, awaited by SceneTransition), `ElementChosenEvent` and `ResetElementChoiceEvent` (client→client signals between `HoverBorder2` and `SceneTransition` — the code uses `.Event`/`:Fire()`, so the Studio instances MUST be BindableEvents, not RemoteEvents, or both scripts error at startup); ModuleScript `ColorPicker`.
- **PlayerGui ScreenGuis**: `MainMenuGui`, `ElementMenuGui`, `CreationMenuGui`, `LoadingScreen`, `EntranceGui` (plus many named child frames/buttons).
- **ServerStorage.Gender**: rig models `Male` and `Female`.
- **`_G.PlayerSkinColors`**: server-side skin-color sync between server scripts (InventoryServer and others) — intentional `_G` usage, not a leftover.

## Conventions

- Comments, `print`/`warn` messages, and variable docs are in **Russian**; keep new comments consistent.
- Luau with occasional type annotations (e.g. `HoverBorder2`); server scripts use tabs for indentation.
- `HoverEffect1/2/3` are alternative iterations of the same effect, not files to merge — ask which variant is current before editing them together. `HoverBorder`/`HoverBorder2` used to be alternatives too, but `HoverBorder2` is now the only ElementMenuGui script on the critical path (element choice → final transition) — treat it as required, not superseded.
- Remote invocation hygiene (keep on new code): server validates client remote args against whitelists — equip/color categories (`VALID_EQUIP_CATEGORIES` in `InventoryServer`), teleport elements (`VALID_ELEMENTS` in `Teleport`), gender (`"male"/"female"` in `MaleFemale`).
- Client/server split follows Roblox rules: server logic in `ServerScriptService` scripts, UI logic in LocalScripts; client→server only via the RemoteEvents listed above.
- `Teleport.txt` passes the chosen element via `TeleportOptions:SetTeleportData({ element = ... })` — the receiving place reads this key.

## Local docs & resources

- **`D:\creator-docs`** — local git clone of the official **Roblox Creator Documentation** repo (source of <https://create.roblox.com/docs>). Use it as the offline, authoritative reference for engine APIs and guides instead of relying on memory: grep/read the markdown under `content/en-us/`. Sections most relevant to this project: `luau`, `scripting`, `ui`, `avatar`, `characters`, `reference` (Engine API reference). It is a separate, independent git repository — treat it as read-only reference material; never commit project changes there.
- **`important_docs/`** (this repo) — folder for useful information collected while working on the project: notes, API excerpts, Studio setup details, decisions. Anything that should survive the session goes there as a markdown file (UTF-8 — the cp1251 rule applies only to the Luau `.txt` snippets). See `important_docs/README.md` for conventions.

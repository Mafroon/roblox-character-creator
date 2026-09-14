# AGENTS.md — rb_scripts

## Purpose

Flat collection of standalone Roblox **Luau** script snippets stored as `.txt` files (no build system, no package manager); version-controlled with git. Each file is copy-pasted into a specific container in Roblox Studio for a character-creation game (gender/race/skin customization, element selection, inventory, loading screen, place teleport). The placement is documented in the first comment line of most files:

| File | Destination in Studio |
|---|---|
| `CameraLockScript` | camera setup snippet (menu scene) |
| `ColorPicker` | ModuleScript in `ReplicatedStorage` |
| `HoverBorder`, `HoverBorder2` | LocalScript in `StarterGui` (MainMenuGui / ElementMenuGui) |
| `HoverEffect`, `HoverEffect2`, `HoverEffect3` | button hover snippets (inside menu GUIs) |
| `InventoryServer` | Script in `ServerScriptService` |
| `LoadingScript` | LocalScript in `ReplicatedFirst` |
| `MaleFemale` | gender-change server script |
| `ReplaceAvatarWithRig` | Script in `ServerScriptService` (custom spawn, `CharacterAutoLoads = false`) |
| `RotateScript` | LocalScript in CreationMenuGui |
| `SceneTransition` | LocalScript in `StarterGui` (main menu + character editor; largest file) |
| `Teleport` | Script in `ServerScriptService` (`GAME_PLACE_ID = 95945939718701` hardcoded) |

## CRITICAL: file encoding

Files are **Windows-1251** (Cyrillic comments) with **CRLF** line endings. Read/Grep tools report them as "unsupported/binary encoding" or mangle the text.

- To read: `iconv -f cp1251 -t utf-8 file.txt`
- To write: convert edits back to cp1251 and preserve CRLF. Do not silently re-encode files to UTF-8.
- Git is configured to store files byte-for-byte (`.gitattributes`: `*.txt -text`) so it never rewrites encoding or line endings. Diffs shown in UTF-8 terminals will still have mojibake in Cyrillic comments — pipe through `iconv` to read them.

## Cross-file contract (do not rename unilaterally)

Scripts communicate through instances expected in the DataModel — renaming in one file breaks the others:

- **ReplicatedStorage**: RemoteEvents `RequestTeleport`, `ElementChosenEvent`, `ChangeGenderEvent`, `ChangePartColorEvent`, `EquipItem`, `GetInventoryItems`, `GetPlayerSkinColor`, `ResetElementChoiceEvent`; BindableEvent `StartGameEvent` (Bindable, not Remote — fired by LoadingScript, awaited by SceneTransition); ModuleScript `ColorPicker`.
- **PlayerGui ScreenGuis**: `MainMenuGui`, `ElementMenuGui`, `CreationMenuGui`, `LoadingScreen`, `EntranceGui` (plus many named child frames/buttons).
- **ServerStorage.Gender**: rig models `Male` and `Female`.
- **`_G.PlayerSkinColors`**: server-side skin-color sync between server scripts (InventoryServer and others) — intentional `_G` usage, not a leftover.

## Conventions

- Comments, `print`/`warn` messages, and variable docs are in **Russian**; keep new comments consistent.
- Luau with occasional type annotations (e.g. `HoverBorder2`); server scripts use tabs for indentation.
- `HoverEffect1/2/3` and `HoverBorder`/`HoverBorder2` are **alternative iterations** of the same effect, not files to merge — ask which variant is current before editing them together.
- Client/server split follows Roblox rules: server logic in `ServerScriptService` scripts, UI logic in LocalScripts; client→server only via the RemoteEvents listed above.
- `Teleport.txt` passes the chosen element via `TeleportOptions:SetTeleportData({ element = ... })` — the receiving place reads this key.

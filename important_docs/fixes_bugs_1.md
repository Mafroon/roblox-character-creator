# fixes_bugs_1.md — fixes applied for bugs_1.md

Date: 2026-09-14
Applies to: all `.txt` scripts changed in the same commit (see `git diff`); findings were defined in `bugs_1.md`.

## Studio-side actions required (instances, not code)

1. **Create a RemoteFunction `GetEquippedItems` in `ReplicatedStorage`** (exact name).
   Required by the new initial-equip sync: `InventoryController.init` invokes it;
   `InventoryServer` implements it (returns `equippedTable, colorsTable`).
2. **Verify instance classes in Studio**: `ElementChosenEvent` and `ResetElementChoiceEvent`
   must be **BindableEvents** (H2). The code in `HoverBorder2` + `SceneTransition` uses
   `.Event` / `:Fire()`, which only exists on BindableEvent. If Studio has RemoteEvents
   there, replace them with BindableEvents (client→client flow — RemoteEvent would be wrong anyway).
   AGENTS.md contract list was corrected accordingly.

## What was changed, per bug ID

- **H1** `SceneTransition`: `genderValue.Changed:Connect` moved inside the `if genderValue` guard
  (timeout of `WaitForChild("PlayerGender", 10)` no longer kills the script; warn + no auto-highlight).
- **H2** No code change (code was consistent BindableEvent usage); AGENTS.md reclassified the two
  events as BindableEvents; requirement documented in `HoverBorder2` header and inline comments.
- **H3** New RemoteFunction `GetEquippedItems` (server snapshot of `equippedItems` + colors).
  `InventoryController.init` fetches it after connecting `EquipItem.OnClientEvent` and initializes
  `currentEquipped`, equip labels, `currentCategoryColors` and the skin swatch. Also added:
  0.25 s click debounce on inventory item buttons (double-click toggle race).
- **H4** `InventoryServer` keeps `categoryColors[player][category]` (written by `applyCategoryColor`);
  `equipSingleItem` and `applyRace` re-apply the stored color to the fresh clone. Cleaned on PlayerRemoving.
- **M1** `ColorPicker`: slider drag loop is now `while holding and not self._isDestroyed`.
- **M2** `LoadingScript`: template missing → warn, fire `StartGameEvent`, return (no loading screen).
  Any missing child after the blocker connects → `abortLoadingScreen()`: disconnects `guiBlocker`,
  re-enables ScreenGuis, fires `StartGameEvent`, destroys the gui. Chained `WaitForChild` split into steps.
- **M3** `ElementMenu`: `Completed` callbacks check `playbackState`; state commits only on
  `Enum.PlaybackState.Completed`; on `Cancelled` only `isInfoAnimating` is reset.
- **M4** `SceneTransition`: all transition locks release from the camera tween's `Completed` (with
  playbackState guard) — no more unlock at 0.8 s vs 1.0 s camera. `SceneEffects.tweenCameraYaw`
  cancels + destroys the previous yaw tween/value before starting a new one.
- **M5** `SceneTransition.transitionToFinal`: collects original transparencies of EntranceGui
  `BackFrame`/`Frame` and all descendants (Background/Text/TextStroke/Image/UIStroke), hides them
  before enabling the GUI, fades everything back to captured originals. No Studio change needed.
- **L1** `InventoryServer`: `VALID_EQUIP_CATEGORIES` whitelist on `EquipItem` (+ itemName type check)
  and on `ChangePartColorEvent` (+ `typeof(color) == "Color3"`, `Skin` allowed for colors).
  `Teleport`: `VALID_ELEMENTS` whitelist (Fire/Water/Earth/Air/Light/Gloom — keep in sync with
  `HoverBorder2.ELEMENT_CONFIG` / `ElementMenu.ELEMENTS`).
- **L2** `SceneTransition.cameraBasePos` aligned with `CameraLockScript` → `Vector3.new(0, 8, 0)`.
  If the lower editor view (y=3) was intentional, revert this one line instead.
- **L3** `InventoryController`: randomizer unequip fires only when the category cache is non-empty;
  0.5 s debounce on the random button.
- **L4** `InventoryServer`: removed unused `startGameEvent` fetch and dead `getFirstRaceName`.
- **L5** `MaleFemale`: `gender` validated (`"male"`/`"female"`); broad "подстраховка" recolor of all
  BaseParts removed (explicit body-part list kept).
- **L6** `HoverBorder2` documented as load-bearing in its header + AGENTS.md.
- **L7** `LoadingScript` waits on `Activated` (mouse/touch/gamepad); `selectedButton.Selected` line
  dropped in `HoverBorder2`; duplicate `CustomizeLeft` chain replaced with `customizeLeft` in
  `SceneTransition`. HoverEffect1/2/3 left as-is (no divergence).

## Mechanics note (encoding)

All `.txt` edits went utf-8/LF scratch → edited → repack `perl -pe 's/\n/\r\n/' | iconv utf-8→cp1251`,
with round-trip `diff` verification per file; trailing-newline absence preserved where it existed
(ColorPicker, LoadingScript, InventoryServer, Teleport, MaleFemale, HoverBorder2).

# fixes_bugs_3.md — bugfix round 3 (palette close state, post-Continue flicker, element-click desync)

Date: 2026-09-15
Applies to: `SceneTransition.txt`, `InventoryController.txt`, `ElementMenu.txt`, `HoverBorder2.txt`
Findings reported by the user after bugfix round 2; log line numbers in the report
(`InventoryController:213` = "Открыт:", `:89` = "Все инвентари и палитры закрыты.") match the
current `.txt` files exactly, so the Studio copies were in sync with the repo before this round.

## B1 — Inventory/palette window ignores the first close click (Race, Eyes, Facial Hair, Hair)

**Repro:** open a category inventory (e.g. Race) → open its color palette → change the color →
click Accept (or Cancel) → palette closes but the inventory window stays on screen → click the
category button again: nothing visible happens, Output prints `Открыт: Inventory2Race` → only the
second click closes the window (`Все инвентари и палитры закрыты.`).

**Root cause:** `ColorPicker` Accept/Cancel both call `Destroy()`, which fires the `onClosed`
callback in `InventoryController.openColorPicker`. That callback set `currentOpenInventory = nil`
even though the *parent inventory frame* stayed `Visible = true`. The category-button toggle in
`switchToMainInventory` decides close-vs-open by comparing `currentOpenInventory` with the target
frame, so the next click took the "open" path (re-showing an already visible window + "Открыт:"
log), and only the click after that toggled closed. The same stale-state bug existed in the
palette's own toggle path (clicking the category's ColorButton while its palette is open).

**Fix (keeps the established UX: closing a palette returns you to the still-open inventory):**
`onClosed` and the toggle branch now restore `currentOpenInventory = parentInventory or nil`, so
state always matches what is on screen. The next category-button click closes the window on the
first try. Checked against every destroy path (`closeAllInventories`, `closeOtherPalettes`,
`switchToMainInventory`, SkinColor toggle) — all of them overwrite `currentOpenInventory`
afterwards, so the restore never leaks.

## B2 — CreationMenuGui flickers for a couple of seconds after Continue

**Root cause:** `SceneTransition` set `creationGui.Enabled = true` *before* running module init.
`InventoryController.init` yields on ~10 `InvokeServer` round trips (skin color, equipped
snapshot, 8 preloaded categories), so the whole editor UI sat fully visible at its edit-time
positions for those seconds, then the panels were hidden one by one — perceived as flicker.

**Fix:** `creationGui` stays disabled during init; it is enabled only *after* all panels are
hidden (`buttonContainer … randomFrame.Visible = false`). MainMenuGui still appears immediately.

## B3 — Element click spam desyncs description vs "Your Choice" (+ requested click limits)

**Repro:** rapidly clicking element buttons could leave the info frame (description) of one
element on screen while the "Your Choice" label showed another.

**Root cause:** the element buttons are listened to by *two* scripts with **independent** click
filters — `ElementMenu` (info frames; only `isInfoAnimating`/`inputEnabled`, no debounce) and
`HoverBorder2` (highlight + YourChoice label; its own private 0.3 s `tick()` debounce). When one
filter accepted a click and the other rejected it, the two UIs diverged. It also meant
`HoverBorder2` could still change the selection during transitions, where `ElementMenu` was
already locked via `setInputEnabled(false)`.

**Fix:** `ElementMenu` now owns a shared gate and exposes it to `HoverBorder2`:

- `ElementMenu.acquireClick(button)` — single decision point: transition lock + info-animation
  lock + 0.3 s debounce. For one physical click both handlers call it with the same button; the
  first call decides, the second (within 0.05 s, same button) receives the same verdict without
  re-arming the debounce. Result: clicks are accepted or rejected by *both* scripts together,
  rapid spam is ignored, and description/choice can no longer diverge.
- `ElementMenu.isClickAllowed()` — non-consuming check used by `HoverBorder2`'s PlayButton so
  Play is inert during transitions/info animations.
- `HoverBorder2` dropped its private `lastClickTime`/`DEBOUNCE_TIME` and now calls the shared
  gate in `toggleSelection`; it also requires `ReplicatedStorage.ElementMenu` at the top (the
  duplicated mid-file `local ReplicatedStorage` was removed).

## Studio-side (not script-controlled): the creation room is too tall

No `.txt` script builds or resizes the room — it is a model in `Workspace`. To lower it:

1. In the Explorer find the creation-room model (the one the editor camera frames; the camera
   sits at `(0, 8, 0)` looking straight along −Z, see `CameraLockScript`).
2. Select the ceiling part(s) and move them down; select the wall parts and reduce their
   `Size.Y`, keeping the floor at its current height. A comfortable target is a ceiling around
   Y ≈ 10–12 (room ~10–12 studs tall with the floor at Y = 0).
3. Keep the floor and the rig spawn position unchanged.
4. If you later move the camera height instead, change it in **both** places together:
   `CameraLockScript` (`targetPosition`) and `SceneTransition` (`cameraBasePos`, must stay
   equal or transitions jerk vertically).

## Smoke test for this round (Play Solo)

1. Continue → main menu appears; the editor UI must **not** flash before the first
   menu → editor transition.
2. Race (or Eyes/Hair/FacialHair): select item → ColorButton → change color → **Accept** →
   palette closes, inventory stays → click the category button once → window closes
   ("Все инвентари и палитры закрыты." in Output on the *first* click).
3. Same but with **Cancel** → color reverts, same single-click close behavior.
4. Also verify the palette's own toggle: ColorButton while palette open → closes palette,
   inventory stays; category button closes it on first click.
5. Element menu: click Fire, then spam Water/Air quickly — description and "Your Choice" always
   change together; clicks during the 0.2 s info animation are ignored; during the final
   transition Play and the element buttons are inert.

## Follow-up 2 (same day, after the user's console log)

The user's full Output log disproved the stale-module theory for the element menu and pinpointed
the idle problem, so round 3c re-architected both:

**Element menu — single decision point (ElementMenu.txt + HoverBorder2.txt).** The log matched the
current files line-for-line (`HoverBorder2:228`, `:253`), the stale-module guard did *not* fire,
and there were no red errors — yet `selectedButton` stayed nil ("Стихия не выбрана" on Play). The
remaining suspect was the two-handler design itself (two independent `Activated` connections with
a shared time/token gate — fragile under deferred signals and ordering). Restructured so this
class of failure cannot exist:

- `ElementMenu` is now the **only** script connecting the element buttons. Its internal
  `acquireClick()` (transition lock + info-animation lock + 0.3 s anti-spam) decides once per
  click and opens/closes the info frame. Rejections caused by wedged state (`inputEnabled=false`,
  `isInfoAnimating=true`) now `warn` with the reason; every accepted click prints
  `ElementMenu: <InfoFrame> -> выбрана/снята`.
- `ElementMenu.onElementToggled(listener)` broadcasts the decision `(button, isSelected)`.
- `HoverBorder2` no longer connects the element buttons at all — its scan only sets up hover
  strokes, and a listener applies highlight + `selectedButton` + `updateChoiceLabel` from the
  broadcast. Label, Play enablement and description can no longer diverge.
- `ElementMenu.isClickAllowed()` still gates `PlayButton`.
- The startup mismatch guard now checks `onElementToggled`/`isClickAllowed`. The module and
  `HoverBorder2` must be re-pasted **together** (the old API `acquireClick(button)` no longer
  exists).

If clicks still do nothing after this, the Output will now say which stage fails: no
`ElementMenu: …` print = the button never fires `Activated` (GUI/input problem); a
`клик отклонён` warning = the gate; a print without a label update = a HoverBorder2 problem.

**Idle animation — replication/ownership timing (ReplaceAvatarWithRig.txt + InventoryServer.txt).**
The log showed the track *did* start at spawn (`Кастомная idle-анимация` at 16:19:14.394) but was
only visible after a gender change — where round 3b's replay runs much later. Difference: at
spawn the server starts the track in the same window when `player.Character = rig` hands
ownership of the rig to the player's client, and `applyRandomOutfit` runs 1 ms later. Per the
Animator docs, track replication goes through the `Animator` instance, and a track started
server-side during that handoff does not reliably reach the owning client. Fixes:

- `ReplaceAvatarWithRig` creates the `Animator` **before** the rig is parented to the workspace
  (so the client never sees a character without one).
- The initial idle play is delayed (`task.delay(0.5)`), and `InventoryServer.applyRandomOutfit`
  replays it again via `_G.ReplayCharacterIdle` 1 s after the outfit settles — same mechanism as
  the gender-change replay that demonstrably worked. Expect the `Кастомная idle-анимация` prints
  ~0.5 s and ~1 s after spawn instead of at the same instant as `Заспавнен …`.

## Follow-up (same day, after user testing)

**Camera height:** the user lowered the camera instead of the room — `targetPosition` and
`cameraBasePos` are both now `Vector3.new(0, 4, 0)` (changed in Studio from `CameraLockScript`
and `SceneTransition.txt`; the pairing rule stays: the two must always be equal). Works, keep
the room model as-is.

**"Your Choice" label stopped updating / Play inert:** diagnosed as a stale paste — the new
`HoverBorder2` calls `ElementMenu.acquireClick`, which only exists in the round-3 `ElementMenu`
ModuleScript. With the old module body still in `ReplicatedStorage`, every element-button click
throws `attempt to call a nil value (field 'acquireClick')`, so selection never registers while
the (old) info frames still open. `HoverBorder2` now `warn`s at startup when the module lacks
`acquireClick`/`isClickAllowed` — if you see that warning, re-paste `ElementMenu.txt` into the
`ElementMenu` ModuleScript. The module and `HoverBorder2` must be replaced together.

**Idle animation stopped (character stiff):** the only animation code is in
`ReplaceAvatarWithRig` (unchanged since `ddababa`): it played `ServerStorage.Animations.Idle`
only if a `FindFirstChild` at script *startup* found it — silently skipping when the folder was
renamed/moved or the Animation's `AnimationId` was empty. Round 3b makes this path loud and
robust:

- `findIdleAnimation()` re-resolves the animation at every spawn and `warn`s exactly what is
  missing (no `Animations` folder / no `Idle` / not an `Animation` / empty `AnimationId`).
- Playback goes through `_G.ReplayCharacterIdle(character)` (server-side `_G`, same pattern as
  `_G.PlayerSkinColors`): stops already-playing tracks, `pcall`s `LoadAnimation`/`:Play()`.
- `MaleFemale` calls `_G.ReplayCharacterIdle` after `ReplaceBodyPartR15` torso swaps (which
  rewire Motor6Ds and can kill the playing track), so the character no longer freezes after a
  gender change. If `_G.ReplayCharacterIdle` is missing, `MaleFemale` warns to update
  `ReplaceAvatarWithRig` first.

Checklist if the character is still stiff after re-pasting: watch Output for the new
`ReplaceAvatarWithRig:` warnings; confirm `ServerStorage.Animations.Idle` exists and is an
`Animation` with a valid `AnimationId` authored for the rigs' `Humanoid.RigType` (R15 — the
game uses `ReplaceBodyPartR15`); the success path prints `Кастомная idle-анимация для …` per
spawn.

# bugs_2.md — Second review pass findings

Date: 2026-09-15
Scope: all 17 `.txt` scripts as of the post-`fixes_bugs_1` commit. This pass (a) re-verified the fixes from `bugs_1.md`/`fixes_bugs_1.md`, (b) looked for issues the first pass missed, and (c) examined cross-script interaction windows (transitions, spawn ordering, remote echo timing).

API claims verified against the offline docs clone at `D:\creator-docs`:
- `reference/engine/classes/TweenBase.yaml:116-119` — playing a second tween on the same property **cancels** the first; `:136-141` — `Completed` fires on cancel and passes `PlaybackState`.
- `reference/engine/classes/GuiButton.yaml:211-218` — `Activated` fires on desktop click, mobile touch **and console A/cross**; `MouseButton1Click` covers mouse (+touch) only.
- `reference/engine/classes/Player.yaml:2977-2979` — `CharacterAdded` fires soon after `player.Character` is set to a non-nil value (manual spawn flow is sound).

**No High findings this round** — the critical paths fixed after bugs_1 hold up. What remains is one soft-lock scenario, two state/input consistency issues, and a set of Low hygiene items.

---

## Fix gaps from bugs_1 (where the first round of fixes stopped short)

- The `playbackState` guard pattern (bugs_1 M3) was applied to `ElementMenu.showInfoFrame`/`closeInfoFrame` but **not** to `ElementMenu.closeOpenInfoFrame` (→ M1 below) and **not** to any of the `SceneEffects` show/hide `Completed` handlers (→ L3).
- The remote-validation round (bugs_1 L1) covered `EquipItem`, `ChangePartColorEvent`, `RequestTeleport` — but **not** `GetInventoryItems.OnServerInvoke` (→ L1 below).
- The gamepad fix (bugs_1 L7) was applied only to `LoadingScript`'s ContinueButton; every other button in the game is still mouse/touch-only (→ M3).

---

## Medium

### M1. Element buttons stay live during the 0.8 s menu-hide window and corrupt `ElementMenu` state
`SceneEffects.hideElementMenu` only sets `elementMenu.Enabled = false` in `backFrameTween.Completed` (`SceneEffects.txt:184-188`), i.e. 0.8 s after the transition starts. During that whole window the element buttons are still clickable while the panels slide away. Two failure shapes, both ending with `currentInfoFrame` pointing at a frame that is logically "open" but invisible:

- **Case A — no frame was open.** User clicks an element button during the window (`transitionBackToCreation` is running). `showInfoFrame` animates 0.2 s and commits `currentInfoFrame = infoFrame` (`ElementMenu.txt:84-87`) *after* the menu was disabled. Next time the element menu is enabled, the stale info frame is instantly visible, and the first click on its button takes the "close" branch (dead click).
- **Case B — a frame was open and the transition is closing it.** `closeOpenInfoFrame(0.5, true)` starts a 0.5 s tween (`SceneTransition.txt:254` → `ElementMenu.txt:150-153`). If the user re-clicks that element's button during the window, `showInfoFrame` starts a tween on the same property, which **cancels** the close tween (TweenBase.yaml:116-119). The close tween's `Completed` handler (`ElementMenu.txt:155-157`) has **no `playbackState` check** — unlike its siblings fixed in bugs_1 M3 — so it sets `Visible = false` on the frame the user just re-opened. The show tween then completes and commits `currentInfoFrame = infoFrame` anyway. Result: an "open" invisible frame; next click on the button closes nothing visible (dead click), the click after that finally re-opens.

Fix: (a) add the `playbackState == Enum.PlaybackState.Completed` check to the `closeOpenInfoFrame` handler, and (b) disable element-button input for the duration of transitions — e.g. an `ElementMenu.setInputEnabled(false)` called by `SceneTransition` when a transition starts (or reuse the `isTransitioning` flag via a shared flag/module).

### M2. Failed teleport leaves the client in an unrecoverable visual state
`transitionToFinal` is a one-way animation: MainMenuGui panels fly apart (`SceneTransition.txt:290-293`), MainContainer tweens off-screen, ElementMenuGui is disabled, the camera is parked Scriptable at the final position, and EntranceGui fades in. The teleport request is fired at `SceneTransition.txt:405`; on the server, `Teleport.txt:21-28` wraps `TeleportAsync` in `pcall` and, on failure, only `warn`s — its own comment admits retry logic is a TODO.

If the teleport fails (Throttled/Failure), the player remains in this place with no functional UI: every menu is hidden or off-screen, the character is anchored with WalkSpeed 0, and there is no path back to any screen. The only recovery is rejoining.

Fix (minimal, client-side): in `SceneTransition`, connect `TeleportService.TeleportInitFailed` and on failure restore the pre-transition state — bgLeft/bgRight back to `bgLeftOriginalPos`/`bgRightOriginalPos`, re-show the element menu (`SceneEffects.showElementMenu()` + `showYourChoiceFrame()`), reset the camera via `tweenCameraYaw(cameraBasePos, -3*math.pi/2, -math.pi, 1.0)`. (Server-side retry in `Teleport.txt` is worth adding too, but only the client fix restores UI.)

### M3. Same buttons wired with different input APIs — console support is half-broken
Per the docs, `GuiButton.Activated` fires for mouse, touch **and console** UI-navigation input; `MouseButton1Click` does not fire from console navigation. The element buttons are wired by **two** scripts with different APIs:

- `HoverBorder2.txt:184` — `button.Activated` → selection/toggle works on console;
- `ElementMenu.txt:134` — `button.MouseButton1Click` → info frame does **not** open on console.

So a console player can highlight an element, enable Play, and start the final transition — having never seen a single info frame. The same applies to every navigation button: `SceneTransition.txt:158-159` (gender), `:410-413` (slots, Back, Next), `:416` (element Back), and all of `InventoryController` (`:226`, `:237`, `:329`, `:353` — inventory buttons, palette buttons, skin color button, randomizer) are `MouseButton1Click`, i.e. a console player cannot drive the editor at all. `LoadingScript` was already migrated to `Activated` (bugs_1 L7) — the rest of the game wasn't.

Fix: mechanical replacement of `MouseButton1Click` → `Activated` in the listed spots (behavior for mouse/touch is unchanged).

---

## Low

### L1. `GetInventoryItems.OnServerInvoke` is the last unvalidated remote
`InventoryServer.txt:384-404` uses `categoryName` directly in `ServerStorage:FindFirstChild(categoryName)`. A non-string argument makes `FindFirstChild` throw inside the handler (error spam from a single FireServer), and any folder name in ServerStorage (Gender, Animations, …) can be enumerated — read-only info leak, since the cloning path is already whitelisted. Align with the other remotes: `typeof(categoryName) == "string"` + the `VALID_EQUIP_CATEGORIES`/`"Race"` whitelist (the client only ever asks for the 8 known categories, so this breaks nothing).

### L2. Equip echo is sent even when the equip silently no-ops
`InventoryServer.txt:483-484`: `equipSingleItem` returns without doing anything when `player.Character` is nil (`:140-141`), but the success echo `equipEvent:FireClient(player, { category = categoryName, item = itemName })` at `:484` runs unconditionally. In the respawn window the client's label and `currentEquipped` then show an item that was never equipped; the desync self-corrects after two clicks (toggle back through the server's real state). Fix: move the echo inside an `equipSingleItem` success return (or re-check `player.Character` before echoing).

### L3. `SceneEffects` show/hide `Completed` handlers lack the `playbackState` guard (latent)
Handlers at `SceneEffects.txt:88-90` (buttonContainer hide), `:102-104` (randomFrame hide), `:109-115` (leftRight hide + `onHidden`), `:172-174` (element ButtonContainer hide), `:184-188` (elementBackFrame hide + `elementMenu.Enabled = false`), `:195-197` (YourChoiceFrame hide) all run their side effects on **any** `Completed`, including `Cancelled` (TweenBase.yaml:136-141). Currently unreachable in practice: the `isTransitioning` lock (released only from the camera tween's `Completed`, `SceneTransition.txt:181-185` etc.) serializes transitions, and hide tweens (0.8 s) always finish before the next transition can start (camera 1.0 s — a 0.2 s margin). But the guard is one line per handler and makes the invariant explicit instead of timing-dependent.

### L4. Unguarded `WaitForChild` inside the final transition = soft-lock on a missing instance
`SceneTransition.txt:296` (`playerGui:WaitForChild("EntranceGui")`, plus `:297-298` for its frames) runs mid-transition with `isTransitioning = true`. If `EntranceGui` is missing/misnamed in Studio, the handler yields forever: the element menu is already hidden, the transition lock never releases, and **all** transitions are dead (same failure class as bugs_1 M2, which fixed LoadingScript but not this spot; `:404` `WaitForChild("RequestTeleport")` is the same pattern, though it runs post-animation). A timeout + warn + early release would degrade to "no entrance screen" instead of a locked editor.

### L5. Teleport request fires before the entrance animation it's supposed to follow
Timeline in `tweenAngle.Completed` (`SceneTransition.txt:369-406`): forward tween runs 1.2 s from t=2.5→3.7; the EntranceGui fade starts at t=3.1; but `task.wait(0.5)` at `:401` — commented "пауза после анимации" — only reaches t=3.0, so `RequestTeleport:FireServer` fires **before** both the movement ends and the fade begins. Harmless today (network teleport latency masks it), but the comment is wrong and any future "wait for the animation" logic will be built on sand. If firing after the animation is intended, move `:404-405` into the `tweenForward.Completed` handler next to `:394-399`.

### L6. Double-click on an inventory button closes the inventory it just opened
`switchToMainInventory` (`InventoryController.txt:196-217`) sets `currentOpenInventory = targetFrame` (`:211`) and *then* populates via a yielding `InvokeServer` (`:101`). A second click arriving during that yield sees `currentOpenInventory == targetFrame` and takes the toggle-close branch (`:197-199`) — the panel the user double-clicked opens and immediately closes, while the populate finishes into the hidden frame. Add the same small debounce the equip/random buttons already have, or set a "populating" flag around `populateInventory`.

### L7. Mangled emoji: literal `?`/`??` bytes in print/warn strings
Confirmed at byte level (e.g. `ReplaceAvatarWithRig.txt:64` starts `print("\x3f\x3f Заспавнен…")`): the emoji that once decorated these messages were destroyed by the UTF-8→cp1251 repack and are now literal question marks. Affected: `ReplaceAvatarWithRig.txt:64,73`; `InventoryServer.txt:219,322,359,419,431,433`; `Teleport.txt:26`; `HoverBorder2.txt:218`; `MaleFemale.txt:52,92,95`. Cosmetic log noise — but also a standing trap: cp1251 cannot encode emoji, so any future edit pasting them in will silently lose them the same way. Either clean them out or replace with ASCII markers (`[OK]`, `[ERR]`).

### L8. Spawn scripts handle only *future* `PlayerAdded`, with no `GetPlayers()` backfill
`ReplaceAvatarWithRig.txt:20` and `InventoryServer.txt:368` only connect `Players.PlayerAdded`. If a player object already exists when these run (Studio Play Solo race, team-test edge), no rig is spawned and `InventoryServer` never attaches `CharacterAdded` — no outfit, no `PlayerGender`, dead session. The `task.wait(0.1)` at `ReplaceAvatarWithRig.txt:52` only protects the *ordering of the two `CharacterAdded` connections* for players who join after both scripts connect. Standard hardening: after connecting, iterate `Players:GetPlayers()` and run the same join logic for existing players.

### L9. `HoverEffect` hardcodes stroke defaults on MouseLeave
`HoverEffect.txt:5-6` (`defaultThickness = 1`) and `:33-36` (reset `Transparency = 0.3`) don't capture the button's actual stroke values, unlike `HoverBorder`/`HoverBorder2` which do. On any button whose real stroke isn't thickness 1 / transparency 0.3, the first hover permanently rewrites those properties. Only matters if these snippets are still placed on buttons (they're the retained "alternative iterations"); noting for whenever the three copies get consolidated.

---

## Fixes from bugs_1 re-verified (all hold)

- **H1** — `genderValue.Changed` now inside the nil guard (`SceneTransition.txt:136-144`).
- **H2/H3** — BindableEvent contract documented in both headers; `GetEquippedItems` snapshot fetched in `InventoryController.init` (`:434-448`) *after* `EquipItem.OnClientEvent:Connect` (`:425`), so no spawn echoes can be lost in the window; 0.25 s equip debounce present (`:115-117`).
- **H4** — `categoryColors` re-applied in `equipSingleItem` (`InventoryServer.txt:150-159`) and `applyRace` (`:192-205`); cleaned on `PlayerRemoving` (`:377`).
- **M1** — ColorPicker drag loop checks `self._isDestroyed` (`ColorPicker.txt:96`); `Destroy` idempotence via `_isDestroyed` (`:166`).
- **M2** — LoadingScript abort path disconnects `guiBlocker`, re-enables GUIs, fires `StartGameEvent`, destroys the gui (`LoadingScript.txt:54-64`); chained WaitForChild split into nil-checked steps (`:77-82`).
- **M4** — All four transition locks release from the camera tween's `Completed` with a `playbackState` guard (`SceneTransition.txt:181-185, 205-209, 232-236, 267-271`); `tweenCameraYaw` cancels + destroys the previous yaw tween/value and its cleanup is guarded against a superseded tween (`SceneEffects.txt:226-250`).
- **M5** — EntranceGui fade collects and hides descendants' Background/Text/TextStroke/Image/UIStroke transparency before enabling the GUI (`SceneTransition.txt:303-332`).
- **L2** — `cameraBasePos = Vector3.new(0, 8, 0)` matches `CameraLockScript` (`SceneTransition.txt:76`).
- **L5** — `MaleFemale` validates gender (`:32-35`); the broad all-BasePart recolor is gone.
- **L1 (Teleport)** — `VALID_ELEMENTS` whitelist in place (`Teleport.txt:35-48`).

## Checked and found OK (new this round)

- **Custom-spawn event chain**: `player.Character = rig` does fire `CharacterAdded` (Player.yaml:2977-2979), so InventoryServer's spawn handler runs; `PlayerGender` is created by ReplaceAvatarWithRig after the assignment with no yields in between, so InventoryServer's "default male" fallback (`InventoryServer.txt:347-360`) can't race it.
- **Randomizer ↔ server semantics**: required-category re-rolls that pick the already-worn item correctly produce no echo (server `:473-479` silent, client `currentEquipped` already matches); optional-category chance-fail unequips with `{category, item=nil}` (omitted key → client sets nil, label "..."); Race no-op on same race (`:453`). Client and server agree in every branch.
- **ColorPicker lifecycle**: `Destroy()` always invokes `onClosed`, and both `closeAllInventories` and `switchToMainInventory` destroy pickers *before* reassigning `currentOpenInventory`, so the onClosed cleanup can't clobber the new state; Cancel-button revert (`ColorPicker.txt:156-161`) re-fires the initial color and closes — correct preview semantics.
- **Mouse.X vs AbsolutePosition in the picker sliders** (`ColorPicker.txt:97`): only the horizontal axis is used, and the GUI inset is vertical-only, so the coordinate spaces agree — no offset bug.
- **`RotateScript`** — `currentRotation` capture-once remains safe: nothing rewrites the rig CFrame after spawn (gender swap only replaces torso parts).
- **`HoverBorder`** (CollectionService version) — correctly scoped to playerGui descendants and handles late-added tagged buttons.
- **`HoverEffect1/2/3`** — still byte-identical modulo indentation; no divergence to merge.

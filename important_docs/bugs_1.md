# bugs_1.md — Code review findings

Date: 2026-09-14
Scope: all 17 `.txt` scripts (`CameraLockScript`, `ColorPicker`, `ElementMenu`, `HoverBorder`, `HoverBorder2`, `HoverEffect`, `HoverEffect2`, `HoverEffect3`, `InventoryController`, `InventoryServer`, `LoadingScript`, `MaleFemale`, `ReplaceAvatarWithRig`, `RotateScript`, `SceneEffects`, `SceneTransition`, `Teleport`).
API claims below were checked against the offline docs clone at `D:\creator-docs` (notably `reference/engine/enums/PlaybackState.yaml`, which confirms `TweenBase.Completed` fires on **both** `Completed` and `Cancelled`).

Severity: **High** = crash or broken gameplay flow; **Medium** = visible malfunction in a plausible scenario; **Low** = robustness / security hygiene / cosmetic.

---

## High

### H1. `SceneTransition.txt:136` — crash when `PlayerGender` times out
Line 26 uses `player:WaitForChild("PlayerGender", 10)`, which returns `nil` after the 10 s timeout. Line 131 guards the nil (`if genderValue then`), but **line 136 uses `genderValue.Changed:Connect(...)` unguarded**. If the StringValue isn't replicated within 10 s (server lag, join during a restart), the whole LocalScript errors out and the main menu never becomes functional.

Fix: either drop the timeout (`WaitForChild("PlayerGender")` — the value is created server-side on spawn, so it *will* arrive), or move line 136 inside the `if genderValue` guard / re-check for nil.

### H2. Event class mismatch: `ElementChosenEvent` / `ResetElementChoiceEvent` used as BindableEvents, documented as RemoteEvents
The code uses BindableEvent-only API in four places:
- `HoverBorder2.txt:222` — `chosenEvent:Fire(config.Name)`
- `HoverBorder2.txt:181` — `resetChoiceEvent.Event:Connect(deselectAllButtons)`
- `SceneTransition.txt:235-236` — `resetChoiceEvent:Fire()`
- `SceneTransition.txt:370` — `ElementChosenEvent.Event:Connect(...)`

`RemoteEvent` has no `.Event` signal and no `:Fire(...)`; those exist only on `BindableEvent`. But AGENTS.md classifies both as **RemoteEvents** in the ReplicatedStorage contract list (unlike `StartGameEvent`, which it explicitly marks as Bindable). One of the two is wrong:

- If the Studio instances really are **RemoteEvents**, both `HoverBorder2` and `SceneTransition` throw at runtime — `HoverBorder2` dies on line 181, and `SceneTransition` dies on line 370 during init, so the final "choose element → Play" flow can never work.
- If they are **BindableEvents** (which the code consistently assumes), the code is fine but AGENTS.md misdocuments the contract.

Fix: verify the instance classes in Studio and reconcile — either reclassify them in AGENTS.md as BindableEvents, or convert the code to the RemoteEvent API (`OnClientEvent` / `FireServer`). Note that a client→client flow like this *should* be a BindableEvent (a RemoteEvent round-trip through the server would be pointless here), so most likely AGENTS.md needs the fix.

### H3. Server never syncs initial outfit state → first click on a worn item behaves inverted
`InventoryServer.applyRandomOutfit` (lines 198, 214, 231, 236) echoes each equip via `equipEvent:FireClient(...)` — but it runs in `onCharacterAdded` at spawn, while the client connects `EquipItemEvent.OnClientEvent` only inside `InventoryController.init`, i.e. after the loading screen is dismissed. All spawn-time echoes are lost.

Consequences in the editor:
- Client-side `currentEquipped` is empty, so all equip labels show `"..."` even though the character is fully dressed.
- First click on the currently worn **optional** item (Hair / FacialHair / Extra): the client thinks it's not equipped and sends `FireServer(cat, name)`; the server hits its "already equipped" branch (`InventoryServer.txt:427-434`) and **unequips** the item — the opposite of what the label implied.
- First click on a worn **required** item (Shirt/Pants/Eyes/Mouth/Race): the server silently rejects (no echo), so the label never updates at all until the player switches to a different item.

Fix: on `InventoryController.init`, invoke a server RemoteFunction returning the current `equippedItems[player]` snapshot (the data already exists) and initialize `currentEquipped` / labels from it. A client-side debounce on item clicks would additionally close the rapid-double-click toggle race.

### H4. Chosen category color is lost when re-equipping an item or switching race
The server persists only the skin color (`_G.PlayerSkinColors`). `equipSingleItem` (`InventoryServer.txt:121-134`) and `applyRace` (`InventoryServer.txt:150-172`) clone fresh template models without re-applying the category's current color.

Scenario: pick a red hair color → equip a different hair → the new hair appears in its default template color, while the client palette still shows red (`InventoryController.currentCategoryColors.Hair` unchanged). Same for Race: switching race resets the race color chosen earlier. (`applyRandomOutfit` is unaffected because it equips *and then* colors within one call.)

Fix: store per-player per-category colors server-side (e.g. alongside `_G.PlayerSkinColors`), and apply the stored color inside `equipSingleItem` / `applyRace` after parenting the clone.

---

## Medium

### M1. `ColorPicker.txt:94-100` — infinite per-frame loop if the picker is destroyed mid-drag
The slider drag loop is `while holding do ... RunService.RenderStepped:Wait() end`. `holding` is only reset by the `InputEnded` connection — but `ColorPicker:Destroy()` **disconnects both connections**. If the picker is destroyed while the user is holding a slider (e.g. a transition calls `InventoryController.closeAll()`), `holding` can never become `false`: the loop runs every frame forever, calling `UpdateUI()` and `_fireColorChanged()` → `ChangePartColorEvent:FireServer(...)` spam at 60+ calls/sec.

Fix: break out of the loop when destroyed, e.g. `while holding and not self._isDestroyed do`, or re-check `self._isDestroyed` inside the loop body.

### M2. `LoadingScript.txt` — a single failed `WaitForChild` leaves the session permanently broken
The script connects `guiBlocker` (line 38), which force-disables **every** ScreenGui ever added to PlayerGui, and only disconnects it after the user clicks Continue (line 83). If anything between line 38 and line 83 fails, the script dies, the blocker stays connected forever, `StartGameEvent` never fires, and `SceneTransition` (which has no timeout at `SceneTransition.txt:21-22`) waits forever — a black, unusable game. Unguarded failure points:

- Lines 54-55: `backFrame:WaitForChild("Names",5):WaitForChild("Name",5):WaitForChild("Draft",5)` — any nil makes line 55 (`draftFrame:WaitForChild(...)`) error. Also, chained `WaitForChild` on a nil intermediate errors, contradicting the nil-checked style of lines 44-50.
- Line 28 (before the blocker, but still fatal): `ReplicatedFirst:WaitForChild("LoadingScreen", 10):Clone()` errors if the template is missing/late.

Fix: nil-check each step and on failure disconnect `guiBlocker` before returning (or re-enable previously disabled GUIs), so a failed loading screen degrades to "no loading screen" instead of a dead session.

### M3. `ElementMenu.txt` — `Completed` fires on cancel, corrupting the info-frame state machine
Per the docs (`TweenBase.Completed` fires for both `Completed` and `Cancelled`), the callback in `showInfoFrame` (lines 50-53 → 70-73) runs even when the tween was cancelled by a newer tween. If `closeOpenInfoFrame` (called by every scene transition) interrupts an in-flight open animation, the show callback still executes afterwards and sets `currentInfoFrame = infoFrame` / `isInfoAnimating = false` — the module now believes a frame is open that the transition just closed. The next element-button click then takes the "close previous" path on an invisible frame, and a later `closeOpenInfoFrame` tweens a hidden frame.

Fix: in the callbacks, check the `playbackState` argument: only commit state `if playbackState == Enum.PlaybackState.Completed`.

### M4. `SceneTransition.txt` — transition lock releases before the camera tween ends; overlapping yaw tweens fight
- `returnToMenu` (lines 166-174) releases `isTransitioning` via `hideCreationUI`'s callback at ~0.8 s, but its camera tween runs 1.0 s. Same in `transitionBackToCreation` (lines 242-254, `onHidden` at 0.8 s vs 1.0 s camera).
- `SceneEffects.tweenCameraYaw` (lines 215-234) creates a **new** `NumberValue` per call and never cancels a previous yaw tween. If the user manages to start the next transition inside that ~0.2 s window, two `Changed` handlers both write `camera.CFrame` every frame (flicker), and the new tween interpolates from a hardcoded start angle while the camera hasn't arrived yet (visible snap).

Fix: unlock from the camera tween's `Completed` only, and/or have `tweenCameraYaw` cancel a stored previous tween before starting a new one.

### M5. `SceneTransition.txt:278-286` — EntranceGui fade only affects frame backgrounds
`transitionToFinal` sets `entranceGui.Enabled = true` immediately, while hiding the two frames solely via `BackgroundTransparency = 1`. Any **children** of `BackFrame`/`Frame` (text labels, buttons, images) are unaffected by `BackgroundTransparency` and will be fully visible the instant the GUI is enabled — long before the 0.6 s fade-in runs. Whether this is visible depends on how EntranceGui is built in Studio.

Fix: use a `CanvasGroup` with `GroupTransparency` for the fade, or set the children's own transparency/`Visible` in step with the tween.

---

## Low

### L1. `InventoryServer.txt` — no input validation on remotes (exploiter-friendly)
- `equipEvent.OnServerEvent` (line 372): `categoryName` is used directly in `ServerStorage:FindFirstChild(categoryName)`. Any folder in ServerStorage is a "category" — e.g. `FireServer("Gender", "Male")` passes the checks and `equipSingleItem` clones the **entire Male rig** onto the character. Same for `Animations` or any other folder. Fix: whitelist `categoryName` against the known set (Shirt, Pants, Eyes, Mouth, Hair, FacialHair, Extra, Race).
- `changeColorEvent.OnServerEvent` (line 442): neither `category` nor `color` is validated; a non-Color3 value makes `desc.Color = color` throw inside the handler (error spam, partial recolors). Fix: `typeof(color) == "Color3"` check + category whitelist.
- `Teleport.txt:32-34`: `chosenElement` is passed unvalidated into `TeleportOptions:SetTeleportData` — the receiving place will read arbitrary attacker-chosen data. Validate against the known element list.

### L2. Camera base mismatch between `CameraLockScript.txt` and `SceneTransition.txt`
The initial menu camera sits at `(0, 8, 0)` FOV 55 (`CameraLockScript.txt:7`), but every transition tweens around `cameraBasePos = Vector3.new(0, 3, 0)` (`SceneTransition.txt:72`). Result: the first menu→editor click hard-cuts the camera from y=8 to y=3, and after Menu → Editor → Menu the camera rests at `(0, 3, 0)` — a different framing than the opening shot. If unintended, align `cameraBasePos` (or CameraLockScript) with the other.

### L3. `InventoryController.txt:365-372` — randomizer unequips optional categories when the cache is empty
If a `categoryItemCache[opt.name]` entry is `nil`/empty (e.g. `GetInventoryItems` returned `{}` or preload failed), the `else` branch still fires `FireServer(opt.name, nil)` — unconditionally stripping an item the player equipped manually. Also, the random button has no debounce and issues ~12 remote calls per click. Guard the else branch on `items and #items > 0` (only unequip on a genuine "didn't roll it" when items exist, or skip when the category is unknown).

### L4. `InventoryServer.txt` — dead code
- Line 16: `startGameEvent` is fetched and never used. Worth noting it could never work anyway: `StartGameEvent` is a BindableEvent fired from the **client**, and BindableEvents don't cross the client/server boundary — a server-side connection would never fire. Remove it (and never "fix" it by connecting).
- Lines 137-147: `getFirstRaceName` is never called.

### L5. `MaleFemale.txt` — unvalidated gender param and a broad recolor fallback
- Line 33: `local rig = (gender == "male") and maleRig or femaleRig` — any value other than `"male"` (including garbage from an exploiter) silently selects the female rig. Validate `gender == "male" or gender == "female"` and return otherwise.
- Lines 84-88 ("подстраховка") recolor **every** direct `BasePart` child of the character with the skin color. Equipped items are normally Models, but if any category folder ever contains a bare BasePart item, it would get painted skin-colored on gender change. Recoloring an explicit body-part list (as lines 72-82 already do) is safer.

### L6. `HoverBorder2.txt` is load-bearing, not an alternative
AGENTS.md groups `HoverBorder`/`HoverBorder2` as "alternative iterations", but in the current architecture `HoverBorder2` is the **only** script wiring `PlayButton` → `ElementChosenEvent` (lines 214-233); the new `ElementMenu` module handles only info frames, and `SceneTransition` only *listens*. Deleting `HoverBorder2` as "superseded" would make the element menu a dead end — the game could never reach the final transition. Document this dependency (in AGENTS.md and/or the file header) before anyone prunes it. Also note `ElementChosenEvent`/`ResetElementChoiceEvent` class verification (H2) blocks this file too.

### L7. Cosmetic / minor
- `LoadingScript.txt:81` — `continueButton.MouseButton1Click:Wait()` ignores gamepad/console input; `Activated:Once()` covers mouse, touch and gamepad.
- `HoverBorder2.txt:159` — `selectedButton.Selected = false` has no visual effect: per the docs, `GuiButton.Selected` only alters legacy `Enum.ButtonStyle` Roblox* presets, not Custom-styled buttons. Harmless, can be dropped.
- `SceneTransition.txt:111` — `creationGui:WaitForChild("CustomizeLeft"):WaitForChild("Frame")...` duplicates the already-resolved `customizeLeft` (line 52). Style only.
- `HoverEffect2.txt` / `HoverEffect3.txt` are functionally identical (only indentation differs); `HoverEffect.txt` differs from them by indentation alone. Confirms AGENTS.md's "alternative iterations" note — no divergence to merge, but also no reason to keep three copies unless they target different buttons.

---

## Checked and found OK (for the record)

- **PlayerGender default race** (`InventoryServer.txt:313-326` vs `ReplaceAvatarWithRig.txt:56-62`): benign. `ReplaceAvatarWithRig` assigns the correct value synchronously right after `player.Character = rig`, before InventoryServer's yielded handler reaches its `"male"` default; the final value is always correct.
- **`Humanoid:ReplaceBodyPartR15`**, **`TeleportService:TeleportAsync` + `TeleportOptions:SetTeleportData`**, **`Animator:LoadAnimation`** — verified present in the offline engine reference.
- **`SceneEffects.tweenCameraYaw` cleanup** — `angleVal:Destroy()` in `Completed` disconnects the `Changed` writer; no leak in the normal path.
- **`InventoryController` populate/destroy cycle** — re-population destroys attribute-tagged children, so old `Activated` connections die with their instances.
- **`RotateScript`** — client-side CFrame writes on the server-anchored rig persist locally (server never rewrites the CFrame), which is all the menu preview needs; velocity zeroing is redundant but harmless.

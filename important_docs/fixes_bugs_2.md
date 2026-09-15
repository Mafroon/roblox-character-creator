# fixes_bugs_2.md — fixes applied for bugs_2.md

Date: 2026-09-15
Applies to: 12 `.txt` files changed in the same commit (see `git diff`); findings were defined in `bugs_2.md`.

## Studio-side actions required

**None.** No new instances, no renames. All fixes are code-only. (The M2 restore
uses the client-side `TeleportService.TeleportInitFailed`, which per the docs
`reference/engine/classes/TeleportService.yaml:1065-1067` fires on the client too.)

## What was changed, per bug ID

- **M1** `ElementMenu`: new module API `ElementMenu.setInputEnabled(enabled)` —
  a click gate checked in `onElementButtonClicked`. `SceneTransition` disables
  input in `transitionBackToCreation` / `transitionToFinal` (while the element
  menu GUI is still active during its ~0.8 s hide animation) and re-enables in
  `transitionFromCreation`. Additionally: `showInfoFrame` now sets
  `currentInfoFrame` **immediately** (not in `Completed`), so a transition that
  starts mid-animation finds the frame via `closeOpenInfoFrame` and closes it
  cleanly instead of leaving it orphaned; `closeOpenInfoFrame`'s
  `hideOnComplete` handler got the `playbackState` guard that its siblings
  already had. Element buttons switched to `Activated` (matching HoverBorder2).
- **M2** `SceneTransition`: client-side `TeleportInitFailed` handler + a
  `restoreAfterTeleportFailure` closure assigned inside `transitionToFinal`.
  On failure it: tweens bgLeft/bgRight back to their original positions,
  disables EntranceGui, re-enables element input, re-shows the element menu
  (`showElementMenu` + `showYourChoiceFrame` — the selected element in
  HoverBorder2 is preserved, so Play works again) and tweens the camera from
  the final yaw (-3π/2) back to the element-menu view (-π). Also triggered as
  a fallback when `RequestTeleport` is missing or `CurrentCamera` is nil.
- **M3** `MouseButton1Click` → `Activated` (gamepad/console support; mouse and
  touch behavior unchanged) in: `SceneTransition` (gender buttons, Slot1/Slot2,
  Back, Next, element Back), `InventoryController` (all inventory buttons,
  all palette color buttons, skin color button, randomizer), `ElementMenu`
  (element info buttons). HoverBorder2 already used `Activated`.
- **L1** `InventoryServer`: `GetInventoryItems.OnServerInvoke` now validates
  `categoryName` (`typeof == "string"` + `VALID_EQUIP_CATEGORIES` whitelist,
  which includes `"Race"`) and returns `{}` otherwise — same policy as the
  other remotes.
- **L2** `InventoryServer`: `equipSingleItem` returns `true`/`false`; the
  equip echo `FireClient` is sent only on a real equip, so a character-missing
  race window no longer shows the client an item that isn't worn.
- **L3** `SceneEffects`: all six show/hide `Completed` handlers
  (buttonContainer, randomFrame, leftRight+onHidden, element ButtonContainer,
  element BackFrame + `Enabled=false`, YourChoiceFrame) now check
  `playbackState == Enum.PlaybackState.Completed`.
- **L4** `SceneTransition.transitionToFinal`: `EntranceGui`/`BackFrame`/`Frame`
  are fetched (10 s timeout) **before** any menu is hidden; if missing, the
  transition rolls back cleanly (input re-enabled, `isTransitioning = false`,
  warn) instead of infinite-yielding with the UI hidden.
- **L5** `SceneTransition`: the `RequestTeleport:FireServer(chosenElement)` moved
  into `tweenForward.Completed` (with its own `playbackState` guard), so the
  teleport request is sent only after the camera move and entrance fade finish;
  the stale `task.wait(0.5)` + early-fire block was removed.
- **L6** `InventoryController`: 0.25 s debounce (`lastInventoryClickTime`) in
  `connectMainButton`, so a double-click can no longer toggle-close an inventory
  while `populateInventory`'s `InvokeServer` is still in flight.
- **L7** Removed the mangled `?`/`??`/`???` print prefixes (literal 0x3F bytes
  left over from an old UTF-8→cp1251 repack) in `InventoryServer` (5),
  `ReplaceAvatarWithRig` (2), `MaleFemale` (3), `Teleport` (1),
  `HoverBorder2` (1). Reminder: cp1251 cannot encode emoji — don't paste them
  into these files.
- **L8** `ReplaceAvatarWithRig` and `InventoryServer`: join logic extracted
  into `spawnPlayer` / `onPlayerAdded`, connected to `PlayerAdded` **and**
  back-filled over `Players:GetPlayers()` (covers players that joined before
  the script started, e.g. Studio Play Solo). No yields between the connect
  and the back-fill loop, so a player can't be processed twice.
- **L9** `HoverEffect`/`HoverEffect2`/`HoverEffect3` (all three kept identical):
  MouseLeave now restores the stroke's real captured `Thickness`/`Transparency`
  instead of hardcoded `1` / `0.3`.

## Verification performed

- **Encoding round-trip**: every file edited as UTF-8 scratch, repacked with
  `iconv -f utf-8 -t cp1251` (CRLF preserved by the editor), then re-decoded
  and `diff`-ed against the scratch — byte-identical for all 12 files.
  PowerShell byte audit: pure CRLF (0 lone LF) and trailing-byte state
  (`\n`, `d`, `)`, space) matches the originals exactly.
- **Syntax check**: parsed old vs new sources with `luaparser` (Lua 5.3
  grammar). 10/12 parse clean; `ReplaceAvatarWithRig` and `HoverBorder2` fail
  **identically in the originals** on pre-existing Luau-only syntax (if-expression
  at line 22 / type annotations) — valid Luau, not a parser-supported feature.
  No new syntax errors.
- **Full diff review** of every hunk (readable via `git diff | iconv`).

## Known residual limitations (accepted)

- If a teleport fails **exactly during** the 0.6 s entrance fade-in and the
  player immediately re-runs the final transition, the fade target values are
  re-captured mid-fade, so the entrance overlay can end up slightly more
  transparent than the true original. Window is ~sub-second; consequence is
  cosmetic only.
- The teleport-failure restore leaves `camera.CameraType = Scriptable` set
  (consistent with the rest of the flow, which is scriptable throughout).
- `Players:GetPlayers()` back-fill processes an existing player even if their
  `PlayerAdded` is queued in the same scheduler tick — not possible here
  because there is no yield between `Connect` and the back-fill loop.

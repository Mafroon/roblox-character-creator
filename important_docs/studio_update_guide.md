# studio_update_guide.md — Migrating Studio from the old 14-file setup to the current 17-file setup

Date: 2026-09-15
Applies to: the game as built from the initial commit `ddababa` (14 `.txt` snippets) being updated
to the current repo state (`3f007d2` module refactor + `fe756e3` bugfix round 1 + the current
uncommitted bugfix round 2, findings in `bugs_2.md`, changes in `fixes_bugs_2.md`).

**TL;DR:** nothing gets deleted. 11 of the old 14 scripts get their **content replaced** with the
current `.txt`, 3 old scripts stay **as-is**, and you **create 4 new things** (3 ModuleScripts +
1 RemoteFunction) plus verify two events are BindableEvents. Full checklists below.

> **Addendum (2026-09-15, bugfix round 3 + follow-ups, `fixes_bugs_3.md`):** `SceneTransition`,
> `InventoryController`, `InventoryServer`, `ElementMenu`, `HoverBorder2`, `ReplaceAvatarWithRig`
> and `MaleFemale` changed after this guide was written — same instances, same containers, just
> paste the **current** `.txt` bodies when you reach Step 3. `HoverBorder2` requires the
> `ElementMenu` ModuleScript and **warns at startup if that module's body is outdated** — if you
> see that warning, re-paste `ElementMenu.txt` into the module. `ElementMenu` and `HoverBorder2`
> must be updated together (element-click handling moved into the module), and
> `ReplaceAvatarWithRig` must be updated together with or before `MaleFemale` (idle replay via
> `_G.ReplayCharacterIdle`).

---

## Step 0 — Before you start: encoding

The `.txt` files are **Windows-1251** (Cyrillic comments). If you open them in VS Code and see
mojibake, do *Reopen with Encoding → Windows 1251* first, then copy. Pasting into the Studio
script editor is safe either way (only comments/strings are non-ASCII).

## Step 1 — CREATE these new instances (skip what you already did after fixes_bugs_1)

| # | Instance name | Class | Parent in DataModel | Source |
|---|---------------|-------|---------------------|--------|
| 1 | `SceneEffects` | ModuleScript | `ReplicatedStorage` | `SceneEffects.txt` |
| 2 | `InventoryController` | ModuleScript | `ReplicatedStorage` | `InventoryController.txt` |
| 3 | `ElementMenu` | ModuleScript | `ReplicatedStorage` | `ElementMenu.txt` |
| 4 | `GetEquippedItems` | **RemoteFunction** | `ReplicatedStorage` | no .txt — implemented inside `InventoryServer.txt` |

Names must match exactly — `SceneTransition` requires the three modules by name, and
`InventoryController.init` invokes `GetEquippedItems` at startup (if it's missing, the main menu
hangs; the missing instance is visible in Output as an infinite-yield warning).

## Step 2 — VERIFY these instance classes (client→client events)

- `ElementChosenEvent` and `ResetElementChoiceEvent` in `ReplicatedStorage` must be
  **BindableEvents**, not RemoteEvents. `HoverBorder2` and `SceneTransition` use `.Event`/`:Fire()`,
  which only exists on BindableEvent — with RemoteEvents both scripts error at startup.
- While you're there, confirm the rest of the ReplicatedStorage contract exists:
  BindableEvent `StartGameEvent`; RemoteEvents `RequestTeleport`, `ChangeGenderEvent`,
  `ChangePartColorEvent`, `EquipItem`; RemoteFunctions `GetInventoryItems`, `GetPlayerSkinColor`;
  ModuleScript `ColorPicker`; `Templates.InventoryItemTemplate` (template for inventory items).
  Full contract table: `AGENTS.md`.

## Step 3 — REPLACE content of these 11 old scripts (same container, just paste the new body)

| Old script in Studio | Container (unchanged) | Current source | Why it changed |
|---|---|---|---|
| `SceneTransition` | LocalScript in `StarterGui.MainMenuGui` | `SceneTransition.txt` | Rewritten as thin orchestrator: requires the 3 modules, owns all transitions, teleport-failure restore, EntranceGui guard, Activated buttons |
| `InventoryServer` | Script in `ServerScriptService` | `InventoryServer.txt` | Remote whitelists, `GetEquippedItems` implementation, category colors persistence, spawn backfill |
| `Teleport` | Script in `ServerScriptService` | `Teleport.txt` | Element whitelist |
| `MaleFemale` | Script in `ServerScriptService` | `MaleFemale.txt` | Gender validation, safe skin recolor |
| `ReplaceAvatarWithRig` | Script in `ServerScriptService` | `ReplaceAvatarWithRig.txt` | Join backfill (`GetPlayers`), cleaned prints |
| `LoadingScript` | LocalScript in `ReplicatedFirst` | `LoadingScript.txt` | Abort path can no longer brick the session; gamepad Continue |
| `HoverBorder2` | LocalScript in `StarterGui.ElementMenuGui` | `HoverBorder2.txt` | Load-bearing script (PlayButton → ElementChosenEvent) — do **not** delete it; header/comment updates |
| `ColorPicker` | ModuleScript in `ReplicatedStorage` | `ColorPicker.txt` | Slider drag loop can no longer spin forever after Destroy |
| `HoverEffect` | snippet inside its menu-GUI button | `HoverEffect.txt` | MouseLeave restores real stroke values |
| `HoverEffect2` | snippet inside its menu-GUI button | `HoverEffect2.txt` | same |
| `HoverEffect3` | snippet inside its menu-GUI button | `HoverEffect3.txt` | same |

Note on `SceneTransition`: the old monolith body is fully replaced by the new orchestrator — do not
keep a copy of the old body anywhere (a second script driving the same GUIs would fight the new one).

Note on `HoverEffect1/2/3`: they are alternative iterations, each placed inside the specific button
that uses it. If a given GUI doesn't actually use one of them, there is nothing to update there.

## Step 4 — LEAVE these 3 old scripts as-is (never changed since the initial commit)

| Script | Container |
|---|---|
| `CameraLockScript` | camera setup snippet (menu scene) |
| `HoverBorder` | LocalScript in `StarterGui.MainMenuGui` (MainMenu hover effect, CollectionService tag `HoverBorder`) |
| `RotateScript` | LocalScript in `CreationMenuGui` |

They are byte-identical to the initial commit — no action needed.

## Step 5 — Recommended order and smoke test

Order: create the Step-1 instances first, then replace the server scripts, then the client
scripts (`SceneTransition` last — it waits for the modules). Studio caches nothing between edits,
so a full **Stop → Play** after every batch is enough.

Smoke test (Play Solo):

1. Loading screen → press Continue → main menu appears (no red errors in Output; ignore the
   mojibake-era `??` prints only if you haven't updated that script).
2. Menu → editor: camera rotates left, editor panels animate in.
3. Editor: equip labels show the random spawn outfit (not all `...`); open an inventory, change a
   color, click the worn item's label check; randomizer reshuffles everything.
4. Gender buttons highlight instantly and swap torso parts; skin tone is kept.
5. Next → element menu: clicking an element opens its info frame, selection highlights,
   YourChoiceFrame shows the name, Play is inert until a selection is made.
6. Back → editor → Next again: menu is functional a second time (no stuck info frames).
7. Play → final flight: camera rises/rotates, EntranceGui fades in, teleport fires.
8. Optional but recommended: repeat 5–7 with a gamepad (all menu buttons are `Activated` now).

## Reference

- Current placement of all 17 files: table in `AGENTS.md`.
- What changed between the old and new script bodies, per bug: `bugs_1.md` + `fixes_bugs_1.md`
  (round 1) and `bugs_2.md` + `fixes_bugs_2.md` (round 2).

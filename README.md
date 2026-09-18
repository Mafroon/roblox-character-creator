# rb_scripts — Roblox Character Creation & Element Selection

Luau sources for a Roblox character-creation lobby: gender and race
customization, clothing/hair inventories with live color palettes (custom
HSV/RGB picker), an element-selection menu with a cinematic final
transition, and a teleport into the main game place.

Managed as a [Rojo](https://rojo.space) project: `default.project.json`
maps the `src/` tree into Studio containers, so the scripts hot-sync into
a live Studio session while the GUI itself is hand-built in the place
file.

## Features

- **Custom character spawn** — `CharacterAutoLoads = false`; the player
  receives a cloned R15 rig (random gender) from `ServerStorage.Gender`,
  pinned in place with a custom idle animation.
- **Full customization editor** — inventories for Shirt / Pants / Eyes /
  Mouth / Hair / FacialHair / Extra / Race, equip labels, a one-click
  randomizer with weighted probabilities, and per-category color
  palettes backed by a custom HSV/RGB `ColorPicker`.
- **Gender swap in place** — torsos are replaced via
  `Humanoid:ReplaceBodyPartR15`, skin color is preserved and the idle
  animation is restarted.
- **Element menu** — six elements with info frames, hover highlights,
  "your choice" preview, and a camera fly-through finale that requests a
  teleport with the chosen element (validated against a whitelist).
- **Loading screen** — `ReplicatedFirst` override with gradient
  animation and an emergency-abort path that always unlocks the session.

## Architecture

Client/server split follows standard Roblox practice: gameplay/security
logic lives in server Scripts, all UI logic in LocalScripts; the client
talks to the server exclusively through the remotes declared in
`default.project.json` (they are created automatically on a fresh Rojo
connect). Client↔client signals use `BindableEvent`s.

```
ReplicatedStorage (ModuleScripts + remotes)
├─ ColorPicker          HSV/RGB picker class (event-driven sliders)
├─ ColorPalettes        shared palettes for server randomizer & client randomizer
├─ SceneEffects         menu show/hide tweens + camera yaw rig
├─ InventoryController  inventories, palettes, equip labels, randomizer
└─ ElementMenu          element info frames + shared ELEMENTS config

ServerScriptService
├─ ReplaceAvatarWithRig custom R15 spawn (CharacterAutoLoads = false)
├─ InventoryServer      equip/unequip, races, recoloring, spawn outfit
├─ MaleFemale           gender swap (ReplaceBodyPartR15, skin preserved)
├─ Teleport             whitelisted teleport with SetTeleportData
├─ PlayerDataManager    per-player state (skin colors) — replaces _G
├─ AnimationController  idle replay shared by the scripts above
└─ RigParts             R15 body-part names for skin repaint

ReplicatedFirst
└─ LoadingScript        custom loading screen + StartGameEvent handshake

StarterGui
├─ HoverBorder          CollectionService-tagged button borders
├─ MainMenuGui          CameraLockScript, SlotHover (Slot1–3 hover FX),
│                       SceneTransition — the client orchestrator
├─ ElementMenuGui       HoverBorder2 — element choice → ElementChosenEvent
└─ CreationMenuGui      RotateScript — turntable character rotation
```

Every script starts with a header comment (in Russian) describing its
purpose, dependencies, and the contract with its neighbors.

### Security notes

All client→server remotes validate their arguments against whitelists:
equip/color categories (`VALID_EQUIP_CATEGORIES`), teleport elements
(`VALID_ELEMENTS`), and gender (`"male"/"female"`). The chosen element
travels to the destination place via
`TeleportOptions:SetTeleportData({ element = ... })`.

## Setup

Requirements: [Rokit](https://github.com/rojo-rbx/rokit) toolchain
(Rojo 7.6.1 pinned in `rokit.toml`) and Roblox Studio.

```bash
git clone <this repo>
cd rb_scripts
rokit install          # installs the pinned Rojo
rojo serve             # start the sync server (port 34872)
```

Then in Studio: open your place → **Plugins → Rojo → Connect**. All
scripts and remotes appear in the DataModel; further edits to `src/**`
hot-sync.

### Expected place contents (hand-built, not in this repo)

| Instance | Purpose |
|---|---|
| `ServerStorage.Gender.Male` / `.Female` | R15 rig templates |
| `ServerStorage.Animations.Idle` | `Animation` with a valid `AnimationId` |
| `ServerStorage.Race.<RaceName>` | folders of race attachments |
| `ServerStorage.Shirt/Pants/Eyes/...` | item folders per category |
| `ReplicatedStorage.Templates.InventoryItemTemplate` | inventory cell template |
| `StarterGui` GUIs | `MainMenuGui`, `CreationMenuGui`, `ElementMenuGui`, `EntranceGui` |
| `ReplicatedFirst.LoadingScreen` | loading screen template |

The destination place id is hardcoded in
`src/ServerScriptService/Teleport.server.luau` (`GAME_PLACE_ID`).

## Conventions

- Sources are **UTF-8 with CRLF**; comments and log messages are in
  Russian. Git stores them byte-for-byte (`*.luau -text` in
  `.gitattributes`).
- Shared state between server scripts goes through ModuleScripts
  (`PlayerDataManager`, `AnimationController`) — `_G` is not used.
- Rojo naming: `*.server.luau` → `Script`, `*.client.luau` →
  LocalScript, `*.luau` → ModuleScript. New shared modules must also be
  declared in `default.project.json`.

## License

[MIT](LICENSE) — free to reuse with attribution.

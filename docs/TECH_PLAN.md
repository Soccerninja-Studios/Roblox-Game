# Mow the Kingdom - Technical Plan

> **Status:** current as of 2026-07-26. The architecture and golden rules below have held
> since the start of the project. The milestone list was replaced with the live roadmap in
> section 7, and superseded module plans are recorded in `docs/SCRAPPED.md`.

## 1. Toolchain

| Tool | Purpose |
|------|---------|
| **Roblox Studio** | The engine and editor. The game runs and is published from here. |
| **VS Code** | Where all game code lives and is edited. |
| **Git + GitHub** | Version control. All code and design docs live in this repository. |
| **Rojo** | Syncs `src/` from this repo into Roblox Studio in real time. |
| **Aftman** | Pins the toolchain versions (see `aftman.toml`). |

**Why Rojo?** Studio normally stores scripts inside a binary place file, which cannot be
version-controlled. Rojo keeps every script as a plain `.luau` file in this repo and
mirrors them into Studio automatically.

## 2. Project Structure

```
roblox-game/
├── default.project.json      # Rojo config: maps src/ folders into Roblox services
├── aftman.toml               # Toolchain versions
├── assets/                   # .rbxmx models + images/ (PNGs uploaded manually)
├── docs/                     # Design + technical documentation
└── src/
    ├── server/
    │   ├── init.server.luau  # Server entry point (bootstraps all services)
    │   └── Services/         # One module per game system
    ├── client/
    │   ├── init.client.luau  # Client entry point (bootstraps all controllers)
    │   └── Controllers/      # One module per client system
    └── shared/               # Code and config used by both server and client
        └── GameConfig.luau   # All tunable game numbers in one place
```

Mapping (see `default.project.json`):

- `src/server` → `ServerScriptService.Server`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client`
- `src/shared` → `ReplicatedStorage.Shared`
- `assets/*.rbxmx` → `ReplicatedStorage.Assets`

## 3. Architecture

### 3.1 Golden rules

1. **The server is the source of truth.** All currency, upgrade, and progress changes
   happen on the server. The client only *requests* actions and *renders* results.
2. **All tunable numbers live in `GameConfig.luau`.** Costs, multipliers, zone sizes,
   spawn positions - never hardcoded inside logic.
3. **One module per system.** Services (server) and Controllers (client) each own one
   responsibility.

### 3.2 Bootstrap pattern

`init.server.luau` requires every ModuleScript under `Services/`, then calls `Init(services)`
and `Start()` on each. **Every require and every lifecycle call is wrapped in `pcall`,** so
one broken module cannot take down the whole server. `init.client.luau` does the same for
`Controllers/`.

This exists because of a real outage: a single Luau compile error in one service once
killed the entire server bootstrap through an unguarded require loop.

### 3.3 Server services (15)

| Service | Responsibility |
|---------|----------------|
| `PlayerDataService` | Profile load/cache/save, DataStore, session locking, migrations |
| `GrassService` | Owns grass state; validates cut requests; awards clippings |
| `MapService` | Builds the plains, the five rings, and scattered scenery |
| `ToolService` | Grants and swaps held tools; zone gating |
| `ShopService` | The shop stall, its zone, and purchase routing |
| `UpgradeService` | Tool tiers and upgrade purchases |
| `ClippingsService` | Physical clipping drops and pickup |
| `BackpackService` | The five zone backpacks: purchase, upgrade, equip, capacity |
| `AutoMowerService` | Autonomous mowers: seek, cut, haul, deposit |
| `GardenerService` | The banking NPC and deposit zone |
| `QuestService` | Quest progress, completion, rewards |
| `QuestGiverService` | The quest-giver NPC and board |
| `CutsceneService` | The intro cutscene and the world reveal |
| `DistrictService` | **Legacy.** Orphaned by the scrapped village; pending removal |
| `AdminService` | Server-validated admin panel for testing |

### 3.4 Client controllers (10)

| Controller | Responsibility |
|------------|----------------|
| `UIController` | HUD, shop modal, all shared UI primitives |
| `MowController` | Input handling, swing, sends cut requests |
| `ToolController` | Tool visuals and equip state |
| `BackpackController` | Backpack panel and worn pack model |
| `AutoMowerController` | Mower panel: buy, deploy, recall |
| `QuestController` | Quest board UI |
| `CutsceneController` | Client-side cutscene playback and skip |
| `DashController` | Dash on Q |
| `EffectsController` | Particles, sounds, popups, screen shake |
| `AdminController` | Admin panel UI |

### 3.5 Shared modules (8)

`GameConfig`, `Remotes`, `Assets`, `StatCalculator`, `QuestData`, `CutsceneData`,
`NpcRig`, `MowerRig`.

`NpcRig` and `MowerRig` exist to **sanitize imported models**: toolbox assets arrive with
embedded scripts that throw `LoadUnownedAsset` errors and run unwanted logic, so both
modules strip scripts and rebuild joints before use.

### 3.6 Client-server communication

- All remote names are declared in one central list in `Remotes.luau` and fetched by name.
- `RemoteEvent`s for actions (RequestCut, PurchaseUpgrade) and state pushes.
- The server **always validates**: is the player near that grass? Can they afford it?
  Have they reached that zone? Cut requests are rate-limited to the swing-speed cap.

## 4. Grass System (performance strategy)

Naively placing millions of grass parts would crash any device. Instead:

1. **Tag-driven surfaces.** Any part tagged `GrassSurface` grows grass on its local **+Y**
   top face. Attributes `GrassType` and `GrassHeight` control the result, with
   `MAX_TILES_PER_SURFACE` as a safety cap.
2. **Chunked tiles.** Each surface is subdivided into tiles. A tile is the unit of cutting
   and the unit of reward - clippings pay out only on a **full clear**.
3. **Server state is numbers, not parts.** The server tracks per-tile remaining health in
   tables.
4. **Armor gates progression.** Each grass type subtracts flat armor from every swing, so
   tougher grass literally requires better tools.

## 5. UI Layering (mandatory convention)

The HUD `ScreenGui` uses **`ZIndexBehavior.Global`**. Any new UI element **must** set an
explicit `ZIndex` or it will render behind the shop modal and appear not to exist.

| Layer | ZIndex |
|-------|--------|
| Modal background | 10 |
| Cards, lists, notices | 11 |
| Card children | 12 |
| Bar fills and bar text | 13 |

This cost three debugging attempts once, including a diagnostic message that was itself
invisible for the same reason. **If an element drawn by one file is visible while an
element drawn by another is not, suspect layering before suspecting data.**

## 6. Data Persistence

- Roblox **DataStore** with session locking, autosave every 120s, save on leave and on
  `BindToClose`, and retry with backoff.
- If a load fails, the player gets a **non-saving temporary profile** so a DataStore
  outage degrades gracefully instead of overwriting real data.
- **Never call `DataStoreService:GetDataStore()` at module top level.** In an unpublished
  place it throws, the module fails to load, and every dependent system cascades into
  `attempt to index nil` errors far from the real cause. It is called inside `Init`.

### Profile schema (v5)

```lua
{
  version = 5,
  clippings = 0, gold = 0, diamonds = 0,
  bagTier = 1,                 -- LEGACY, retained only as a capacity fallback
  backpacks = { owned = {}, level = {}, autoDeposit = {}, equipped = "basket" },
  totalBladesCut = 0,
  toolTier = 1,
  skills = {},
  zones = {},
  prestige = 0,
  quests = { progress = {}, claimed = {}, reached = {} },
  autoMowers = { owned = {}, deployed = {} },
}
```

**Migration history:**

| Bump | Change |
|------|--------|
| v1 → v2 | Clippings stopped being the spendable currency; banked clippings moved into gold |
| v2 → v3 | Added the `autoMowers` block |
| v3 → v4 | Single upgradeable bag became five per-zone backpacks (generous grant) |
| v4 → v5 | Ring 3/4 zone keys renamed: `Moss` → `Mossmire`, `Thick` → `Thicket` |

> The v5 remap matters because `quests.reached` is keyed by zone and **is** persisted.
> Without it, every existing player would silently lose their ring 3 and ring 4 unlocks -
> which also re-locks those zones' quests, backpacks, and auto-mowers, since all three
> gate on `quests.reached`.

## 7. Roadmap

Ordered. Items above the line are done.

**Done:** scaffold, core mowing, grass types and armor, physical clipping drops, DataStore
persistence, plains map, intro cutscene, economy (bag/gold/diamonds/Gardener), 11-tool
ladder, 150 quests, admin panel, dash, autonomous auto-mowers, tabbed Shop UI, 5 zone
backpacks.

---

| # | Item |
|---|------|
| 1 | **Tools & swords pass** - register the remaining tool models in Rojo, convert Model/Accessory assets to Tools, own-and-equip-at-will shop overhaul |
| 2 | **Combat foundation** - player HP, damage, death, the recoverable clippings pile |
| 3 | **Monsters & bosses** - per-zone spawn model, 5 bosses, essence drops |
| 4 | **Pets (15)** - awarded by chance per tile cleared, 3 per zone |
| 5 | **Neighbors (5)** - one rescuable per zone, permanent buffs |
| 6 | **Abilities (8)** - hotkey actives |
| 7 | **Auto-mower anchors** - 4 deploy anchors per zone with travel between them |
| 8 | **Hub + TeleportService** - solo saves, co-op does not |
| 9 | **Monetization** - gamepasses, dev products, cosmetics |
| 10 | **Achievements** |
| 11 | **Grass persistence across sessions** |
| 12 | **Prestige** - needs a new name; Desert / Frost / Shadow variants |

## 8. Cleanup Backlog

| Item | Note |
|------|------|
| `DistrictService` + `District` attribute + `ServerStorage.DistrictLife` | Orphaned by the scrapped village |
| `GameConfig.BAG_TIERS` | Purchase path removed; table survives only as a pre-v4 capacity fallback in `PlayerDataService` |
| `ratePerSec` on auto-mowers | Decorative; income now comes from grass actually cut |
| `workspace.Kingdom` | Theme leftover; rename with the game title |
| Unregistered tool models | Meadow Trimmer, Bramble Sickle, Thornbite Machete, Bogblade, Ironfang Scythe, and `PlainsAssets` are not in `default.project.json`, so tools still render procedurally |
| `QuestData` ring 3/4 reward tiers | Inverted relative to grass difficulty - see `PROGRESSION.md` |

## 9. Manual Studio Steps

These cannot be done from code and must be done in Studio:

- **Enable API access** for DataStores to work.
- **Force R6 avatars** in Game Settings, or cutscene animations silently fail.
- **Upload `assets/images/*.png`** and paste the resulting IDs into `src/shared/Assets.luau`.
- Set `GameConfig.INTRO_CUTSCENE = true` to exercise the cutscene and reveal path.

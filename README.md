# Mow the Kingdom (Roblox)

An incremental Roblox game: mow an entire overgrown medieval kingdom, one blade at a time, upgrading from rusty shears to a robo-mower fleet.

- 📘 [Game Design Blueprint](docs/GAME_DESIGN.md)
- 🛠️ [Technical Plan](docs/TECH_PLAN.md)

## One-time setup (do these in order)

1. **Install Roblox Studio**: go to [create.roblox.com](https://create.roblox.com), log in with your Roblox account, click **Get Studio** and install it.
2. **Install Git**: download from [git-scm.com](https://git-scm.com/downloads) and install with default options.
3. **Install VS Code**: download from [code.visualstudio.com](https://code.visualstudio.com) and install.
4. **Clone this repository**: open VS Code → press `Ctrl+Shift+P` → type `Git: Clone` → press Enter → paste `https://gitlab.com/businessmans1984-group/roblox-game.git` → pick a folder → click **Open** when asked.
5. **Install the Rojo extension**: in VS Code, click the Extensions icon (four squares, left sidebar) → search `Rojo` → install **Rojo – Roblox Studio Sync** (by evaera).
6. **Install the Rojo Studio plugin**: press `Ctrl+Shift+P` → type `Rojo: Open Menu` → Enter. If prompted, let it install the Rojo binary. In the menu, click **Install Roblox Studio Plugin**.

## Every time you work on the game

1. Open the project folder in VS Code.
2. Press `Ctrl+Shift+P` → `Rojo: Open Menu` → click **default.project.json** to start the sync server (status bar shows Rojo running).
3. Open **Roblox Studio** → create/open a place (**New → Baseplate** the first time, then **File → Save to Roblox As...** to keep it).
4. In Studio: **Plugins** tab → **Rojo** button → **Connect**.
5. Code now syncs live from VS Code into Studio. Press **Play** (F5) in Studio to test.

### Verifying it works
After connecting and pressing Play, open the Output window in Studio (**View → Output**). You should see lines like:

```
[Server] Initialized PlayerDataService
[Server] Mow the Kingdom server is running!
[Client] Mow the Kingdom client loaded!
```

If you haven't tagged any grass surfaces yet, you'll also see `No GrassSurface tags found - building demo map.` and a demo field + mossy hut will appear so you can test right away.

## Placing grass on YOUR map (for builders)

You build the kingdom (walls, roofs, ground) by hand. To cover any part in grass that the
player can cut down, **tag** that part:

1. In Studio, open **View → Tag Editor**.
2. Create a tag named exactly **`GrassSurface`** (once).
3. Select any Part you want covered (a floor, a roof, a wall pad) and click the tag to apply it.

When the game runs, the server grows a grid of grass tiles out of that part's **top face**
(its local +Y), matching the part's rotation. So:

- **Ground / floors** → tag the flat part; grass stands straight up.
- **Roofs** → tag the (tilted) roof part; grass tilts to match it.
- **Walls** → lay a thin part flat against the wall, rotate it so its **top points outward**, then tag it; grass grows out of the wall.

When the player cuts all the grass off a part, the tiles disappear and reveal the building/ground underneath.

### Optional per-part attributes (in the Properties window → Attributes)

| Attribute      | Type   | What it does                                                        |
|----------------|--------|--------------------------------------------------------------------|
| `GrassType`    | String | Which grass type to grow (`Meadow`, `Wild`, `Thick`, `Moss`, `Ironweed`). Default `Wild`. |
| `GrassHeight`  | Number | Override how tall the grass stands, in studs.                       |

### Grass types & tool gating

Each grass type has its own **defense** (armor + health). A swing only cuts if the tool's
cut power beats the grass's armor, so tougher grass literally needs better tools + the
**Sharp Blades** power upgrade. Rough guide with default tools:

| Grass type | Toughness  | Cut by                                       | Clips when cleared |
|------------|-----------|-----------------------------------------------|--------------------|
| Meadow     | very soft | anything                                      | 3                  |
| Wild       | soft      | anything                                      | 6                  |
| Moss       | medium    | Sickle+ (or Rusty Shears with Sharp Blades)   | 15                 |
| Thick      | tough     | Sickle+ / more power                          | 25                 |
| Ironweed   | very tough| Scythe + power upgrades                        | 80                 |

Clippings are paid out **only when a tile is fully cut down**, and each grass type grants a
**set amount** (above) no matter how many swings it took — so a stronger tool that clears a
tile in fewer hits still yields the full reward, and Wild grass always gives at least 6. That
amount is the guaranteed minimum; the **Greener Thumb** upgrade and any gamepass / global boost
(via a player's `ClipMultiplier` attribute) raise it, and a rare Golden Blade crit multiplies it.

All balance numbers live in `src/shared/GameConfig.luau` — tweak them there.

## Playing the current build

- You spawn holding a **cutting tool** (a real, held item). Mowing requires it equipped — if you unequip it (hotbar / `1`), equip it again.
- **Hold left-click** (or hold on touch) while pointing at grass near you to mow. Grass starts **tall** and **shrinks on every swing**, disappearing after a few cuts. Stronger tools + Sharp Blades cut faster and get through tougher grass.
- Cut grass **drops clippings on the ground**. Walk near them to vacuum them up — the **Clipping Magnet** upgrade widens that pickup range.
- The **🛒 Shop** button on the **right side** opens the upgrade menu anytime; you can also just **walk into the market stall** near spawn and it opens automatically (and closes when you leave). A **glowing green circle** on the ground marks the exact area where the shop opens. If your model includes a **ProximityPrompt**, holding the interact key opens the shop too. All upgrades (tools + Kingdom Skills) live in that menu.

## The world map (zones)

The map is **built automatically in code** from `GameConfig.ZONES` — you don't have to place anything in Studio. On server start, `MapService` builds a stone **spawn plaza** (which holds the spawn point and the shop) followed by a contiguous strip of **grass zones** laid out in progression order:

| Zone | Grass | Harvest with |
| --- | --- | --- |
| Meadow | Meadow Grass | Rusty Shears (starter) |
| Wildfields | Wild Grass | Rusty Shears |
| Mossy Hollow | Creeping Moss | Sickle |
| The Thicket | Thicket | Sickle |
| Ironweed Expanse | Ironweed | Scythe |

Each zone is one ground pad, tagged so `GrassService` grows the right grass on it. Tougher grass has more armor, so you literally can't harvest a zone until you've bought a tool that out-powers it — **that's the world progression** (mow Meadow/Wildfields with the starter shears → afford the Sickle → clear Moss/Thicket → afford the Scythe → tackle Ironweed).

**To add or change a zone,** edit `GameConfig.ZONES` (one line per zone: name, grass type, length, ground color, required tool). To reshape the whole strip (plaza size, depth, ground thickness, colors), edit `GameConfig.WORLD`. No code changes needed for either.

You can still hand-build in Studio too: any part you tag with **`GrassSurface`** (with a `GrassType` attribute) grows grass the same way, so you can replace or extend the generated map whenever you like. The old demo sandbox is now off (`DEMO_ENABLED = false`).

## Saving & progress (persistence)

Player progress (clippings, tool tier, Kingdom Skills, stats) is saved to Roblox **DataStores** and reloaded when a player rejoins. You don't have to do anything in-game — it saves automatically:

- **On leave** and **on server shutdown** (a final save runs for everyone still in-game).
- **Every 2 minutes** in the background while playing.
- A **session lock** stops two servers from editing the same player at once (this is what prevents progress rollbacks and item duplication).
- If a load ever fails, that player gets a **temporary profile that is never saved**, so a glitch can't wipe real progress.

**Important — to test saving in Studio:** DataStores only work if API access is enabled. Go to **Game Settings → Security → Enable Studio Access to API Services** (turn it on). You must also have **published** the place to Roblox at least once (**File → Save to Roblox As...**). Without this you'll see load/save warnings in the Output and progress won't persist in Studio — it will still work in the live game once published.

If you ever need to wipe everyone's data during development, change `STORE_NAME` in `PlayerDataService.luau` (e.g. `"PlayerData_v2"`).

## Custom models (shop, tools, buildings)

Hand-built models live in the `assets/` folder as `.rbxmx` files and are synced into `ReplicatedStorage.Assets` by Rojo. The game clones them at runtime.

- **`assets/Shop.rbxmx`** → `ReplicatedStorage.Assets.Shop`. Spawned by `ShopService` at `SHOP_POSITION` (resting on the ground). It must contain a part named **`ShopZone`** — the code reshapes that into the visible circular area (radius = `SHOP_ZONE_RADIUS`). Any `Sign`, NPC, or `ProximityPrompt` inside the model is kept.
- **`assets/Shears.rbxmx`** → `ReplicatedStorage.Assets.Shears`. Cloned by `ToolService` for the tier-1 tool. It must be a `Tool` with a `Handle` part; a `Motor6D` named **`Pivot`** joining the two scissor halves is animated as the snip.

To add or replace a model: right-click it in Studio → **Save to File** as `.rbxmx`, drop it in `assets/`, and (for a brand-new asset) add an entry under `ReplicatedStorage.Assets` in `default.project.json`.

## Project layout

```
src/
  server/
    init.server.luau
    Services/
      PlayerDataService.luau   # profiles + state replication (M2 DataStore: autosave, session lock)
      GrassService.luau        # coats tagged surfaces; handles cutting + grass types
      ClippingsService.luau    # dropped clipping pickups + walk-near collection
      UpgradeService.luau      # tool tiers + Kingdom Skills purchases
      ToolService.luau         # builds/gives the held cutting tool per tier
      ShopService.luau         # spawns the Shop model; makes ShopZone a visible circle
      MapService.luau          # builds the spawn plaza + grass zones from GameConfig.ZONES
  client/
    init.client.luau
    Controllers/
      MowController.luau        # input; requires a tool equipped
      ToolController.luau       # equip state + swing/snip animation
      UIController.luau         # HUD, right-side buttons, shop modal
      EffectsController.luau    # grass bursts, +N popups, too-tough feedback
  shared/
    GameConfig.luau            # all tunable numbers (grass types, tools, skills)
    StatCalculator.luau        # profile -> gameplay stats
    Remotes.luau               # client<->server events
```

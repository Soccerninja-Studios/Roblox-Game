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

## The world map (villages & castle)

The world is a **kingdom of 5 villages ringed around a central castle**. Each village is a **zone** (Village 1–5, the Castle is zone 6). You start in **Village 1** and only unlock the next village once you've fully cleared the one before it. Every village has its own **gardener** (where you deposit clippings) and its own **shop**, plus roads linking it to its two neighbouring villages and one road up to a castle gate. The look is inspired by the villages of *Medieval Dynasty* — timber-framed houses, thatch and slate roofs, a well in the square, market stalls, barns, and fields.

`MapService` builds the whole thing **automatically in code** on server start — you don't place anything in Studio.

### Village 1 — "Greenhollow" (built now)

The starting village is now shaped like a real **Medieval Dynasty** settlement: an **oval palisade wall** rings the whole village, and the **buildings line the inside of the wall facing inward** onto an **open central common**. It's built on a **large continuous ground** (no floating baseplate — the default Baseplate is removed and replaced with a 380×380 village floor surrounded by open countryside stretching ~800 studs in every direction).

The wall has four **gates**, one at each end of the oval, each facing the center:

- **South gate — the entrance.** You now spawn on a small **arrival plaza just *outside* the south gate** (the bottom of the reference picture), facing north straight into the village, with a **"Greenhollow"** welcome sign.
- **North gate — a new road that runs out the top toward the Castle.**
- **East & west gates — roads out to the adjacent villages** (Village 2 to the east, Village 5 to the west).

The three non-entrance gates are signed **Locked** until you unlock them. Inside, a **worn ring path** loops around the common linking the districts.

The village is split into **four districts** arranged around the oval (matching the reference photo), each covered in grass that you mow to uncover it:

- **The Village Square** (the open common in the middle) — a **bonfire in the northwest corner**, a **herd of cows grazing** in the middle, a well, the **Gardener's Hut** (deposit clippings) near the **Shop**, market stalls, the **Town Hall** on the north side, big shade trees, a cart, and villagers.
- **Residential Row** (north arc, top of the picture) — **thatched longhouses**, **family houses** and a **cottage** lining the wall, plus a shared well.
- **The Craftsmen's Quarter** (east arc) — **Blacksmith** (working forge with fire + anvil), **Tavern** ("The Rusty Tankard"), **Storehouse**, a **Windmill** with turning blades, and a market stall.
- **The Farmstead** (south + west arcs, bottom-left) — a big **Barn**, farmhouse, sheds, storehouse, **plowed fields** with scarecrows, hay bales, and a fenced pasture.

**Building look:** to match the picture, houses now wear **thatched (straw) roofs** on timber-framed walls, with the big **longhouses** stretched out along the top. Every building still has **closed, tapered gable ends**, solid **doors**, glass **windows**, and timber **corner beams**, and they're spaced around the ring so they face the common and don't overlap.

Around the village is **open world detail**: a forest of scattered trees, rocks and bushes, rolling **hills**, and a **lake** to the southwest.

### Overgrowth & bringing the village to life

The whole village starts **buried under grass** — every district's **ground is carpeted** in cuttable grass, and the **rooftops are overgrown** too (roof grass is cosmetic; you don't need to reach it). Mowing uncovers the village bit by bit.

When you **fully mow a district's ground**, that district comes to life: its hidden **villagers and animals appear** (the Square brings out the herd of **cows** grazing on the common plus townsfolk; the Farmstead brings out cows, sheep, pigs, and chickens; the other districts bring out townsfolk), and a banner announces *"<District> restored — its people return!"* Clear all four districts and Greenhollow is declared **fully restored** — which is what will unlock Village 2.

- The villagers and animals are **non-interactable** (decorative life) for now, built hidden in `ServerStorage.DistrictLife` and moved into the world the moment their district is clear.
- District grass is gentle **Meadow** (in the Square, so brand-new players can always clear it with the starter Rusty Shears) and **Wild** grass elsewhere — nothing that would soft-lock a player without upgrades.
- Detection is automatic: `MapService` tags each district's ground with a `District` attribute, `GrassService` passes that tag onto every grass tile, and `DistrictService` counts them down and fires the reveal.

### Villages 2–5 and the Castle (coming next)

These aren't built yet. Village 1's gates and roads already point where the connections will go — the **east/west roads run out to Villages 2 & 5** and the **north road runs out toward the Castle** — and each future village will get its own gardener, shop, and unique layout. Zone-unlock gating (clear a village → unlock the next) is planned to hook into the `GardenerSpot`/`ZoneKey` tags already placed.

You can still hand-build in Studio too: any part you tag with **`GrassSurface`** (with a `GrassType` attribute) grows grass the same way, so you can extend the generated map whenever you like. The old demo sandbox is off (`DEMO_ENABLED = false`), and the previous zone-strip layout (`GameConfig.ZONES`/`WORLD`) is superseded by the village map though left in config for reference.

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

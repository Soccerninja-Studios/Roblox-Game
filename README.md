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

| Grass type | Toughness  | Cut by                                   |
|------------|-----------|-------------------------------------------|
| Meadow     | very soft | anything                                  |
| Wild       | soft      | anything                                  |
| Moss       | medium    | Sickle+ (or Rusty Shears with Sharp Blades) |
| Thick      | tough     | Sickle+ / more power                       |
| Ironweed   | very tough| Scythe + power upgrades                    |

All balance numbers live in `src/shared/GameConfig.luau` — tweak them there.

## Playing the current build

- You spawn holding a **cutting tool** (a real, held item). Mowing requires it equipped — if you unequip it (hotbar / `1`), equip it again.
- **Hold left-click** (or hold on touch) while pointing at grass near you to mow. Grass starts **tall** and **shrinks on every swing**, disappearing after a few cuts. Stronger tools + Sharp Blades cut faster and get through tougher grass.
- Cut grass **drops clippings on the ground**. Walk near them to vacuum them up — the **Clipping Magnet** upgrade widens that pickup range.
- The **🛒 Shop** button on the **right side** opens the upgrade menu anytime; you can also just **walk into the market stall** near spawn and it opens automatically (and closes when you leave). All upgrades (tools + Kingdom Skills) live in that menu.

## Project layout

```
src/
  server/
    init.server.luau
    Services/
      PlayerDataService.luau   # profiles + state replication (M1 in-memory)
      GrassService.luau        # coats tagged surfaces; handles cutting + grass types
      ClippingsService.luau    # dropped clipping pickups + walk-near collection
      UpgradeService.luau      # tool tiers + Kingdom Skills purchases
      ToolService.luau         # builds/gives the held cutting tool per tier
      ShopService.luau         # builds the walk-in market stall + zone
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

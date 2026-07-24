# Mow the Kingdom - Full Progression Design

> The complete, costed progression map from the opening cutscene to the endgame.
> Numbers here are the design targets that the code (GameConfig, services) should be
> tuned to. Everything is balanced around the five grass **zones/rings**, which are
> the spine of the whole game.

## 1. Core Loop

1. **Mow** grass with your **tool** -> earn **clippings** into your carry **bag**.
2. **Bank** clippings at the **Gardener** -> convert to **gold** (and rare **diamonds**).
3. **Spend** gold/diamonds at the **Shop** on tools, swords, auto-mowers, abilities, and upgrades.
4. **Fight** each zone's **monsters** with **swords** -> earn **essence** + diamonds.
5. **Recruit pets**, **rescue villagers**, and **complete quests** for permanent power.
6. **Unlock the next ring**, which has tougher grass, new enemies, and better rewards.
7. Repeat until you conquer the **Ironweed Ring** and forge the ultimate gear.

## 2. Currencies & Resources

| Currency | How you get it | What it buys |
|----------|----------------|--------------|
| **Clippings** | Mowing grass (held in your bag, capped by bag tier) | Converted to gold at the Gardener |
| **Gold** | Banking clippings; quests; auto-mowers | Tools, low/mid swords, most upgrades, Shop restocks |
| **Diamonds** | Rare deposit rolls (5% per 50 clippings), bosses, quests | Auto-mowers, top-tier gear, ability unlocks, premium upgrades |
| **Essence** (per-zone: Meadow Pollen, Wild Burr, Thick Sap, Mire Spore, Iron Filament) | Dropped by that zone's monsters | Forging/upgrading that zone's swords, feeding/recruiting pets |

## 3. The Five Zones (Rings)

Each ring wraps the plains outward from the house. Grass gets tougher, pays more, and
hosts unique enemies and pets. A ring unlocks once you meet BOTH its gold cost and the
required tool tier.

| Zone | Ring | Grass | Grass HP | Clippings/tuft | Gold/clipping | Unlock Cost | Tool Req |
|------|------|-------|----------|----------------|---------------|-------------|----------|
| 1 | Meadow Ring | Meadow | 3 | 1 | x1.0 | Free (start) | Rusty Shears |
| 2 | Wildwood Ring | Wild | 7 | 2 | x1.4 | 2,500 gold | Tier 2 tool |
| 3 | Thicket Ring | Thick | 15 | 4 | x2.0 | 20,000 gold | Tier 3 tool |
| 4 | Mossmire Ring | Moss | 28 | 8 | x3.0 | 120,000 gold | Tier 4 tool |
| 5 | Ironweed Ring | Ironweed | 50 | 16 | x4.5 | 750,000 gold | Tier 5 tool |

## 4. Tools (Mowers) - 10 total

Every specialist tool has a **favored grass** it shreds (x2.5 cut power) and is **weaker
off-type** (x0.8). The two mid "combo" tools favor two grasses at x2.2. The **ultimate**
ignores specialties and cuts everything at a flat, very high power. "Cut power" is damage
per swing; a tuft is cut when damage >= its Grass HP.

| # | Tool | Tier | Favored Grass | Base Cut | On Favored | Off-Type | Swing CD | Cost |
|---|------|------|---------------|----------|------------|----------|----------|------|
| 1 | Rusty Shears | 0 | none (all-rounder) | 2 | 2 | 2 | 0.50s | Free (starter) |
| 2 | Meadow Trimmer | 1 | Meadow | 4 | 10 | 3.2 | 0.50s | 150 gold |
| 3 | Bramble Sickle | 2 | Wild | 8 | 20 | 6.4 | 0.45s | 900 gold |
| 4 | Thornbite Machete | 3 | Thick | 16 | 40 | 12.8 | 0.45s | 4,500 gold |
| 5 | Bogblade | 4 | Moss | 30 | 75 | 24 | 0.40s | 18,000 gold |
| 6 | Ironfang Scythe | 5 | Ironweed | 55 | 137 | 44 | 0.40s | 70,000 gold |
| 7 | Greenwarden Mower | 3 | Meadow + Wild | 24 | 53 (both) | 20 | 0.40s | 12,000 gold |
| 8 | Marsh Reaver | 4 | Thick + Moss | 45 | 99 (both) | 38 | 0.38s | 40,000 gold |
| 9 | Stormcutter | 5 | Ironweed | 80 | 176 | 72 | 0.35s | 25 diamonds |
| 10 | **Verdant Kingcutter** (ULTIMATE) | 6 | **ALL** | 120 | 180 (all) | 180 (all) | 0.30s | 150 diamonds + defeat the Ironweed King |

## 5. Swords - 11 total (2 per zone + 1 ultimate)

Swords are for combat vs. monsters. Each zone has a cheaper **A-blade** and a stronger
**B-blade**; the ultimate **Kingsedge** outclasses all and works everywhere.

| Zone | Sword | Damage | Swing CD | Special | Cost |
|------|-------|--------|----------|---------|------|
| Meadow | Meadow Cutlass | 8 | 0.6s | Wide Slash (small arc AoE) | 300 gold |
| Meadow | Blossom Saber | 15 | 0.55s | Petal Burst (ranged AoE on 5th hit) | 1,200 gold |
| Wild | Bramblefang Blade | 28 | 0.55s | Bleed (DoT 4/s for 3s) | 3,000 gold + 5 Wild Burr |
| Wild | Wildwood Cleaver | 45 | 0.6s | Cleave (hits 3 targets) | 12 Wild Burr + 6 diamonds |
| Thick | Thornguard Sword | 75 | 0.55s | Parry (block next hit, 6s CD) | 25 Thick Sap |
| Thick | Bristlebane | 120 | 0.5s | Thorns (reflect 30% melee) | 40 Thick Sap + 8 diamonds |
| Moss | Bogpiercer | 180 | 0.5s | Poison (DoT 20/s for 4s) | 45 Mire Spore |
| Moss | Mireblade | 280 | 0.5s | Lifesteal (heal 10% of damage) | 70 Mire Spore + 15 diamonds |
| Ironweed | Ironrender | 420 | 0.5s | Armor Break (-40% enemy armor 5s) | 80 Iron Filament |
| Ironweed | Weepthorn Greatblade | 650 | 0.55s | Execute (instant kill < 15% HP) | 120 Iron Filament + 30 diamonds |
| ALL | **Kingsedge** (ULTIMATE) | 1,000 | 0.45s | Whirlwind + true damage (ignores armor) | 200 diamonds + defeat all 5 bosses |

## 6. Auto-Mowers - 5 total (one per zone)

Deploy in its home zone; it passively mows and generates clippings, auto-banking to
gold when it fills (requires the Gardener's "Remote Deposit" perk, unlocked by rescuing
Farmer Fields). Only one runs at a time until the Multi-Mower upgrade.

| Zone | Auto-Mower | Clippings/sec | Storage Cap | Cost | Notes |
|------|-----------|---------------|-------------|------|-------|
| Meadow | Push Mower | 2 | 500 | 20 diamonds | Starter automation |
| Wild | Reel Mower | 5 | 1,500 | 45 diamonds | Handles Wild grass |
| Thick | Brushcutter Bot | 12 | 5,000 | 90 diamonds | Self-rights on slopes |
| Moss | Hover Mower | 28 | 15,000 | 160 diamonds | Floats over bog water |
| Ironweed | Plasma Harvester | 60 | 50,000 | 300 diamonds | Endgame idle engine |

## 7. Special Abilities & Items - 8 total

Cooldown-based actives bound to hotkeys. Bought once, then upgradeable (see Upgrades).

| Ability | Effect | Duration | Cooldown | Unlock |
|---------|--------|----------|----------|--------|
| Grass Bomb | Instantly cuts all grass in a 25-stud radius and banks those clippings | instant | 45s | 15 diamonds |
| Frenzy | +50% cut power and +50% cut range | 15s | 90s | 8 diamonds |
| Magnet Surge | 3x collect range + auto-pull all pickups | 12s | 60s | 6 diamonds |
| Golden Hour | +100% gold from deposits | 30s | 300s | 20 diamonds |
| Whirlwind | Spin hitting every monster within 15 studs for 3x sword damage | instant | 20s | 10 diamonds |
| Dash Boots | Burst of movement speed / short dash | 2s | 8s | 5 diamonds |
| Stasis Field | Freezes all monsters within 20 studs | 6s | 120s | 25 diamonds |
| Harvest Drone | Summons a drone that auto-collects clippings | 30s | 180s | 18 diamonds |

## 8. Upgrades - 28 total (all aspects)

Each upgrade has a max level; cost scales roughly x1.6 per level from the listed start
cost. "Effect/Lv" is the per-level gain.

### Tool & Mowing
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Blade Sharpness | 20 | +8% cut power | 100 | gold |
| Swing Speed | 15 | -3% swing cooldown | 150 | gold |
| Cut Range | 10 | +1 stud cut range | 200 | gold |
| Clipping Yield | 20 | +6% clippings per cut | 250 | gold |

### Economy & Bag
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Bag Capacity (Tiers 1-5) | 5 | 25 -> 60 -> 150 -> 400 -> 1,000 | 150 (tier 2) | gold |
| Deposit Bonus | 15 | +5% gold per clipping | 300 | gold |
| Diamond Luck | 10 | +0.5% diamond roll chance | 5 | diamonds |
| Gold Vault (interest) | 10 | +1% of banked gold/hr (idle) | 500 | gold |

### Movement
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Move Speed | 12 | +4% walk speed | 200 | gold |
| Stamina / Double Jump | 5 | +1 air jump / +sprint time | 400 | gold |
| Climb Grip | 8 | +10% climb speed (for climbable walls) | 15 | diamonds |

### Sword & Combat
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Sword Damage | 20 | +8% sword damage | 250 | gold |
| Attack Speed | 15 | -3% attack cooldown | 300 | gold |
| Crit Chance | 10 | +2% crit chance | 8 | diamonds |
| Crit Damage | 10 | +15% crit damage | 10 | diamonds |
| Vitality (Max HP) | 20 | +10 max HP | 200 | gold |
| Armor (Damage Resist) | 15 | +2% incoming damage reduction | 350 | gold |

### Auto-Mower
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Mower Speed | 15 | +6% clippings/sec | 12 | diamonds |
| Mower Capacity | 10 | +20% storage | 10 | diamonds |
| Mower Efficiency | 8 | +10% runtime before refuel | 15 | diamonds |
| Multi-Mower | 4 | run +1 auto-mower at once | 50 | diamonds |

### Powerups / Abilities
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Ability Cooldown | 10 | -4% all ability cooldowns | 12 | diamonds |
| Bomb Radius | 8 | +3 studs Grass Bomb radius | 10 | diamonds |
| Powerup Duration | 10 | +8% active-ability duration | 12 | diamonds |

### Villagers / Pets
| Upgrade | Max Lv | Effect / Lv | Start Cost | Currency |
|---------|--------|-------------|------------|----------|
| Pet Slots | 3 | +1 equipped pet (max 3) | 40 | diamonds |
| Pet Power | 20 | +5% all pet bonuses | 5 | essence |
| Pet Loyalty (XP) | 10 | +10% pet XP gain | 8 | essence |
| Quest Reward Boost | 10 | +6% all quest rewards | 500 | gold |

## 9. Villagers & Pets (per zone)

**Pets** are equipped (cap 3) and give stacking passive bonuses; level them by feeding
essence. **Villagers** are rescued once (via a quest) for a permanent perk + a service.

| Zone | Pet | Passive (per level) | Recruit Cost |
|------|-----|---------------------|--------------|
| Meadow | Meadow Bunny | +8% clipping yield | 5 Meadow Pollen |
| Meadow | Honeybee | +2 collect range | 8 Meadow Pollen |
| Meadow | Lamb | +4% move speed | 6 diamonds |
| Wild | Fox Kit | +8% gold gain | 10 Wild Burr |
| Wild | Sparrow | +5% swing speed | 12 Wild Burr |
| Wild | Hedgehog | +6% damage resist | 10 diamonds |
| Thick | Badger | +10% cut power | 20 Thick Sap |
| Thick | Owl | +3% diamond luck | 15 diamonds |
| Thick | Boar | +12% max HP | 22 Thick Sap |
| Moss | Marsh Frog | +10% deposit bonus | 35 Mire Spore |
| Moss | Firefly | +6% ability cooldown reduction | 25 diamonds |
| Moss | Newt | +4% lifesteal | 40 Mire Spore |
| Ironweed | Iron Beetle | +10% armor | 60 Iron Filament |
| Ironweed | Phoenix Chick | +15% crit damage | 45 diamonds |
| Ironweed | Dragonling | +6% to ALL stats | 120 Iron Filament + 40 diamonds |

| Zone | Villager | Permanent Perk / Service |
|------|----------|--------------------------|
| Meadow | Farmer Fields | +5% global gold; unlocks Auto-Mower "Remote Deposit" |
| Wild | Ranger Rowan | Highlights rare Golden Grass (2x clippings) in the wild |
| Thick | Woodcutter Wren | +25% essence drops from all monsters |
| Moss | Herbalist Hazel | Unlocks potion crafting (temporary stat buffs) |
| Ironweed | Blacksmith Brand | Unlocks sword forging + reforging (reroll specials) |

## 10. Monsters & Bosses (per zone)

Monsters roam their ring and attack while you mow; kill them with swords. Each zone has
two common monsters and one boss. Stats scale hard by ring.

| Zone | Monster | HP | Damage | Drops |
|------|---------|----|--------|-------|
| Meadow | Weed Sprite | 20 | 4 | Meadow Pollen, gold |
| Meadow | Garden Gnome | 40 | 8 | Meadow Pollen, gold |
| Meadow | **Dandelion Titan** (boss) | 500 | 20 | diamonds, trophy, Meadow Pollen (bulk) |
| Wild | Thistle Goblin | 90 | 12 | Wild Burr, gold |
| Wild | Bramble Crawler | 140 | 18 | Wild Burr, gold |
| Wild | **Bramble Broodmother** (boss) | 1,600 | 45 | diamonds, trophy, Wild Burr (bulk) |
| Thick | Vine Lurker | 320 | 30 | Thick Sap, gold |
| Thick | Bark Golemling | 480 | 42 | Thick Sap, gold |
| Thick | **Elder Vinewrath** (boss) | 5,500 | 90 | diamonds, trophy, Thick Sap (bulk) |
| Moss | Spore Hound | 900 | 60 | Mire Spore, gold |
| Moss | Bog Wraith | 1,300 | 80 | Mire Spore, gold |
| Moss | **Mirequeen** (boss) | 16,000 | 160 | diamonds, trophy, Mire Spore (bulk) |
| Ironweed | Weedwraith | 2,600 | 120 | Iron Filament, gold |
| Ironweed | Ironclad Sentinel | 4,000 | 160 | Iron Filament, gold |
| Ironweed | **The Ironweed King** (final boss) | 60,000 | 300 | diamonds (bulk), Crown, unlocks ultimate gear |

## 11. Quests - 150 total (one Quest Giver NPC, zone-gated)

All quests are handed out by a single NPC, **Sprig the Quartermaster**, who stands near
the house. The quest board only shows quests for your **current/unlocked zone**, so the
experience changes ring to ring. 30 quests per zone. Rewards already scale by zone.

### Zone 1 - Meadow Ring (30 quests)

| # | Quest | Objective | Reward |
|---|-------|-----------|--------|
| 1 | Meadow Ring: Greenhorn | Mow 15 tufts of Meadow grass. | 60 gold |
| 2 | Meadow grass Harvest | Mow 120 Meadow grass tufts in total. | 140 gold |
| 3 | A Full Satchel in the Meadow Ring | Fill your carry bag to capacity while in the Meadow Ring. | 60 gold |
| 4 | Bank On It (Meadow Ring) | Deposit 150 gold at the Gardener. | 1 diamonds |
| 5 | Weed Sprite Stomper | Defeat 5 Weed Sprites. | 60 gold + 6 Meadow Pollen |
| 6 | Garden Gnome Menace | Defeat 5 Garden Gnomes. | 140 gold + 6 Meadow Pollen |
| 7 | Right Blade for the Job (Meadow Ring) | Buy and equip the Meadow Trimmer. | 2 diamonds |
| 8 | Keen Edge in the Meadow Ring | Upgrade Blade Sharpness to Lv 3. | 140 gold |
| 9 | Quick Clip (Meadow Ring) | Mow 15 Meadow grass tufts within 60 seconds. | 2 diamonds |
| 10 | Meadow Pollen Gatherer | Collect 10 Meadow Pollen. | 140 gold |
| 11 | First Blood: Meadow Cutlass | Buy the Meadow Cutlass. | 6 Meadow Pollen |
| 12 | Twin Fangs of the Meadow Ring | Own both Meadow Ring swords (Meadow Cutlass & Blossom Saber). | 4 diamonds |
| 13 | Culling the Meadow Ring | Defeat 25 monsters in the Meadow Ring. | 300 gold + 2 diamonds |
| 14 | Slayer of the Dandelion Titan | Defeat the Dandelion Titan. | 4 diamonds + trophy |
| 15 | Best Friend: Meadow Bunny | Recruit the Meadow Bunny. | 2 diamonds |
| 16 | Loyal Companion: Honeybee | Recruit the Honeybee. | 2 diamonds |
| 17 | Rare Tamer: Lamb | Recruit the Lamb. | 4 diamonds |
| 18 | Rescue: Farmer Fields | Find and rescue Farmer Fields, trapped in the Meadow Ring. | 4 diamonds + permanent perk |
| 19 | Set It & Forget It (Meadow Ring) | Deploy the Push Mower in the Meadow Ring. | 4 diamonds |
| 20 | Overtime Wages (Meadow Ring) | Let the Push Mower auto-bank 150 gold. | 300 gold |
| 21 | Big Spender (Meadow Ring) | Spend 200 gold at the Shop. | 2 diamonds |
| 22 | Boom Season (Meadow Ring) | Use a Grass Bomb 5 times in the Meadow Ring. | 140 gold |
| 23 | Frenzied Cutter (Meadow Ring) | Trigger Frenzy 5 times. | 140 gold |
| 24 | Golden Deposit (Meadow Ring) | Deposit during Golden Hour 3 times. | 2 diamonds |
| 25 | Untouchable (Meadow Ring) | Defeat 5 Weed Sprites without taking damage. | 4 diamonds |
| 26 | Diamond Rush (Meadow Ring) | Earn 5 diamonds while in the Meadow Ring. | 4 diamonds |
| 27 | Upgrade Spree (Meadow Ring) | Purchase 5 upgrades of any kind. | 140 gold |
| 28 | Clean Sweep (Meadow Ring) | Clear 80% of the Meadow Ring's grass in one session. | 4 diamonds |
| 29 | Elite Hunt: Garden Gnome | Defeat 5 Elite Garden Gnomes. | 6 Meadow Pollen + 2 diamonds |
| 30 | Meadow Ring Champion | Defeat the Dandelion Titan 1 times. | 4 diamonds + the Meadow Ring Crown |

### Zone 2 - Wildwood Ring (30 quests)

| # | Quest | Objective | Reward |
|---|-------|-----------|--------|
| 31 | Wildwood Ring: Greenhorn | Mow 40 tufts of Wild grass. | 240 gold |
| 32 | Wild grass Harvest | Mow 350 Wild grass tufts in total. | 560 gold |
| 33 | A Full Satchel in the Wildwood Ring | Fill your carry bag to capacity while in the Wildwood Ring. | 240 gold |
| 34 | Bank On It (Wildwood Ring) | Deposit 600 gold at the Gardener. | 2 diamonds |
| 35 | Thistle Goblin Stomper | Defeat 10 Thistle Goblins. | 240 gold + 14 Wild Burr |
| 36 | Bramble Crawler Menace | Defeat 10 Bramble Crawlers. | 560 gold + 14 Wild Burr |
| 37 | Right Blade for the Job (Wildwood Ring) | Buy and equip the Bramble Sickle. | 5 diamonds |
| 38 | Keen Edge in the Wildwood Ring | Upgrade Blade Sharpness to Lv 5. | 560 gold |
| 39 | Quick Clip (Wildwood Ring) | Mow 40 Wild grass tufts within 60 seconds. | 5 diamonds |
| 40 | Wild Burr Gatherer | Collect 25 Wild Burr. | 560 gold |
| 41 | First Blood: Bramblefang Blade | Buy the Bramblefang Blade. | 14 Wild Burr |
| 42 | Twin Fangs of the Wildwood Ring | Own both Wildwood Ring swords (Bramblefang Blade & Wildwood Cleaver). | 9 diamonds |
| 43 | Culling the Wildwood Ring | Defeat 55 monsters in the Wildwood Ring. | 1,200 gold + 5 diamonds |
| 44 | Slayer of the Bramble Broodmother | Defeat the Bramble Broodmother. | 9 diamonds + trophy |
| 45 | Best Friend: Fox Kit | Recruit the Fox Kit. | 5 diamonds |
| 46 | Loyal Companion: Sparrow | Recruit the Sparrow. | 5 diamonds |
| 47 | Rare Tamer: Hedgehog | Recruit the Hedgehog. | 9 diamonds |
| 48 | Rescue: Ranger Rowan | Find and rescue Ranger Rowan, trapped in the Wildwood Ring. | 9 diamonds + permanent perk |
| 49 | Set It & Forget It (Wildwood Ring) | Deploy the Reel Mower in the Wildwood Ring. | 9 diamonds |
| 50 | Overtime Wages (Wildwood Ring) | Let the Reel Mower auto-bank 600 gold. | 1,200 gold |
| 51 | Big Spender (Wildwood Ring) | Spend 900 gold at the Shop. | 5 diamonds |
| 52 | Boom Season (Wildwood Ring) | Use a Grass Bomb 10 times in the Wildwood Ring. | 560 gold |
| 53 | Frenzied Cutter (Wildwood Ring) | Trigger Frenzy 10 times. | 560 gold |
| 54 | Golden Deposit (Wildwood Ring) | Deposit during Golden Hour 5 times. | 5 diamonds |
| 55 | Untouchable (Wildwood Ring) | Defeat 10 Thistle Goblins without taking damage. | 9 diamonds |
| 56 | Diamond Rush (Wildwood Ring) | Earn 15 diamonds while in the Wildwood Ring. | 9 diamonds |
| 57 | Upgrade Spree (Wildwood Ring) | Purchase 10 upgrades of any kind. | 560 gold |
| 58 | Clean Sweep (Wildwood Ring) | Clear 80% of the Wildwood Ring's grass in one session. | 9 diamonds |
| 59 | Elite Hunt: Bramble Crawler | Defeat 10 Elite Bramble Crawlers. | 14 Wild Burr + 5 diamonds |
| 60 | Wildwood Ring Champion | Defeat the Bramble Broodmother 2 times. | 9 diamonds + the Wildwood Ring Crown |

### Zone 3 - Thicket Ring (30 quests)

| # | Quest | Objective | Reward |
|---|-------|-----------|--------|
| 61 | Thicket Ring: Greenhorn | Mow 80 tufts of Thick grass. | 850 gold |
| 62 | Thick grass Harvest | Mow 800 Thick grass tufts in total. | 2,000 gold |
| 63 | A Full Satchel in the Thicket Ring | Fill your carry bag to capacity while in the Thicket Ring. | 850 gold |
| 64 | Bank On It (Thicket Ring) | Deposit 2,000 gold at the Gardener. | 4 diamonds |
| 65 | Vine Lurker Stomper | Defeat 18 Vine Lurkers. | 850 gold + 28 Thick Sap |
| 66 | Bark Golemling Menace | Defeat 18 Bark Golemlings. | 2,000 gold + 28 Thick Sap |
| 67 | Right Blade for the Job (Thicket Ring) | Buy and equip the Thornbite Machete. | 10 diamonds |
| 68 | Keen Edge in the Thicket Ring | Upgrade Blade Sharpness to Lv 8. | 2,000 gold |
| 69 | Quick Clip (Thicket Ring) | Mow 80 Thick grass tufts within 60 seconds. | 10 diamonds |
| 70 | Thick Sap Gatherer | Collect 50 Thick Sap. | 2,000 gold |
| 71 | First Blood: Thornguard Sword | Buy the Thornguard Sword. | 28 Thick Sap |
| 72 | Twin Fangs of the Thicket Ring | Own both Thicket Ring swords (Thornguard Sword & Bristlebane). | 18 diamonds |
| 73 | Culling the Thicket Ring | Defeat 90 monsters in the Thicket Ring. | 4,500 gold + 10 diamonds |
| 74 | Slayer of the Elder Vinewrath | Defeat the Elder Vinewrath. | 18 diamonds + trophy |
| 75 | Best Friend: Badger | Recruit the Badger. | 10 diamonds |
| 76 | Loyal Companion: Owl | Recruit the Owl. | 10 diamonds |
| 77 | Rare Tamer: Boar | Recruit the Boar. | 18 diamonds |
| 78 | Rescue: Woodcutter Wren | Find and rescue Woodcutter Wren, trapped in the Thicket Ring. | 18 diamonds + permanent perk |
| 79 | Set It & Forget It (Thicket Ring) | Deploy the Brushcutter Bot in the Thicket Ring. | 18 diamonds |
| 80 | Overtime Wages (Thicket Ring) | Let the Brushcutter Bot auto-bank 2,000 gold. | 4,500 gold |
| 81 | Big Spender (Thicket Ring) | Spend 4,000 gold at the Shop. | 10 diamonds |
| 82 | Boom Season (Thicket Ring) | Use a Grass Bomb 18 times in the Thicket Ring. | 2,000 gold |
| 83 | Frenzied Cutter (Thicket Ring) | Trigger Frenzy 18 times. | 2,000 gold |
| 84 | Golden Deposit (Thicket Ring) | Deposit during Golden Hour 8 times. | 10 diamonds |
| 85 | Untouchable (Thicket Ring) | Defeat 18 Vine Lurkers without taking damage. | 18 diamonds |
| 86 | Diamond Rush (Thicket Ring) | Earn 40 diamonds while in the Thicket Ring. | 18 diamonds |
| 87 | Upgrade Spree (Thicket Ring) | Purchase 18 upgrades of any kind. | 2,000 gold |
| 88 | Clean Sweep (Thicket Ring) | Clear 80% of the Thicket Ring's grass in one session. | 18 diamonds |
| 89 | Elite Hunt: Bark Golemling | Defeat 18 Elite Bark Golemlings. | 28 Thick Sap + 10 diamonds |
| 90 | Thicket Ring Champion | Defeat the Elder Vinewrath 3 times. | 18 diamonds + the Thicket Ring Crown |

### Zone 4 - Mossmire Ring (30 quests)

| # | Quest | Objective | Reward |
|---|-------|-----------|--------|
| 91 | Mossmire Ring: Greenhorn | Mow 150 tufts of Moss grass. | 3,000 gold |
| 92 | Moss grass Harvest | Mow 1800 Moss grass tufts in total. | 7,000 gold |
| 93 | A Full Satchel in the Mossmire Ring | Fill your carry bag to capacity while in the Mossmire Ring. | 3,000 gold |
| 94 | Bank On It (Mossmire Ring) | Deposit 6,500 gold at the Gardener. | 8 diamonds |
| 95 | Spore Hound Stomper | Defeat 30 Spore Hounds. | 3,000 gold + 50 Mire Spore |
| 96 | Bog Wraith Menace | Defeat 30 Bog Wraiths. | 7,000 gold + 50 Mire Spore |
| 97 | Right Blade for the Job (Mossmire Ring) | Buy and equip the Bogblade. | 22 diamonds |
| 98 | Keen Edge in the Mossmire Ring | Upgrade Blade Sharpness to Lv 12. | 7,000 gold |
| 99 | Quick Clip (Mossmire Ring) | Mow 150 Moss grass tufts within 60 seconds. | 22 diamonds |
| 100 | Mire Spore Gatherer | Collect 90 Mire Spore. | 7,000 gold |
| 101 | First Blood: Bogpiercer | Buy the Bogpiercer. | 50 Mire Spore |
| 102 | Twin Fangs of the Mossmire Ring | Own both Mossmire Ring swords (Bogpiercer & Mireblade). | 38 diamonds |
| 103 | Culling the Mossmire Ring | Defeat 150 monsters in the Mossmire Ring. | 16,000 gold + 22 diamonds |
| 104 | Slayer of the Mirequeen | Defeat the Mirequeen. | 38 diamonds + trophy |
| 105 | Best Friend: Marsh Frog | Recruit the Marsh Frog. | 22 diamonds |
| 106 | Loyal Companion: Firefly | Recruit the Firefly. | 22 diamonds |
| 107 | Rare Tamer: Newt | Recruit the Newt. | 38 diamonds |
| 108 | Rescue: Herbalist Hazel | Find and rescue Herbalist Hazel, trapped in the Mossmire Ring. | 38 diamonds + permanent perk |
| 109 | Set It & Forget It (Mossmire Ring) | Deploy the Hover Mower in the Mossmire Ring. | 38 diamonds |
| 110 | Overtime Wages (Mossmire Ring) | Let the Hover Mower auto-bank 6,500 gold. | 16,000 gold |
| 111 | Big Spender (Mossmire Ring) | Spend 15,000 gold at the Shop. | 22 diamonds |
| 112 | Boom Season (Mossmire Ring) | Use a Grass Bomb 30 times in the Mossmire Ring. | 7,000 gold |
| 113 | Frenzied Cutter (Mossmire Ring) | Trigger Frenzy 30 times. | 7,000 gold |
| 114 | Golden Deposit (Mossmire Ring) | Deposit during Golden Hour 10 times. | 22 diamonds |
| 115 | Untouchable (Mossmire Ring) | Defeat 30 Spore Hounds without taking damage. | 38 diamonds |
| 116 | Diamond Rush (Mossmire Ring) | Earn 90 diamonds while in the Mossmire Ring. | 38 diamonds |
| 117 | Upgrade Spree (Mossmire Ring) | Purchase 30 upgrades of any kind. | 7,000 gold |
| 118 | Clean Sweep (Mossmire Ring) | Clear 80% of the Mossmire Ring's grass in one session. | 38 diamonds |
| 119 | Elite Hunt: Bog Wraith | Defeat 30 Elite Bog Wraiths. | 50 Mire Spore + 22 diamonds |
| 120 | Mossmire Ring Champion | Defeat the Mirequeen 3 times. | 38 diamonds + the Mossmire Ring Crown |

### Zone 5 - Ironweed Ring (30 quests)

| # | Quest | Objective | Reward |
|---|-------|-----------|--------|
| 121 | Ironweed Ring: Greenhorn | Mow 250 tufts of Ironweed grass. | 9,500 gold |
| 122 | Ironweed grass Harvest | Mow 3500 Ironweed grass tufts in total. | 22,000 gold |
| 123 | A Full Satchel in the Ironweed Ring | Fill your carry bag to capacity while in the Ironweed Ring. | 9,500 gold |
| 124 | Bank On It (Ironweed Ring) | Deposit 20,000 gold at the Gardener. | 16 diamonds |
| 125 | Weedwraith Stomper | Defeat 50 Weedwraiths. | 9,500 gold + 90 Iron Filament |
| 126 | Ironclad Sentinel Menace | Defeat 50 Ironclad Sentinels. | 22,000 gold + 90 Iron Filament |
| 127 | Right Blade for the Job (Ironweed Ring) | Buy and equip the Ironfang Scythe. | 45 diamonds |
| 128 | Keen Edge in the Ironweed Ring | Upgrade Blade Sharpness to Lv 18. | 22,000 gold |
| 129 | Quick Clip (Ironweed Ring) | Mow 250 Ironweed grass tufts within 60 seconds. | 45 diamonds |
| 130 | Iron Filament Gatherer | Collect 160 Iron Filament. | 22,000 gold |
| 131 | First Blood: Ironrender | Buy the Ironrender. | 90 Iron Filament |
| 132 | Twin Fangs of the Ironweed Ring | Own both Ironweed Ring swords (Ironrender & Weepthorn Greatblade). | 75 diamonds |
| 133 | Culling the Ironweed Ring | Defeat 250 monsters in the Ironweed Ring. | 50,000 gold + 45 diamonds |
| 134 | Slayer of the The Ironweed King | Defeat the The Ironweed King. | 75 diamonds + trophy |
| 135 | Best Friend: Iron Beetle | Recruit the Iron Beetle. | 45 diamonds |
| 136 | Loyal Companion: Phoenix Chick | Recruit the Phoenix Chick. | 45 diamonds |
| 137 | Rare Tamer: Dragonling | Recruit the Dragonling. | 75 diamonds |
| 138 | Rescue: Blacksmith Brand | Find and rescue Blacksmith Brand, trapped in the Ironweed Ring. | 75 diamonds + permanent perk |
| 139 | Set It & Forget It (Ironweed Ring) | Deploy the Plasma Harvester in the Ironweed Ring. | 75 diamonds |
| 140 | Overtime Wages (Ironweed Ring) | Let the Plasma Harvester auto-bank 20,000 gold. | 50,000 gold |
| 141 | Big Spender (Ironweed Ring) | Spend 55,000 gold at the Shop. | 45 diamonds |
| 142 | Boom Season (Ironweed Ring) | Use a Grass Bomb 50 times in the Ironweed Ring. | 22,000 gold |
| 143 | Frenzied Cutter (Ironweed Ring) | Trigger Frenzy 50 times. | 22,000 gold |
| 144 | Golden Deposit (Ironweed Ring) | Deposit during Golden Hour 12 times. | 45 diamonds |
| 145 | Untouchable (Ironweed Ring) | Defeat 50 Weedwraiths without taking damage. | 75 diamonds |
| 146 | Diamond Rush (Ironweed Ring) | Earn 180 diamonds while in the Ironweed Ring. | 75 diamonds |
| 147 | Upgrade Spree (Ironweed Ring) | Purchase 50 upgrades of any kind. | 22,000 gold |
| 148 | Clean Sweep (Ironweed Ring) | Clear 80% of the Ironweed Ring's grass in one session. | 75 diamonds |
| 149 | Elite Hunt: Ironclad Sentinel | Defeat 50 Elite Ironclad Sentinels. | 90 Iron Filament + 45 diamonds |
| 150 | Ironweed Ring Champion | Defeat the The Ironweed King 5 times. | 75 diamonds + the Ironweed Ring Crown |

## 12. Pacing & Progression Timeline

| Phase | Approx. session time | Player is doing... | Key unlocks |
|-------|----------------------|--------------------|-------------|
| Opening | 0-10 min | Cutscene, first mows with Rusty Shears, first deposit | Meadow Trimmer, Bag Tier 2, first pet |
| Meadow mastery | 10-60 min | Clearing Meadow, first swords, Dandelion Titan | Push Mower, Wildwood unlock (2,500g) |
| Wildwood | 1-3 hrs | Wild grass + combat ramps, essence economy begins | Bramble Sickle, Reel Mower, rescue Ranger Rowan |
| Thicket | 3-8 hrs | Combo tools, harder bosses, upgrade sinks | Greenwarden Mower, Brushcutter Bot, abilities |
| Mossmire | 8-20 hrs | Deep combat, potion crafting, idle income matters | Marsh Reaver, Hover Mower, most upgrades maxing |
| Ironweed | 20-40+ hrs | Endgame grind, boss rushes, forging | Stormcutter, Plasma Harvester, ultimate gear |
| Endgame | 40+ hrs | Verdant Kingcutter + Kingsedge, 100% pets, all 150 quests | Prestige (future) |

## 13. Economy Tuning Notes (for GameConfig)

- **Clipping -> gold** base is 1:1, multiplied by the zone's Gold/clipping (x1.0 -> x4.5).
- **Diamond roll**: 5% chance per 50 clippings deposited (existing DIAMOND_CHANCE / DIAMOND_ROLL_PER_CLIPPINGS), before Diamond Luck upgrades.
- Each zone's grass HP (3/7/15/28/50) is what tool cut power is balanced against - a favored specialist one-shots its grass; an off-type tool needs 2-3 swings.
- Sword damage vs. monster HP is tuned so the matching-zone A-blade kills a common monster in ~3-5 hits and the B-blade in ~2-3; bosses are multi-minute fights.
- Costs climb ~x4-6 per zone so each ring is a meaningful gate; diamonds gate the "convenience + ultimate" layer (auto-mowers, abilities, top gear).
- Suggested new GameConfig blocks: ZONES, TOOL_TIERS (expand to 10), SWORDS, AUTO_MOWERS, ABILITIES, UPGRADES, PETS, VILLAGERS, MONSTERS, QUESTS.

---
*Generated design doc. All names, numbers, and costs are the initial design targets and are meant to be tuned during playtesting.*

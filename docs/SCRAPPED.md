# Mow the Kingdom - Scrapped Content

> Everything that has been cut from the game, with the reason why. This file exists so
> that scrapped ideas stay **recoverable** but stop being re-proposed as if they were
> still on the roadmap. If an idea is in this file, it is **not** part of the current
> game unless it is explicitly moved back out.
>
> Ruling date: 2026-07-26.

---

## 1. Why the setting changed

The game began as **"The Kingdom of Verdania"** - a medieval-fantasy premise where a
peasant reclaims an abandoned kingdom buried under overgrowth, restoring villages and
finally claiming the crown.

That framing was replaced by the current premise: **a kid's teddy bear falls out their
bedroom window, and the suburban neighborhood outside has been overtaken by an endless
plains biome.** The game is now **modern**, with **sparse sci-fi and medieval touches
scattered through the gear** rather than a medieval world.

Everything below was cut because it belonged to the old framing, was superseded by a
better version, or was built and then removed in playtesting.

---

## 2. Setting & fiction

| Cut | Reason |
|-----|--------|
| **"The Kingdom of Verdania"** as the setting name | Medieval framing retired. The working setting name is now **Robloxia Neighborhood**. |
| **Medieval-fantasy premise** (peasant, royal land, claim the crown) | Replaced by the modern teddy-bear / overgrown-neighborhood premise. |
| **`workspace.Kingdom`** as the world root instance name | Theme leftover; renamed for clarity. |
| **"Kingdom Skills"** as the upgrade-system name | Renamed to plain **Upgrades**. |
| **Prestige named "New Kingdom"** | Prestige itself is still on the roadmap; only the name is cut. Needs a new, non-medieval name. |
| **Title "Mow the Kingdom"** | **Kept for now** - flagged for a future rename, but it stays until a replacement is chosen. |

> Note: the title is deliberately *not* fully scrapped. It is the one surviving
> "kingdom" reference and is pending a rename decision.

---

## 3. World & maps

| Cut | Reason |
|-----|--------|
| **8 zones** | Reduced to exactly **5 zones**, which are now the balancing spine of the entire game. |
| **Village 1 "Greenhollow"** (procedurally built village) | Built, screenshotted, iterated on, then scrapped entirely along with the medieval framing. |
| **Oval "Medieval Dynasty"-style village layout**, cows in the commons, NW bonfire | Part of the same scrapped village. |
| **4 districts + `DistrictService`** | Districts existed to subdivide the scrapped village. See the carve-out below. |
| **Village market stalls / commerce buildings** | Superseded by the single Shop stall. |
| **Grass barriers between rings** | Added, then removed - they read as walls and broke the feeling of open plains. |
| **Zone "restoration cutscenes"** (buildings repairing themselves as a zone completes) | Tied to the village/kingdom-restoration fantasy. |

### Carve-out: "mow to reveal" survives

The **districts** system is cut, but the **"mow to reveal"** idea it carried is **kept**:
mowing still uncovers the scenery models scattered across the map. Revealing is now a
property of clearing grass, not of a district unlocking.

---

## 4. Traversal

| Cut | Reason |
|-----|--------|
| **Tool-based climbing** on `Climbable`-tagged walls | Cut from scope. |
| **Roof grass** (mowing rooftops) | Existed only to give climbing a purpose. |
| **`Climb Grip` upgrade** | Orphaned by the above. |

---

## 5. Tools & gear

| Cut | Reason |
|-----|--------|
| **15 tool tiers** | Reduced to exactly **11 tools**. |
| **Favored-grass multiplier of x2.5** | Retained as a mechanic but **retuned to x2.0**. |
| **"Verdant Kingcutter"** (ultimate tool name) | Medieval name; mechanic kept, **rename required**. |
| **"Kingsedge"** (ultimate sword name) | Medieval name; mechanic kept, **rename required**. |
| **Horse-drawn / steam / riding mower tiers, mounts, carts** | Belonged to the medieval tool ladder. |

---

## 6. Bag / backpack

| Cut | Reason |
|-----|--------|
| **`BAG_TIERS` linear bag ladder** + the `PurchaseUpgrade("bag")` path | Fully superseded by the 5 zone backpacks. Was dead-but-live code. |
| **Hard-stop bag** (clippings above capacity are discarded) | Replaced by **slight overflow**: a cut that would exceed capacity is granted in full rather than truncated, so no clippings are ever destroyed by bag arithmetic. Mowing is only blocked *after* the bag is at or over capacity. |

---

## 7. The 12 "Kingdom Skills"

The original 12-skill micro-upgrade list is **retired as a framing**. The canonical
upgrade system is now the **28-upgrade list** in `PROGRESSION.md` section 8.

Retired list: Sharp Blades, Quick Hands, Wide Arc, Swift Boots, Clipping Magnet,
Greener Thumb, Lucky Snips, Golden Touch, **Goat Whisperer**, Deep Pockets,
**Treasure Sense**, Endurance.

**Important carve-out:** several of these are *already implemented and working in code*
(notably **Sharp Blades** and **Clipping Magnet**). Those mechanics are **kept** and
re-homed into the 28-upgrade list under their new names (e.g. Blade Sharpness, collect
range). Only the "Kingdom Skills" grouping, its naming, and the skills that had no
system behind them are cut.

Fully cut with no replacement:

| Cut skill | Reason |
|-----------|--------|
| **Goat Whisperer** | Assumed grazing livestock as the auto-mower fantasy; auto-mowers are now machines. |
| **Treasure Sense** | Depended on a buried-treasure/rare-find system that was never built. |

---

## 8. Economy

| Cut | Reason |
|-----|--------|
| **Gold costs to unlock zones** (2,500 / 20,000 / 120,000 / 750,000) | Zones are gated by **gear capability only** - your tool must be able to damage that grass. No purchase step. |
| **Offline earnings + offline earnings cap** | Auto-mowers earn only while online. |

---

## 9. Monster spawn model (revised, not cut)

The old figure of **"~25 of each monster per zone"** is cut as a flat global number -
25 monsters in a 1,000-tile field is not threatening.

Replaced by: **per-zone spawn counts that scale with zone size**, and/or a
**chance-based trigger** (for example a ~5% chance to spawn a monster each time a grass
tile is fully cleared). Final model TBD; see `PROGRESSION.md`.

---

## 10. Pets & neighbors (restructured, not cut)

**"Villagers ARE the pet system"** is cut. They are now **two separate systems**, and
"villagers" are renamed **neighbors** to fit the suburban setting:

- **5 neighbors** - rescued once each, one guaranteed per zone, grant buffs.
- **15 pets** - 3 per zone, grant buffs, awarded **by chance per grass tile cleared**,
  with each zone guaranteed to hand out exactly one copy of each of its three pets.

---

## 11. Superseded technical plans

| Cut | Reason |
|-----|--------|
| **Milestones M0-M7** as written | Reached or overtaken by actual development; replaced with a live roadmap. |
| **`ZoneService`, `MonetizationService`, `PetService`, `CameraController`** as planned modules | Never built under those names; responsibilities landed in other modules. |
| **Profile schema v1** | Now at **v5**. |
| **`ratePerSec` idle income for auto-mowers** | Mowers now earn from grass they physically cut. The field survives only as a shop blurb number and is decorative. |
| **Single shared auto-mower deploy anchor** | Replaced by **4 anchors per zone**; a mower that finds no grass near its current anchor travels to the next one. |
| **Zone naming split (`Moss`/`Thick` vs Thicket/Mossmire)** | Resolved: **ring 3 = Mossmire**, **ring 4 = Thicket**. Keys renamed in code. |

---

## 12. Kept, despite sounding legacy

Listed here to stop them being re-scrapped by mistake:

- **Grass state not persisting across sessions** - a known limitation, **still on the
  roadmap**, just not now.
- **Prestige loop** and its **Desert / Frost / Shadow** biome variants - still planned;
  only the "New Kingdom" name is cut.
- **"~2,000,000 blades of grass"** as a scope figure.
- **Private, persistent per-player world.**
- **"Golden Blade" 10x critical cuts.**
- **Solo saves / co-op does not save.**

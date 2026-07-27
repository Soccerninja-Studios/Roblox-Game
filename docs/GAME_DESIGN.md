# Mow the Kingdom - Game Design Blueprint

> **Status:** current as of 2026-07-26. This document was rewritten from scratch when the
> setting changed. Everything cut from the original medieval "Kingdom of Verdania"
> version is recorded in `docs/SCRAPPED.md`.
>
> **Working title:** *Mow the Kingdom*. This is a **placeholder** - the word "Kingdom" is
> a leftover from the original premise and a rename is expected. It stays until a
> replacement is chosen.

---

## 1. Concept

**The hook:** A kid is sitting at their desk when their **teddy bear falls out the bedroom
window**. They go outside to get it - and the ordinary suburban neighborhood they live in
has been swallowed by an **endless plains biome**. The grass is waist-high and getting
taller. The teddy bear is out there somewhere.

You mow to take the neighborhood back.

**Setting:** the **Robloxia Neighborhood** - a normal modern suburb, overrun. The house you
start at is your house.

**Genre:** incremental / grind-to-goal simulator with deep upgrade-driven progression.

**Why it works:**

- The goal is instantly readable and the progress *is* the map - every cleared tile stays
  cleared, and mowing reveals the scenery buried in the overgrowth.
- A cold open that costs the player nothing: a 30-second cutscene, then they're holding
  shears in a transformed world.
- Constant acceleration through upgrades, with something affordable to buy at all times.
- Real risk in the outer rings: monsters can take clippings you haven't banked.

**Map model:** every player gets their **own private, persistent world**. Playing solo
saves your progress; co-op sessions are fresh and do **not** save.

---

## 2. Tone & Aesthetic

The game is **modern**, not medieval. Bright, chunky, low-poly, readable at a glance.

- **Base layer - modern suburban.** Houses, fences, driveways, mailboxes, garden tools.
- **Sprinkle of sci-fi.** Mostly in the late-game automation: the Brushcutter Bot, Hover
  Mower, and Plasma Harvester are unapologetically futuristic.
- **Sprinkle of medieval/fantasy.** Mostly in the bladed gear and the monsters: scythes,
  machetes, and enemies like the Bramble Broodmother.

The rule: **the world is modern; the gear is where the weird stuff lives.** Sci-fi and
medieval elements are *scattered accents*, never the setting itself.

**Juice:** grass pops with particles and sound on every cut, floating "+N clippings"
popups, coins that rattle up the counter, screen shake on big clears.

---

## 3. Core Loop (30-second cycle)

1. **Mow** grass with an equipped tool (hold left-click). A tool is required.
2. **Collect clippings.** They drop physically and are vacuumed up as you walk near them.
   Clippings are only awarded when a tile is **fully cleared**.
3. **Fill your backpack.** Clippings are carried, not banked, and capacity is limited.
4. **Bank at the Gardener** to convert clippings into **gold**, with a chance at
   **diamonds**.
5. **Spend at the Shop** on tools, backpacks, upgrades, auto-mowers, and swords.
6. **Push outward** into tougher grass that pays more.

Later in progression, combat layers on top: monsters roam the outer rings and steal
**unbanked** clippings, so carrying a full bag far from home is a real gamble.

---

## 4. The Five Zones

Exactly **five** concentric rings radiate outward from the house across a 5x5 grid of
512-stud baseplates. Grass gets tougher, pays more, and hosts its own enemies and pets.

| Ring | Zone | Grass key | Grass HP | Clippings per tile |
|------|------|-----------|----------|--------------------|
| 1 | **Meadow** | `Meadow` | 3 | 3 |
| 2 | **Wildfields** | `Wild` | 6 | 6 |
| 3 | **Mossmire** | `Mossmire` | 12 | 15 |
| 4 | **Thicket** | `Thicket` | 16 | 25 |
| 5 | **Ironweed Expanse** | `Ironweed` | 40 | 80 |

**Zones are gated by capability, not by purchase.** Grass has armor that subtracts from
every swing, so a tool that is too weak simply cannot damage it. There is no gold cost to
"unlock" a ring - you unlock it by being able to cut it.

> Ring 3 is **Mossmire** and ring 4 is **Thicket**. This ordering is canonical and matches
> the code keys exactly.

---

## 5. Progression Systems

Full costed detail lives in `docs/PROGRESSION.md`. Summary:

- **Tools - 11 total.** Each specialist tool has a **favored grass type (x2.0 cut power)**
  and is weaker off-type (x0.7). Players **own tools and equip at will** rather than
  replacing them, so tools are situational rather than a strict ladder.
- **Backpacks - 5 total,** one per zone, each upgradeable within itself. Capacity allows
  **slight overflow**: a cut that would exceed your cap is granted in full rather than
  truncated, so clippings are never destroyed by bag arithmetic. Mowing is blocked only
  once you are already at capacity.
- **Upgrades - 28 total** across Tool/Mowing, Economy/Bag, Movement, Sword/Combat,
  Auto-Mower, Abilities, and Pets/Neighbors.
- **Auto-mowers - 5 total,** one per zone. These are real autonomous agents that seek,
  cut, haul, and deposit - not idle number generators.
- **Swords - 11 total,** two per zone plus one ultimate.
- **Abilities - 8 total,** cooldown-based actives on hotkeys.
- **Pets - 15 total** (3 per zone) and **Neighbors - 5 total** (1 per zone). These are two
  **separate** systems; both grant buffs.
- **Quests - 150 total,** 30 per zone, from a single quest-giver NPC.
- **Monsters and bosses** per zone, culminating in **The Ironweed King**.

### Currencies

| Currency | Role |
|----------|------|
| **Clippings** | Carried, capped by backpack. Vulnerable until banked. |
| **Gold** | Main persistent currency. |
| **Diamonds** | Premium. ~5% roll per 50 clippings banked. Gates high-end gear. |
| **Essence** | Per-zone combat currency for pets and sword forging. |

---

## 6. Risk & Failure Design

The outer rings need teeth, but losing progress must never feel punitive:

- Monsters steal **unbanked** clippings only. Banked gold is always safe.
- On death, your carried clippings drop as a **recoverable pile** with an on-screen
  prompt pointing you back to it. Loss must never *read* as permanent.
- Because backpack capacity grows fast in later zones, the amount at stake scales
  naturally with how far out you are.

---

## 7. Retention

- Private, persistent world - progress is entirely personal.
- 150 zone-gated quests, so the objective list changes ring to ring.
- Pets awarded by chance per tile cleared, giving every cut a lottery ticket.
- Neighbors to rescue, each granting a permanent buff.
- Auto-mowers as an idle layer that rewards returning.
- Prestige at the very end (see `docs/PROGRESSION.md`); the old "New Kingdom" name is
  retired and a replacement is needed.

### Pacing target

| Stage | Target |
|-------|--------|
| Opening hook | 0-10 minutes |
| Main progression | 15-25 hours |
| Endgame | 40+ hours |

---

## 8. Monetization

**Golden rule:** everything that grants power is also earnable for free, just slower.
Robux is the skip lane. Cosmetics may be Robux-exclusive.

Planned: gamepasses (2x clippings, auto-collect, extra mower slots), dev products (timed
boosts, clipping packs, Grass Bombs), a cosmetics shop, and one-time starter bundles.
Not yet implemented.

---

## 9. Current State

**Built and working:** grass system, plains map and scatter, clipping drops and magnet
pickup, DataStore persistence with session locking, Shop / Gardener / quest-giver hub,
11-tool zone-gated ladder, intro cutscene, 150 quests, 5 autonomous auto-mowers, tabbed
Shop UI, 5 zone backpacks, dash, admin panel.

**Not yet built:** combat and monsters, swords, pets, neighbors, abilities, prestige,
hub/co-op teleport layer, monetization.

**Known limitation:** grass state does not persist across sessions yet. This is on the
roadmap.

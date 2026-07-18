--!strict
-- GameConfig: every tunable number in the game lives here.
-- Never hardcode balance values inside game logic; reference this module instead.

local GameConfig = {
	-- Economy
	CLIPPINGS_PER_BLADE = 1,
	CRIT_BASE_CHANCE = 0.01, -- 1% base "Golden Blade" chance
	CRIT_BASE_MULTIPLIER = 10,

	-- Grass tiles
	-- Grass now starts TALL and shrinks vertically each cut until it disappears.
	-- BLADES_PER_TILE is tuned low so a few swings with the starter tool clear a tile.
	BLADES_PER_TILE = 5,
	TILE_SIZE_STUDS = 4,
	TALL_GRASS_HEIGHT = 7, -- how tall a fresh, uncut tile stands (studs)
	GRASS_HEIGHT_VARIATION = 1.2, -- random extra height for a natural, uneven look
	GRASS_MIN_STUB = 0.05, -- tile height at the instant before it is removed
	GRASS_SHRINK_TWEEN = 0.12, -- seconds for the shrink animation per cut

	-- Tool tiers: bladesPerSwing = how many blades one swing cuts (a.k.a. clipping power),
	-- cost in Clippings, plus how the held shears tool should look at that tier.
	TOOL_TIERS = {
		{
			name = "Rusty Shears",
			bladesPerSwing = 1,
			cost = 0,
			handleColor = { 92, 64, 40 },
			bladeColor = { 138, 120, 96 }, -- rusty metal
			bladeMaterial = "CorrodedMetal",
			toolScale = 1.0,
		},
		{
			name = "Sickle",
			bladesPerSwing = 3,
			cost = 100,
			handleColor = { 110, 76, 46 },
			bladeColor = { 190, 190, 200 }, -- clean steel
			bladeMaterial = "Metal",
			toolScale = 1.15,
		},
		{
			name = "Scythe",
			bladesPerSwing = 8,
			cost = 750,
			handleColor = { 70, 50, 34 },
			bladeColor = { 214, 216, 226 }, -- polished steel
			bladeMaterial = "Metal",
			toolScale = 1.35,
		},
		-- Tiers 4-15 added in a later balancing pass
	},

	-- Kingdom Skills: small leveled upgrades
	SKILLS = {
		SharpBlades = { maxLevel = 100, effectPerLevel = 0.02, baseCost = 25, costGrowth = 1.08 },
		QuickHands = { maxLevel = 50, effectPerLevel = 0.01, baseCost = 40, costGrowth = 1.10 },
		-- Remaining skills added in a later milestone
	},

	-- Swing
	BASE_SWING_COOLDOWN = 0.5, -- seconds between swings before QuickHands
	CUT_RANGE = 16, -- max studs between player and a tile to cut it

	-- Test meadow (M1): grid of tiles next to spawn
	MEADOW_GRID = 40, -- 40x40 tiles
	MEADOW_ORIGIN = Vector3.new(16, 0, 16), -- corner the meadow grows from

	-- Shop (walk-in zone + always-on button both open the same menu)
	SHOP_POSITION = Vector3.new(-10, 0, -16), -- center of the shop stall / zone
	SHOP_ZONE_RADIUS = 15, -- how close (studs, horizontal) opens the menu automatically
}

return GameConfig

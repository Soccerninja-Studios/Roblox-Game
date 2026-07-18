--!strict
-- GameConfig: every tunable number in the game lives here.
-- Never hardcode balance values inside game logic; reference this module instead.

local GameConfig = {
	-- Economy
	CLIPPINGS_PER_BLADE = 1,
	CRIT_BASE_CHANCE = 0.01, -- 1% base "Golden Blade" chance
	CRIT_BASE_MULTIPLIER = 10,

	-- Grass tiles (shared)
	TILE_SIZE_STUDS = 4, -- footprint of one grass tile
	TILE_FILL = 0.94, -- fraction of the cell the tile fills (small gap = individual blades read)
	GRASS_SHRINK_TWEEN = 0.12, -- seconds for the shrink animation per cut
	GRASS_MIN_STUB = 0.05, -- tile height at the instant before it is removed
	MIN_CUT_DAMAGE = 1, -- if a swing would deal less than this vs a grass type, it's "too tough"

	-- How the map is coated in grass.
	-- A builder tags any Part with the CollectionService tag below; the server grows a
	-- grid of grass tiles out of that part's TOP face (local +Y). Rotate the tagged part
	-- to aim the grass (e.g. lay a thin pad flat on a wall so its top points outward).
	-- Optional per-part attributes:
	--   GrassType (string)  -> which grass type to use (see GRASS_TYPES). Default DEFAULT_GRASS_TYPE.
	--   GrassHeight (number)-> override the grass height in studs.
	GRASS_SURFACE_TAG = "GrassSurface",
	DEFAULT_GRASS_TYPE = "Wild",
	MAX_TILES_PER_SURFACE = 4000, -- safety cap so one huge part can't spawn millions of tiles

	-- Grass types: each has its own "defense".
	--   health    = total damage needed to clear one tile
	--   armor     = flat damage subtracted from every swing (models toughness / defense)
	--   height    = how tall a fresh tile of this type stands (studs)
	--   value     = clipping value multiplier for this type
	--   color     = {r,g,b}
	-- A tool can only cut a type once its cut power exceeds that type's armor, so tougher
	-- grass literally requires better tools + power upgrades.
	GRASS_TYPES = {
		Meadow = { displayName = "Meadow Grass", health = 3, armor = 0, height = 2.6, value = 1.0, color = { 120, 196, 92 } },
		Wild = { displayName = "Wild Grass", health = 6, armor = 0, height = 4.8, value = 1.2, color = { 86, 158, 66 } },
		Thick = { displayName = "Thicket", health = 16, armor = 2, height = 5.6, value = 1.8, color = { 58, 120, 52 } },
		Moss = { displayName = "Creeping Moss", health = 12, armor = 1, height = 2.2, value = 1.5, color = { 74, 132, 86 } },
		Ironweed = { displayName = "Ironweed", health = 40, armor = 5, height = 5.0, value = 3.0, color = { 44, 92, 74 } },
	},

	-- Tool tiers.
	--   bladesPerSwing = base cut power (how much damage one swing deals before skills)
	--   cost           = Clippings cost to buy
	--   style          = which 3D model to build ("shears", "sickle", "scythe")
	--   handleColor / bladeColor = {r,g,b}
	--   bladeMaterial  = Enum.Material name
	--   toolScale      = overall size multiplier
	TOOL_TIERS = {
		{
			name = "Rusty Shears",
			bladesPerSwing = 1,
			cost = 0,
			style = "shears",
			handleColor = { 92, 64, 40 },
			bladeColor = { 138, 120, 96 },
			bladeMaterial = "CorrodedMetal",
			toolScale = 1.0,
		},
		{
			name = "Sickle",
			bladesPerSwing = 3,
			cost = 100,
			style = "sickle",
			handleColor = { 116, 80, 46 },
			bladeColor = { 198, 200, 210 },
			bladeMaterial = "Metal",
			toolScale = 1.1,
		},
		{
			name = "Scythe",
			bladesPerSwing = 8,
			cost = 750,
			style = "scythe",
			handleColor = { 74, 52, 34 },
			bladeColor = { 220, 224, 235 },
			bladeMaterial = "Metal",
			toolScale = 1.25,
		},
		-- Tiers 4-15 added in a later balancing pass
	},

	-- Kingdom Skills: small leveled upgrades
	SKILLS = {
		SharpBlades = { maxLevel = 100, effectPerLevel = 0.05, baseCost = 25, costGrowth = 1.08 }, -- +5% cut power / lvl
		QuickHands = { maxLevel = 50, effectPerLevel = 0.01, baseCost = 40, costGrowth = 1.10 }, -- +1% swing speed / lvl
		ClippingMagnet = { maxLevel = 40, effectPerLevel = 0.06, baseCost = 30, costGrowth = 1.09 }, -- +6% collect range / lvl
		GreenerThumb = { maxLevel = 100, effectPerLevel = 0.01, baseCost = 50, costGrowth = 1.07 }, -- +1% clipping value / lvl
	},

	-- Swing
	BASE_SWING_COOLDOWN = 0.5, -- seconds between swings before QuickHands
	CUT_RANGE = 16, -- max studs between player and a tile to cut it

	-- Clipping pickups (drop on the ground, collected by walking near them)
	BASE_COLLECT_RANGE = 8, -- studs; grown by the Clipping Magnet skill
	PICKUP_LIFETIME = 45, -- seconds a dropped clipping lasts before vanishing
	PICKUP_MAGNET_TIME = 0.16, -- seconds for a clipping to fly into the player

	-- Demo map (only generated if the builder hasn't tagged any GrassSurface parts yet)
	DEMO_ENABLED = true,
	DEMO_CENTER = Vector3.new(64, 0, 64),

	-- Shop (walk-in zone + always-on button both open the same menu)
	SHOP_POSITION = Vector3.new(-14, 0, -18),
	SHOP_ZONE_RADIUS = 16,
}

return GameConfig

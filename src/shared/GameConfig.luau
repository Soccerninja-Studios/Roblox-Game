--!strict
-- GameConfig: every tunable number in the game lives here.
-- Never hardcode balance values inside game logic; reference this module instead.

local GameConfig = {
	-- Intro cutscene: when true, the server plays the teddy-bear intro and, at the
	-- end, swaps the neighborhood out for the plains map (built centered on the
	-- house). When false, the plains map is built at the origin on server start so
	-- you can walk it directly -- handy for testing the map on its own.
	INTRO_CUTSCENE = false,

	-- Economy
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
	--   clipReward= total Clippings awarded when a tile of this type is FULLY cut down
	--               (before upgrade/gamepass multipliers). This is the guaranteed minimum,
	--               independent of how many swings clearing it actually took.
	--   color     = {r,g,b}
	-- A tool can only cut a type once its cut power exceeds that type's armor, so tougher
	-- grass literally requires better tools + power upgrades.
	GRASS_TYPES = {
		Meadow = { displayName = "Meadow Grass", health = 3, armor = 0, height = 2.6, clipReward = 3, color = { 120, 196, 92 } },
		Wild = { displayName = "Wild Grass", health = 6, armor = 0, height = 4.8, clipReward = 6, color = { 86, 158, 66 } },
		Thick = { displayName = "Thicket", health = 16, armor = 2, height = 5.6, clipReward = 25, color = { 58, 120, 52 } },
		Moss = { displayName = "Creeping Moss", health = 12, armor = 1, height = 2.2, clipReward = 15, color = { 74, 132, 86 } },
		Ironweed = { displayName = "Ironweed", health = 40, armor = 5, height = 5.0, clipReward = 80, color = { 44, 92, 74 } },
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

	-- World map layout. MapService builds a stone spawn plaza followed by a
	-- contiguous strip of grass zones (below), laid out along +X. All map geometry
	-- is generated from these numbers, so tweaking them reshapes the world.
	WORLD = {
		GROUND_THICKNESS = 2, -- how thick each ground pad is (studs); walkable top = this value
		STRIP_DEPTH = 64, -- Z depth of the plaza and every zone (keeps the strip aligned)
		PLAZA_SIZE = 48, -- X length of the stone spawn plaza (holds the spawn point + shop)
		PLAZA_COLOR = { 150, 146, 138 },
		BORDER_COLOR = { 96, 90, 82 },
		SIGN_POST_COLOR = { 92, 64, 40 },
	},

	-- Grass zones, in progression order (easiest first). Each becomes one ground pad
	-- laid end-to-end after the plaza, tagged so GrassService grows its grass type.
	-- ADD A ZONE by adding a line here -- no code changes needed anywhere.
	--   key          = unique id (also the workspace part name, Zone_<key>)
	--   displayName  = shown on the entrance sign
	--   grassType    = which GRASS_TYPES entry to grow (drives reward + toughness)
	--   length       = X length of the pad in studs (depth is WORLD.STRIP_DEPTH)
	--   groundColor  = {r,g,b} of the dirt beneath the grass
	--   requiredTool = tool named on the sign as the one strong enough to harvest it
	ZONES = {
		{ key = "Meadow", displayName = "Meadow", grassType = "Meadow", length = 64, groundColor = { 120, 92, 60 }, requiredTool = "Rusty Shears" },
		{ key = "Wild", displayName = "Wildfields", grassType = "Wild", length = 64, groundColor = { 98, 74, 52 }, requiredTool = "Rusty Shears" },
		{ key = "Moss", displayName = "Mossy Hollow", grassType = "Moss", length = 64, groundColor = { 78, 74, 58 }, requiredTool = "Sickle" },
		{ key = "Thick", displayName = "The Thicket", grassType = "Thick", length = 64, groundColor = { 74, 62, 46 }, requiredTool = "Sickle" },
		{ key = "Ironweed", displayName = "Ironweed Expanse", grassType = "Ironweed", length = 72, groundColor = { 60, 56, 50 }, requiredTool = "Scythe" },
	},

	-- Demo map: legacy single-field sandbox, now superseded by the real map above and
	-- kept OFF. If you ever want the old sandbox back, set DEMO_ENABLED = true; it only
	-- builds when nothing (including MapService) has tagged a GrassSurface part.
	DEMO_ENABLED = false,
	DEMO_CENTER = Vector3.new(64, 0, 64),

	-- Shop (walk-in zone + always-on button both open the same menu). It sits in the
	-- Village 1 square, mirroring the Gardener's Hut across the well. Y = 0 is the
	-- village ground top, so ShopService rests the stall on the ground.
	SHOP_POSITION = Vector3.new(-20, 0, 18),
	SHOP_ZONE_RADIUS = 16,
}

return GameConfig

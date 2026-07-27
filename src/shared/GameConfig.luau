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

	-- Currency + bag. The core loop: mow grass -> clippings fill your carry BAG ->
	-- deposit them at the Gardener to bank GOLD (and, rarely, DIAMONDS) -> spend gold
	-- on tools, skills, and bigger bags.
	CLIPPING_TO_GOLD = 1, -- gold banked per clipping deposited
	-- Diamonds: a rare bonus at deposit time. Every DIAMOND_ROLL_PER_CLIPPINGS
	-- clippings deposited rolls once at DIAMOND_CHANCE for one diamond (so ~5% per
	-- 50 clippings by default -- roughly one diamond per ~1,000 clippings).
	DIAMOND_ROLL_PER_CLIPPINGS = 50,
	DIAMOND_CHANCE = 0.05,
	-- LEGACY. Superseded by BACKPACKS below. Kept only because UpgradeService still
	-- handles PurchaseUpgrade("bag") against this table; removing it would break that
	-- path. Nothing in the UI points here any more.
	BAG_TIERS = {
		{ capacity = 25, cost = 0 },
		{ capacity = 60, cost = 150 },
		{ capacity = 150, cost = 600 },
		{ capacity = 400, cost = 2500 },
		{ capacity = 1000, cost = 9000 },
	},

	-- Backpacks: one per zone, each bought once and then upgraded on its own track.
	-- The EQUIPPED pack alone decides how many clippings you can carry, so a later
	-- pack is a straight upgrade rather than a side-grade.
	--   zone            gate: the grass type you must have cut to buy it (same
	--                   quests.reached check the auto-mowers use)
	--   levels          capacity ladder. Level 1 comes with the purchase, so its cost
	--                   is always 0; later entries are the gold price of that level.
	--   autoDepositCost one-off unlock, per pack: a full bag banks itself from
	--                   anywhere instead of making you walk back to the Gardener.
	--   shape           which procedural model BackpackService builds for the back.
	--   color / accent  body and trim colours for that model and its shop card.
	BACKPACKS = {
		{
			key = "basket",
			name = "Woven Basket",
			zone = "Meadow",
			desc = "Reed basket the whole kingdom starts with.",
			shape = "basket",
			goldCost = 0,
			diamondCost = 0,
			autoDepositCost = 1200,
			autoDepositDiamondCost = 0,
			color = { 196, 158, 96 },
			accent = { 232, 210, 148 },
			levels = {
				{ capacity = 25, cost = 0 },
				{ capacity = 45, cost = 150 },
				{ capacity = 70, cost = 450 },
				{ capacity = 105, cost = 1100 },
				{ capacity = 150, cost = 2400 },
			},
		},
		{
			key = "satchel",
			name = "Field Satchel",
			zone = "Wild",
			desc = "Waxed canvas with room for a real haul.",
			shape = "satchel",
			goldCost = 3000,
			diamondCost = 0,
			autoDepositCost = 6000,
			autoDepositDiamondCost = 10,
			color = { 122, 96, 62 },
			accent = { 208, 176, 108 },
			levels = {
				{ capacity = 240, cost = 0 },
				{ capacity = 330, cost = 1400 },
				{ capacity = 450, cost = 3200 },
				{ capacity = 600, cost = 6400 },
				{ capacity = 800, cost = 12000 },
			},
		},
		{
			key = "rucksack",
			name = "Mire Rucksack",
			zone = "Moss",
			desc = "Sealed against bog water and spores.",
			shape = "rucksack",
			goldCost = 22000,
			diamondCost = 20,
			autoDepositCost = 30000,
			autoDepositDiamondCost = 25,
			color = { 74, 108, 84 },
			accent = { 152, 204, 150 },
			levels = {
				{ capacity = 1100, cost = 0 },
				{ capacity = 1500, cost = 8000 },
				{ capacity = 2000, cost = 16000 },
				{ capacity = 2700, cost = 30000 },
				{ capacity = 3600, cost = 55000 },
			},
		},
		{
			key = "bramblepack",
			name = "Bramble Pack",
			zone = "Thick",
			desc = "Thorn-proof hide over a hardwood frame.",
			shape = "frame",
			goldCost = 120000,
			diamondCost = 45,
			autoDepositCost = 150000,
			autoDepositDiamondCost = 60,
			color = { 58, 74, 48 },
			accent = { 176, 148, 92 },
			levels = {
				{ capacity = 4800, cost = 0 },
				{ capacity = 6400, cost = 40000 },
				{ capacity = 8600, cost = 85000 },
				{ capacity = 11500, cost = 160000 },
				{ capacity = 15000, cost = 300000 },
			},
		},
		{
			key = "hauler",
			name = "Ironweed Hauler",
			zone = "Ironweed",
			desc = "Humming containment field. Holds a field's worth.",
			shape = "hauler",
			goldCost = 600000,
			diamondCost = 120,
			autoDepositCost = 750000,
			autoDepositDiamondCost = 150,
			color = { 46, 92, 74 },
			accent = { 150, 245, 170 },
			levels = {
				{ capacity = 20000, cost = 0 },
				{ capacity = 27000, cost = 200000 },
				{ capacity = 36000, cost = 420000 },
				{ capacity = 48000, cost = 800000 },
				{ capacity = 65000, cost = 1500000 },
			},
		},
	},

	-- How often BackpackService checks an auto-depositing pack for a full bag.
	BACKPACK_AUTO_DEPOSIT_TICK = 0.5,

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

	-- Tool tiers form the progression LADDER. You always wield your highest owned
	-- tier; buying the next tier in the Shop swaps your tool. The ladder alternates
	-- balanced ALL-ROUNDER tools with grass-TYPE SPECIALISTS, and ends in one
	-- ultimate tool that shreds every grass type.
	--   bladesPerSwing = base cut power (damage per swing before skills + type bonus)
	--   cost           = Gold cost to buy the tier (bought in order)
	--   style          = which 3D model to build ("shears", "sickle", "scythe")
	--   favored        = grass type this tool EXCELS at (see GRASS_TYPES); "all" for
	--                    the ultimate; nil for a balanced all-rounder
	--   favoredMul     = cut-power multiplier vs favored grass (or vs ALL for "all")
	--   offMul         = cut-power multiplier vs every OTHER grass type
	--   handleColor / bladeColor = {r,g,b}
	--   bladeMaterial  = Enum.Material name
	--   toolScale      = overall size multiplier
	TOOL_TIERS = {
		-- 1 \u{00B7} all-rounder (starter)
		{ name = "Rusty Shears", bladesPerSwing = 1, cost = 0, style = "shears", favored = nil, handleColor = { 92, 64, 40 }, bladeColor = { 138, 120, 96 }, bladeMaterial = "CorrodedMetal", toolScale = 1.0 },
		-- 2 \u{00B7} specialist: Meadow
		{ name = "Meadow Trimmer", bladesPerSwing = 8, cost = 300, style = "shears", favored = "Meadow", favoredMul = 2.6, offMul = 0.7, handleColor = { 108, 78, 46 }, bladeColor = { 176, 214, 150 }, bladeMaterial = "Metal", toolScale = 1.05 },
		-- 3 \u{00B7} all-rounder
		{ name = "Steel Shears", bladesPerSwing = 7, cost = 900, style = "shears", favored = nil, handleColor = { 70, 74, 82 }, bladeColor = { 198, 204, 214 }, bladeMaterial = "Metal", toolScale = 1.1 },
		-- 4 \u{00B7} specialist: Wild
		{ name = "Bramble Sickle", bladesPerSwing = 13, cost = 2500, style = "sickle", favored = "Wild", favoredMul = 2.6, offMul = 0.7, handleColor = { 96, 68, 40 }, bladeColor = { 120, 168, 96 }, bladeMaterial = "Metal", toolScale = 1.12 },
		-- 5 \u{00B7} all-rounder
		{ name = "Garden Sickle", bladesPerSwing = 15, cost = 6000, style = "sickle", favored = nil, handleColor = { 116, 80, 46 }, bladeColor = { 210, 214, 224 }, bladeMaterial = "Metal", toolScale = 1.15 },
		-- 6 \u{00B7} specialist: Moss
		{ name = "Moss Whip", bladesPerSwing = 20, cost = 14000, style = "scythe", favored = "Moss", favoredMul = 2.6, offMul = 0.7, handleColor = { 60, 82, 58 }, bladeColor = { 150, 198, 150 }, bladeMaterial = "Metal", toolScale = 1.18 },
		-- 7 \u{00B7} all-rounder
		{ name = "Keen Scythe", bladesPerSwing = 26, cost = 32000, style = "scythe", favored = nil, handleColor = { 74, 52, 34 }, bladeColor = { 220, 224, 235 }, bladeMaterial = "Metal", toolScale = 1.22 },
		-- 8 \u{00B7} specialist: Thicket
		{ name = "Thornbite Machete", bladesPerSwing = 30, cost = 70000, style = "scythe", favored = "Thick", favoredMul = 2.6, offMul = 0.7, handleColor = { 58, 44, 30 }, bladeColor = { 90, 150, 84 }, bladeMaterial = "Metal", toolScale = 1.25 },
		-- 9 \u{00B7} all-rounder
		{ name = "Royal Reaper", bladesPerSwing = 44, cost = 150000, style = "scythe", favored = nil, handleColor = { 60, 44, 74 }, bladeColor = { 236, 232, 210 }, bladeMaterial = "Metal", toolScale = 1.3 },
		-- 10 \u{00B7} specialist: Ironweed
		{ name = "Ironfang Scythe", bladesPerSwing = 40, cost = 320000, style = "scythe", favored = "Ironweed", favoredMul = 2.6, offMul = 0.7, handleColor = { 40, 44, 48 }, bladeColor = { 120, 140, 150 }, bladeMaterial = "Metal", toolScale = 1.34 },
		-- 11 \u{00B7} ULTIMATE: excels at every grass type
		{ name = "Verdant Kingcutter", bladesPerSwing = 70, cost = 900000, style = "scythe", favored = "all", favoredMul = 1.6, handleColor = { 40, 90, 60 }, bladeColor = { 180, 245, 170 }, bladeMaterial = "Neon", toolScale = 1.42 },
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

	-- Dash: tap the dash key to burst a short distance in the direction you are
	-- moving (standing still dashes whichever way you are facing). The distance is
	-- measured in CHARACTER HEIGHTS so it scales with the avatar instead of being a
	-- magic stud count -- an R6 body is ~5 studs tall, so 2 heights is a ~10-stud hop.
	DASH = {
		key = Enum.KeyCode.Q,
		distanceInHeights = 2, -- how far one dash travels, in character heights
		duration = 0.18, -- seconds the burst lasts (shorter = snappier)
		cooldown = 1, -- seconds before you can dash again
	},

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

	-- Shop (walk-in zone + always-on button both open the same menu). Placed at the
	-- front-right of the house on the plains: HouseCenter (-564.75, -1.5, -999) plus
	-- +40 studs to the right (X) and +95 studs toward the front (Z, the spawn side),
	-- resting on the ground (Y = -1.5). It sits inside MapService's central clear
	-- radius so no grass grows over it. ShopService rests the stall on this point.
	SHOP_POSITION = Vector3.new(-480, 5.75, -953),
	SHOP_ZONE_RADIUS = 16,

	-- Gardener deposit stand: walk into its glowing pad to bank everything in your
	-- bag. Placed at the front-LEFT of the house (mirror of the shop across the house
	-- center X = -564.75), resting on the ground (Y = -1.5).
	GARDENER_POSITION = Vector3.new(-479.75, -0.16, -1037),
	GARDENER_ZONE_RADIUS = 14,

	-- Quest Giver ("Sprigman The Questgiver"): hands out the zone quest board. Placed
	-- at the front-CENTER of the house, between the shop and the gardener, on the
	-- ground (Y = -0.16). Walk near and press the prompt to open the quest board.
	QUEST_GIVER_POSITION = Vector3.new(-467.049, 1.854, -1013.96),
	-- Y-axis facing (degrees) for Sprigman. This is the exact transform placed in
	-- Studio, so QUEST_GIVER_POSITION is the character's root position (not the
	-- ground point) -- QuestGiverService uses it directly without lifting.
	QUEST_GIVER_ORIENTATION_Y = 135,
	QUEST_GIVER_ZONE_RADIUS = 10,

	-- Admin panel: Roblox usernames allowed to open the in-game Admin panel and
	-- grant themselves gold/diamonds while testing (so you don't have to grind
	-- resources to test features). The server re-validates every request against
	-- this list (see AdminService), so only these users can use it.
	ADMINS = { "soccerninja4516" },

	-- Auto-Mowers: deployable idle units bought once with gold + diamonds. Once
	-- owned, DEPLOY one to send a little mower roaming the hub; it passively makes
	-- clippings into its own storage and, when that storage fills, AUTO-BANKS the
	-- clippings straight to gold (no Gardener trip needed). This is the premium idle
	-- layer from docs/PROGRESSION.md section 6.
	--   key         = unique id (also the workspace model suffix)
	--   name        = display name (matches the auto-mower quests in QuestData)
	--   zone        = grass zone you must have reached to buy it (see ZONES). This is
	--                 also the ONLY grass this mower will ever cut. Unlike the
	--                 player's tools, a mower does NOT fall back to easier zones --
	--                 each zone gets its own dedicated mower.
	--   modelName   = name of the model under ReplicatedStorage.Assets to spawn.
	--                 Falls back to a built-from-scratch box mower if it is missing.
	--   modelLength = 0 keeps the model at the exact size it was authored at in
	--                 ReplicatedStorage, which is what every mower uses. Set it to a
	--                 stud length ONLY to force a rescale of that one mower; a
	--                 uniform length made the bot tiny and the harvester enormous.
	--   modelYaw    = manual steering correction in DEGREES, added on top of the
	--                 automatic one. MowerRig measures each model and fixes the
	--                 90-degree "driving sideways" case on its own, but it cannot
	--                 tell front from back. If a mower drives in reverse, set this
	--                 to 180. Other useful values: 90 and -90. The values below were
	--                 each confirmed in-game.
	--   hoverOffset = extra studs of lift, ON TOP of the automatic ground seating.
	--                 0 for anything with wheels. Raise it for a model whose mesh
	--                 hangs below its own bounding box and so digs into the dirt.
	--   moveSpeed   = studs per second it drives while seeking grass or hauling
	--   cutPower    = health removed per cut swing (armor is subtracted from this)
	--   cutInterval = seconds between its cut swings
	--   ratePerSec  = LEGACY: kept only for the shop blurb. Income now comes from
	--                 grass the mower actually cuts, not from a passive rate.
	--   storageCap  = clippings it holds before it hauls back to the Gardener
	--   goldCost / diamondCost = one-time purchase price
	--   bodyColor   = {r,g,b} of the little mower body
	--   desc        = one-line blurb for the shop panel
	AUTO_MOWER_TICK = 1, -- seconds between idle-income ticks
	-- Where deployed mowers appear (a clear patch just west of the hub). Each roams
	-- a few studs around its slot. Placement will tighten once the 5 physical zones
	-- are built; for now every mower deploys here in the shared hub.
	AUTO_MOWER_DEPLOY_ANCHOR = Vector3.new(-505, 2.5, -1000),
	AUTO_MOWER_SLOT_SPACING = 7, -- studs between each mower's parking slot (along Z)
	-- How far a mower looks for its next tile. It sweeps outward from its own
	-- position in STEP increments up to MAX so a mower in a cleared patch will still
	-- find work further out instead of idling.
	AUTO_MOWER_SEARCH_STEP = 80,
	-- Reaches the outer Ironweed ring (~1145 studs from the plains centre) from the
	-- shared hub anchor. Mowers only cut their own zone now, so this MUST stay large
	-- enough for a late-zone mower to see its ring or it would park forever.
	AUTO_MOWER_SEARCH_MAX = 1600,
	-- Studs from a tile before the mower is considered "on" it and starts cutting.
	AUTO_MOWER_ARRIVE_DIST = 4,
	-- Studs from the Gardener before a hauling mower can unload.
	AUTO_MOWER_DEPOSIT_DIST = 8,
	-- Seconds between mower brain ticks (movement is tweened between ticks).
	AUTO_MOWER_BRAIN_TICK = 0.25,
	-- Hover height above a tile's base so mowers sit on the ground, not inside it.
	AUTO_MOWER_HOVER = 1.6,
	AUTO_MOWERS = {
		{ key = "push", name = "Push Mower", zone = "Meadow", modelName = "PushMower", modelLength = 0, modelYaw = 180, hoverOffset = 0, moveSpeed = 14, cutPower = 4, cutInterval = 0.50, ratePerSec = 2, storageCap = 180, goldCost = 500, diamondCost = 20, bodyColor = { 120, 196, 92 }, desc = "Starter automation for the Meadow." },
		{ key = "reel", name = "Reel Mower", zone = "Wild", modelName = "ReelMower", modelLength = 0, modelYaw = 180, hoverOffset = 0, moveSpeed = 18, cutPower = 9, cutInterval = 0.45, ratePerSec = 5, storageCap = 450, goldCost = 1500, diamondCost = 45, bodyColor = { 86, 158, 66 }, desc = "Handles tougher Wild grass." },
		{ key = "brushcutter", name = "Brushcutter Bot", zone = "Moss", modelName = "BrushcutterBot", modelLength = 0, modelYaw = 90, hoverOffset = 0, moveSpeed = 20, cutPower = 20, cutInterval = 0.40, ratePerSec = 12, storageCap = 1080, goldCost = 5000, diamondCost = 90, bodyColor = { 58, 120, 52 }, desc = "Walking legs keep it upright on rough ground." },
		{ key = "hover", name = "Hover Mower", zone = "Thick", modelName = "HoverMower", modelLength = 0, modelYaw = 0, hoverOffset = 0, moveSpeed = 26, cutPower = 16, cutInterval = 0.35, ratePerSec = 28, storageCap = 2520, goldCost = 15000, diamondCost = 160, bodyColor = { 74, 132, 86 }, desc = "Floats clean over bog water and tangled roots." },
		{ key = "plasma", name = "Plasma Harvester", zone = "Ironweed", modelName = "PlasmaHarvester", modelLength = 0, modelYaw = 0, hoverOffset = 2, moveSpeed = 32, cutPower = 50, cutInterval = 0.30, ratePerSec = 60, storageCap = 5400, goldCost = 50000, diamondCost = 300, bodyColor = { 150, 245, 170 }, desc = "Endgame idle engine." },
	},
}

return GameConfig

--!strict
-- GameConfig: every tunable number in the game lives here.
-- Never hardcode balance values inside game logic; reference this module instead.

local GameConfig = {
	-- Intro cutscene: when true, the server plays the teddy-bear intro and, at the
	-- end, swaps the neighborhood out for the plains map (built centered on the
	-- house). When false, the plains map is built at the origin on server start so
	-- you can walk it directly -- handy for testing the map on its own.
	INTRO_CUTSCENE = true,

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
			zone = "Mossmire",
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
			zone = "Thicket",
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
		Thicket = { displayName = "Thicket", health = 16, armor = 2, height = 5.6, clipReward = 25, color = { 58, 120, 52 } },
		Mossmire = { displayName = "Creeping Moss", health = 12, armor = 1, height = 2.2, clipReward = 15, color = { 74, 132, 86 } },
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
		{ name = "Meadow Trimmer", modelRot = { 0, 0, 0 }, swingRot = { 0, -58, 0 }, sweep = true, bladesPerSwing = 8, cost = 300, style = "shears", favored = "Meadow", favoredMul = 2.6, offMul = 0.7, handleColor = { 108, 78, 46 }, bladeColor = { 176, 214, 150 }, bladeMaterial = "Metal", toolScale = 1.05 },
		-- 3 \u{00B7} all-rounder
		{ name = "Steel Shears", bladesPerSwing = 7, cost = 900, style = "shears", favored = nil, handleColor = { 70, 74, 82 }, bladeColor = { 198, 204, 214 }, bladeMaterial = "Metal", toolScale = 1.1 },
		-- 4 \u{00B7} specialist: Wild
		{ name = "Bramble Sickle", modelRot = { 0, 90, 0 }, bladesPerSwing = 13, cost = 2500, style = "sickle", favored = "Wild", favoredMul = 2.6, offMul = 0.7, handleColor = { 96, 68, 40 }, bladeColor = { 120, 168, 96 }, bladeMaterial = "Metal", toolScale = 1.12 },
		-- 5 \u{00B7} all-rounder
		{ name = "Garden Sickle", bladesPerSwing = 15, cost = 6000, style = "sickle", favored = nil, handleColor = { 116, 80, 46 }, bladeColor = { 210, 214, 224 }, bladeMaterial = "Metal", toolScale = 1.15 },
		-- 6 \u{00B7} specialist: Mossmire
		{ name = "Bogblade", modelRot = { 0, 180, 0 }, bladesPerSwing = 20, cost = 14000, style = "scythe", favored = "Mossmire", favoredMul = 2.6, offMul = 0.7, handleColor = { 60, 82, 58 }, bladeColor = { 150, 198, 150 }, bladeMaterial = "Metal", toolScale = 1.18 },
		-- 7 \u{00B7} all-rounder
		{ name = "Keen Scythe", modelRot = { 0, -90, 0 }, bladesPerSwing = 26, cost = 32000, style = "scythe", favored = nil, handleColor = { 74, 52, 34 }, bladeColor = { 220, 224, 235 }, bladeMaterial = "Metal", toolScale = 1.22 },
		-- 8 \u{00B7} specialist: Thicket
		{ name = "Thornbite Machete", bladesPerSwing = 30, cost = 70000, style = "scythe", favored = "Thicket", favoredMul = 2.6, offMul = 0.7, handleColor = { 58, 44, 30 }, bladeColor = { 90, 150, 84 }, bladeMaterial = "Metal", toolScale = 1.25 },
		-- 9 \u{00B7} all-rounder
		{ name = "Royal Reaper", modelRot = { 0, 180, 0 }, bladesPerSwing = 44, cost = 150000, style = "scythe", favored = nil, handleColor = { 60, 44, 74 }, bladeColor = { 236, 232, 210 }, bladeMaterial = "Metal", toolScale = 1.3 },
		-- 10 \u{00B7} specialist: Ironweed
		{ name = "Ironfang Scythe", modelRot = { 0, 90, 90 }, bladesPerSwing = 40, cost = 320000, style = "scythe", favored = "Ironweed", favoredMul = 2.6, offMul = 0.7, handleColor = { 40, 44, 48 }, bladeColor = { 120, 140, 150 }, bladeMaterial = "Metal", toolScale = 1.34 },
		-- 11 \u{00B7} ULTIMATE: excels at every grass type
		{ name = "Verdant Kingcutter", bladesPerSwing = 70, cost = 900000, style = "scythe", favored = "all", favoredMul = 1.6, handleColor = { 40, 90, 60 }, bladeColor = { 180, 245, 170 }, bladeMaterial = "Metal", toolScale = 1.42 },
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
		{ key = "Mossmire", displayName = "Mossmire", grassType = "Mossmire", length = 64, groundColor = { 78, 74, 58 }, requiredTool = "Sickle" },
		{ key = "Thicket", displayName = "Thicket", grassType = "Thicket", length = 64, groundColor = { 74, 62, 46 }, requiredTool = "Sickle" },
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
		{ key = "brushcutter", name = "Brushcutter Bot", zone = "Mossmire", modelName = "BrushcutterBot", modelLength = 0, modelYaw = 90, hoverOffset = 0, moveSpeed = 20, cutPower = 20, cutInterval = 0.40, ratePerSec = 12, storageCap = 1080, goldCost = 5000, diamondCost = 90, bodyColor = { 58, 120, 52 }, desc = "Walking legs keep it upright on rough ground." },
		{ key = "hover", name = "Hover Mower", zone = "Thicket", modelName = "HoverMower", modelLength = 0, modelYaw = 0, hoverOffset = 0, moveSpeed = 26, cutPower = 16, cutInterval = 0.35, ratePerSec = 28, storageCap = 2520, goldCost = 15000, diamondCost = 160, bodyColor = { 74, 132, 86 }, desc = "Floats clean over bog water and tangled roots." },
		{ key = "plasma", name = "Plasma Harvester", zone = "Ironweed", modelName = "PlasmaHarvester", modelLength = 0, modelYaw = 0, hoverOffset = 2, moveSpeed = 32, cutPower = 50, cutInterval = 0.30, ratePerSec = 60, storageCap = 5400, goldCost = 50000, diamondCost = 300, bodyColor = { 150, 245, 170 }, desc = "Endgame idle engine." },
	},

	-- =========================================================================
	-- COMBAT (Phase 3: swords + monsters + bosses). All five zones have their
	-- common combat pair, boss encounter, per-zone essence, and sword progression.
	-- =========================================================================

	-- Player health, scaled by the toughest zone you have REACHED. Design goal: HP
	-- climbs from a fragile 3 in the Meadow up to 50 in the Ironweed Expanse.
	COMBAT = {
		defaultMaxHP = 3,
		zoneMaxHP = { Meadow = 3, Wild = 8, Mossmire = 16, Thicket = 30, Ironweed = 50 },
		regenPerSecond = 1, -- HP healed per second once out of combat
		regenDelay = 5, -- seconds after the last hit before regen kicks in
		scatterPileLifetime = 45, -- (unused) death piles are now PERMANENT until reclaimed
		scatterReclaimRange = 6, -- studs you must get within to reclaim the pile
	},

	-- Monster spawning uses a self-correcting PITY chance rolled every time a tile is
	-- fully cleared. Right after a spawn the chance is suppressed (so monsters can''t
	-- cluster); through a drought it ramps up; and after a hard cap a spawn is
	-- GUARANTEED (so it can never dry up). Base is ~10%.
	MONSTER_SPAWN = {
		baseChance = 0.10,
		minChance = 0.02, -- floor right after a spawn
		maxChance = 0.85, -- ceiling reached through a drought
		suppressTiles = 4, -- tiles after a spawn spent ramping back up to base
		droughtRamp = 0.05, -- +5% chance per dry tile once past the suppression window
		guaranteeAfter = 24, -- a spawn is guaranteed after this many dry tiles
		maxAlivePerZone = 12, -- do not oversaturate a zone
	},

	-- Per-zone combat currency dropped by monsters and spent on combat purchases.
	ESSENCE = {
		MeadowPollen = { name = "Meadow Pollen", zone = "Meadow", color = { 240, 214, 110 } },
		WildBurr = { name = "Wild Burr", zone = "Wild", color = { 196, 146, 86 } },
		MireSpore = { name = "Mire Spore", zone = "Mossmire", color = { 142, 116, 190 } },
		ThicketSap = { name = "Thicket Sap", zone = "Thicket", color = { 92, 170, 90 } },
		IronFilament = { name = "Iron Filament", zone = "Ironweed", color = { 116, 176, 188 } },
	},

	-- Monsters. spawnWeight is the relative chance of THIS monster when a spawn fires
	-- in its zone. hp/damage/speed drive the fight; goldReward + essence are the
	-- payout for killing it.
	MONSTERS = {
		{ key = "weedSprite", name = "Weed Sprite", zone = "Meadow", hp = 12, damage = 1, moveSpeed = 11, attackRange = 6, attackCooldown = 1.4, aggroRange = 42, roamRange = 22, spawnWeight = 70, goldReward = 8, essenceKey = "MeadowPollen", essenceReward = 2, scale = 1.0, bodyColor = { 120, 196, 92 }, headColor = { 150, 220, 120 } },
		{ key = "gardenGnome", name = "Garden Gnome", zone = "Meadow", hp = 30, damage = 1, moveSpeed = 8, attackRange = 6.5, attackCooldown = 1.1, aggroRange = 48, roamRange = 18, spawnWeight = 30, goldReward = 22, essenceKey = "MeadowPollen", essenceReward = 5, scale = 1.15, bodyColor = { 180, 84, 70 }, headColor = { 235, 220, 190 } },
		{ key = "thistleGoblin", name = "Thistle Goblin", zone = "Wild", hp = 78, damage = 2, moveSpeed = 12, attackRange = 6, attackCooldown = 1.25, aggroRange = 48, roamRange = 24, spawnWeight = 65, goldReward = 28, essenceKey = "WildBurr", essenceReward = 3, scale = 1.08, bodyColor = { 104, 146, 72 }, headColor = { 148, 92, 164 } },
		{ key = "brambleCrawler", name = "Bramble Crawler", zone = "Wild", hp = 126, damage = 3, moveSpeed = 10, attackRange = 6.5, attackCooldown = 1.2, aggroRange = 52, roamRange = 22, spawnWeight = 35, goldReward = 60, essenceKey = "WildBurr", essenceReward = 6, scale = 1.2, bodyColor = { 92, 68, 44 }, headColor = { 86, 146, 68 } },
		{ key = "sporeHound", name = "Spore Hound", zone = "Mossmire", hp = 540, damage = 4, moveSpeed = 11.5, attackRange = 6, attackCooldown = 1.25, aggroRange = 54, roamRange = 25, spawnWeight = 60, goldReward = 95, essenceKey = "MireSpore", essenceReward = 8, scale = 1.15, bodyColor = { 96, 118, 82 }, headColor = { 164, 126, 190 } },
		{ key = "bogWraith", name = "Bog Wraith", zone = "Mossmire", hp = 780, damage = 5, moveSpeed = 9.5, attackRange = 7, attackCooldown = 1.35, aggroRange = 58, roamRange = 22, spawnWeight = 40, goldReward = 180, essenceKey = "MireSpore", essenceReward = 14, scale = 1.3, bodyColor = { 54, 92, 86 }, headColor = { 126, 186, 164 } },
		{ key = "vineLurker", name = "Vine Lurker", zone = "Thicket", hp = 1260, damage = 7, moveSpeed = 12, attackRange = 6.5, attackCooldown = 1.15, aggroRange = 60, roamRange = 26, spawnWeight = 60, goldReward = 260, essenceKey = "ThicketSap", essenceReward = 18, scale = 1.2, bodyColor = { 58, 112, 52 }, headColor = { 96, 164, 76 } },
		{ key = "barkGolemling", name = "Bark Golemling", zone = "Thicket", hp = 1950, damage = 9, moveSpeed = 8.5, attackRange = 7.5, attackCooldown = 1.4, aggroRange = 62, roamRange = 20, spawnWeight = 40, goldReward = 480, essenceKey = "ThicketSap", essenceReward = 30, scale = 1.4, bodyColor = { 92, 66, 42 }, headColor = { 126, 94, 58 } },
		{ key = "weedwraith", name = "Weedwraith", zone = "Ironweed", hp = 3000, damage = 12, moveSpeed = 13, attackRange = 7, attackCooldown = 1.05, aggroRange = 66, roamRange = 28, spawnWeight = 58, goldReward = 700, essenceKey = "IronFilament", essenceReward = 30, scale = 1.28, bodyColor = { 44, 78, 72 }, headColor = { 94, 154, 160 } },
		{ key = "ironcladSentinel", name = "Ironclad Sentinel", zone = "Ironweed", hp = 4800, damage = 16, moveSpeed = 8, attackRange = 8, attackCooldown = 1.35, aggroRange = 70, roamRange = 20, spawnWeight = 42, goldReward = 1250, essenceKey = "IronFilament", essenceReward = 50, scale = 1.5, bodyColor = { 74, 84, 90 }, headColor = { 130, 152, 160 } },
	},

	-- Bosses awaken when the final tile in their ring is cleared. Every attack is
	-- telegraphed before server-side damage is applied. The same definitions power
	-- spawning, health UI, rewards, quest validation, and the combat state machine.
	BOSS_SYSTEM = {
		respawnSeconds = 60,
		hudRange = 260,
	},

	BOSSES = {
		{
			key = "dandelionTitan", name = "Dandelion Titan", zone = "Meadow", visual = "flower",
			hp = 420, damage = 1, moveSpeed = 6.5, attackRange = 8, attackCooldown = 1.45,
			aggroRange = 80, resetDelay = 10, scale = 2.15, globalAbilityCooldown = 2.3,
			bodyColor = { 116, 178, 72 }, headColor = { 214, 174, 72 }, accentColor = { 250, 218, 92 },
			goldReward = 400, diamondReward = 4, essenceKey = "MeadowPollen", essenceReward = 25,
			abilities = {
				{ kind = "summon", label = "Seedling Call", count = 2, windup = 0.7, cooldown = 10 },
				{ kind = "spikes", label = "Dandelion Burst", pattern = "ring", count = 6, ringRadius = 11, radius = 3, height = 6, damage = 1, windup = 1.2, cooldown = 8 },
				{ kind = "slam", label = "Pollen Slam", radius = 10, height = 3, damage = 1, windup = 1.05, cooldown = 7 },
			},
		},
		{
			key = "brambleBroodmother", name = "Bramble Broodmother", zone = "Wild", visual = "broodmother",
			hp = 2200, damage = 3, moveSpeed = 7.5, attackRange = 8.5, attackCooldown = 1.3,
			aggroRange = 88, resetDelay = 10, scale = 2.25, globalAbilityCooldown = 2.2,
			bodyColor = { 88, 62, 42 }, headColor = { 116, 156, 70 }, accentColor = { 174, 116, 194 },
			goldReward = 1800, diamondReward = 9, essenceKey = "WildBurr", essenceReward = 45,
			abilities = {
				{ kind = "summon", label = "Hatch the Brood", count = 3, windup = 0.65, cooldown = 9 },
				{ kind = "spikes", label = "Bramble Trail", pattern = "line", count = 6, spacing = 6, radius = 3.3, height = 7, damage = 2, windup = 1.05, cooldown = 7.5 },
				{ kind = "charge", label = "Broodmother Charge", width = 8, maxDistance = 38, damage = 3, windup = 0.9, duration = 0.5, cooldown = 8.5 },
			},
		},
		{
			key = "mirequeen", name = "Mirequeen", zone = "Mossmire", visual = "mirequeen",
			hp = 9000, damage = 6, moveSpeed = 7, attackRange = 9, attackCooldown = 1.35,
			aggroRange = 94, resetDelay = 11, scale = 2.45, globalAbilityCooldown = 2.1,
			bodyColor = { 54, 90, 82 }, headColor = { 130, 110, 170 }, accentColor = { 174, 126, 214 }, poolColor = { 76, 142, 106 },
			goldReward = 6500, diamondReward = 18, essenceKey = "MireSpore", essenceReward = 90,
			abilities = {
				{ kind = "summon", label = "Mireborn Call", count = 3, windup = 0.7, cooldown = 10 },
				{ kind = "pools", label = "Spore Bloom", count = 3, radius = 5, spread = 10, damage = 2, windup = 1.1, duration = 5, tickRate = 1, cooldown = 8 },
				{ kind = "slam", label = "Royal Mirewave", radius = 13, height = 4, damage = 5, windup = 1.2, cooldown = 9 },
			},
		},
		{
			key = "elderVinewrath", name = "Elder Vinewrath", zone = "Thicket", visual = "vine",
			hp = 22000, damage = 11, moveSpeed = 7.5, attackRange = 9.5, attackCooldown = 1.25,
			aggroRange = 100, resetDelay = 11, scale = 2.65, globalAbilityCooldown = 2.0,
			bodyColor = { 70, 88, 46 }, headColor = { 94, 140, 64 }, accentColor = { 88, 182, 92 },
			goldReward = 20000, diamondReward = 38, essenceKey = "ThicketSap", essenceReward = 160,
			abilities = {
				{ kind = "summon", label = "Ancient Growth", count = 4, windup = 0.65, cooldown = 10 },
				{ kind = "spikes", label = "Root Prison", pattern = "ring", count = 8, ringRadius = 12, radius = 3.5, height = 10, damage = 5, windup = 1.05, cooldown = 7 },
				{ kind = "spikes", label = "Vine Rupture", pattern = "line", count = 7, spacing = 6.5, radius = 3.5, height = 9, damage = 6, windup = 1.0, cooldown = 8.5 },
			},
		},
		{
			key = "ironweedKing", name = "The Ironweed King", zone = "Ironweed", visual = "ironking",
			hp = 60000, damage = 18, moveSpeed = 7, attackRange = 10, attackCooldown = 1.2,
			aggroRange = 108, resetDelay = 12, scale = 2.85, globalAbilityCooldown = 1.9,
			bodyColor = { 68, 76, 82 }, headColor = { 104, 132, 138 }, accentColor = { 144, 210, 218 },
			goldReward = 60000, diamondReward = 75, essenceKey = "IronFilament", essenceReward = 300,
			abilities = {
				{ kind = "spikes", label = "Royal Ironline", pattern = "line", count = 8, spacing = 7, radius = 3.8, height = 11, damage = 8, windup = 0.95, cooldown = 7 },
				{ kind = "slam", label = "King's Decree", radius = 15, height = 5, damage = 12, windup = 1.15, cooldown = 8.5 },
				{ kind = "armor", label = "Iron Dominion", reduction = 0.55, count = 4, windup = 0.65, duration = 5, cooldown = 12 },
			},
		},
	},

	-- Swords: a separate hotbar weapon ladder for combat. Each is bought with its
	-- configured gold/diamond/essence mix once the zone is reached, then SHARPENED
	-- up a per-sword damage ladder. The all-zone Kingsedge unlocks only after every
	-- configured ring boss has been defeated at least once.
	SWORDS = {
		{ key = "meadowCutlass", name = "Meadow Cutlass", zone = "Meadow", desc = "A light blade forged for Meadow pests.", goldCost = 250, diamondCost = 0, attackCooldown = 0.6, reach = 9, scale = 1.0, handleColor = { 108, 78, 46 }, bladeColor = { 180, 214, 150 }, levels = { { damage = 6, cost = 0 }, { damage = 9, cost = 400 }, { damage = 13, cost = 1200 }, { damage = 18, cost = 3000 } } },
		{ key = "blossomSaber", name = "Blossom Saber", zone = "Meadow", desc = "Heavier Meadow steel that bites deep.", goldCost = 1200, diamondCost = 0, attackCooldown = 0.7, reach = 10, scale = 1.12, handleColor = { 90, 60, 120 }, bladeColor = { 235, 150, 180 }, levels = { { damage = 14, cost = 0 }, { damage = 20, cost = 1500 }, { damage = 28, cost = 4000 }, { damage = 40, cost = 9000 } } },
		{ key = "bramblefangBlade", name = "Bramblefang Blade", zone = "Wild", desc = "A hooked Wildfields blade paid for partly in Wild Burr.", goldCost = 3000, diamondCost = 0, essenceKey = "WildBurr", essenceCost = 5, attackCooldown = 0.55, reach = 10, scale = 1.14, handleColor = { 88, 58, 36 }, bladeColor = { 126, 174, 94 }, levels = { { damage = 28, cost = 0 }, { damage = 38, cost = 4500 }, { damage = 52, cost = 9000 }, { damage = 70, cost = 18000 } } },
		{ key = "wildwoodCleaver", name = "Wildwood Cleaver", zone = "Wild", desc = "A heavy cleaver forged from Wild Burr and diamonds.", goldCost = 0, diamondCost = 6, essenceKey = "WildBurr", essenceCost = 12, attackCooldown = 0.6, reach = 10.5, scale = 1.24, handleColor = { 70, 50, 34 }, bladeColor = { 174, 194, 150 }, levels = { { damage = 45, cost = 0 }, { damage = 60, cost = 10000 }, { damage = 80, cost = 20000 }, { damage = 105, cost = 40000 } } },
		{ key = "bogpiercer", name = "Bogpiercer", zone = "Mossmire", desc = "A quick mire-forged blade that channels concentrated spores.", goldCost = 0, diamondCost = 0, essenceKey = "MireSpore", essenceCost = 45, attackCooldown = 0.5, reach = 11, scale = 1.18, handleColor = { 62, 74, 54 }, bladeColor = { 154, 126, 194 }, levels = { { damage = 180, cost = 0 }, { damage = 240, cost = 20000 }, { damage = 320, cost = 40000 }, { damage = 420, cost = 80000 } } },
		{ key = "mireblade", name = "Mireblade", zone = "Mossmire", desc = "A heavy Mossmire weapon forged from Mire Spore and diamonds.", goldCost = 0, diamondCost = 15, essenceKey = "MireSpore", essenceCost = 70, attackCooldown = 0.5, reach = 11.5, scale = 1.28, handleColor = { 46, 64, 50 }, bladeColor = { 112, 188, 162 }, levels = { { damage = 280, cost = 0 }, { damage = 370, cost = 40000 }, { damage = 490, cost = 80000 }, { damage = 650, cost = 160000 } } },
		{ key = "thornguardSword", name = "Thornguard Sword", zone = "Thicket", desc = "A guarded thorn-steel blade tempered with Thicket Sap.", goldCost = 0, diamondCost = 0, essenceKey = "ThicketSap", essenceCost = 90, attackCooldown = 0.55, reach = 12, scale = 1.24, handleColor = { 72, 50, 34 }, bladeColor = { 88, 166, 90 }, levels = { { damage = 420, cost = 0 }, { damage = 560, cost = 60000 }, { damage = 740, cost = 120000 }, { damage = 980, cost = 240000 } } },
		{ key = "bristlebane", name = "Bristlebane", zone = "Thicket", desc = "A brutal Thicket blade forged from sap and diamonds.", goldCost = 0, diamondCost = 25, essenceKey = "ThicketSap", essenceCost = 140, attackCooldown = 0.5, reach = 12.5, scale = 1.34, handleColor = { 58, 42, 30 }, bladeColor = { 142, 194, 112 }, levels = { { damage = 650, cost = 0 }, { damage = 860, cost = 120000 }, { damage = 1140, cost = 240000 }, { damage = 1500, cost = 480000 } } },
		{ key = "ironrender", name = "Ironrender", zone = "Ironweed", desc = "A dense filament-forged blade built for the final ring.", goldCost = 0, diamondCost = 0, essenceKey = "IronFilament", essenceCost = 160, attackCooldown = 0.5, reach = 13, scale = 1.32, handleColor = { 54, 62, 66 }, bladeColor = { 116, 178, 190 }, levels = { { damage = 1000, cost = 0 }, { damage = 1320, cost = 200000 }, { damage = 1740, cost = 400000 }, { damage = 2300, cost = 800000 } } },
		{ key = "weepthornGreatblade", name = "Weepthorn Greatblade", zone = "Ironweed", desc = "A massive endgame blade forged from Iron Filament and diamonds.", goldCost = 0, diamondCost = 45, essenceKey = "IronFilament", essenceCost = 240, attackCooldown = 0.55, reach = 14, scale = 1.48, handleColor = { 42, 48, 52 }, bladeColor = { 158, 210, 216 }, levels = { { damage = 1600, cost = 0 }, { damage = 2100, cost = 400000 }, { damage = 2800, cost = 800000 }, { damage = 3700, cost = 1600000 } } },
		{ key = "kingsedge", name = "Kingsedge", zone = "All", desc = "The all-ring blade. Every swing is a true-damage whirlwind.", goldCost = 0, diamondCost = 200, requiresAllBosses = true, requirementText = "Defeat all five ring bosses", special = "whirlwind", specialRadius = 18, attackCooldown = 0.5, reach = 16, scale = 1.62, handleColor = { 54, 82, 60 }, bladeColor = { 224, 246, 184 }, levels = { { damage = 2800, cost = 0 }, { damage = 3900, cost = 800000 }, { damage = 5300, cost = 1600000 }, { damage = 7000, cost = 3200000 } } },
	},
}

return GameConfig

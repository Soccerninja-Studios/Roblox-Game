--!strict
-- AutoMowerService: the automation layer. Players buy an auto-mower once (gold +
-- diamonds), then DEPLOY it to send a real little mower out into the field.
--
-- A deployed mower is not an idle gold faucet -- it actually works the map:
--
--   SEEKING  drive from wherever it stands to the nearest grass tile it is rated
--            to cut (its own zone and every easier one, same gating as tools)
--   CUTTING  swing at that tile on its own interval until the tile is felled,
--            banking the clippings into its OWN storage
--   HAULING  once storage is full, drive back to the Gardener and unload, which
--            pays the owning player gold -- then straight back to SEEKING
--
-- So mowers clear the field alongside the player instead of replacing them, and
-- the payout still flows through the Gardener the way manual deposits do.
--
-- Cutting itself lives in GrassService.MowerCut so mowers and players share the
-- exact same shrink/clear behaviour. All balance lives in GameConfig.AUTO_MOWERS.
-- Ownership + deployed state persist on the profile (profile.autoMowers); each
-- mower's live storage is session-only, which is fine because it unloads often.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MowerRig = require(ReplicatedStorage.Shared.MowerRig)

local AutoMowerService = {}

local PlayerDataService: any
local QuestService: any
local GrassService: any

local MOWERS: { any } = GameConfig.AUTO_MOWERS
local ANCHOR: Vector3 = GameConfig.AUTO_MOWER_DEPLOY_ANCHOR
local SLOT_SPACING: number = GameConfig.AUTO_MOWER_SLOT_SPACING or 7
local BRAIN_TICK: number = GameConfig.AUTO_MOWER_BRAIN_TICK or 0.25
local ARRIVE_DIST: number = GameConfig.AUTO_MOWER_ARRIVE_DIST or 4
local DEPOSIT_DIST: number = GameConfig.AUTO_MOWER_DEPOSIT_DIST or 8
local GARDENER: Vector3 = GameConfig.GARDENER_POSITION

-- key -> config, and key -> slot index (for a stable parking position).
local mowerByKey: { [string]: any } = {}
local slotIndex: { [string]: number } = {}
for i, def in ipairs(MOWERS) do
	mowerByKey[def.key] = def
	slotIndex[def.key] = i
end

-- One live mower.
type Runtime = {
	model: Model,
	body: BasePart,
	def: any,
	home: Vector3,
	state: string, -- "seeking" | "cutting" | "hauling" | "idle"
	storage: number,
	target: BasePart?,
	nextCutAt: number,
	zoneIndex: number,
	-- Height from the model's bottom up to its driver part's origin, so we can seat
	-- it on the ground instead of a stud above it.
	groundOffset: number,
	-- Yaw correction in degrees, for models that weren't built facing -Z.
	yaw: number,
}

-- Runtime, per-player state: player -> mower key -> Runtime
local live: { [Player]: { [string]: Runtime } } = {}

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function ensureState(profile: any)
	profile.autoMowers = profile.autoMowers or {}
	local s = profile.autoMowers
	s.owned = s.owned or {}
	s.deployed = s.deployed or {}
	return s
end

local function isZoneUnlocked(profile: any, zoneKey: string): boolean
	if zoneKey == "Meadow" then
		return true -- the first ring is always open
	end
	local q = profile.quests
	return q ~= nil and q.reached ~= nil and q.reached[zoneKey] == true
end

local function slotPosition(key: string): Vector3
	local i = slotIndex[key] or 1
	local mid = (#MOWERS + 1) / 2
	return ANCHOR + Vector3.new(0, 0, (i - mid) * SLOT_SPACING)
end

-- Floating label with the name + a live status readout. Shared by the real models
-- and the fallback box, so every mower reports what it is currently doing.
local function attachTag(body: BasePart, def: any)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MowerTag"
	gui.Size = UDim2.new(0, 160, 0, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Adornee = body
	gui.Parent = body

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.FredokaOne
	name.Text = def.name
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeColor3 = Color3.fromRGB(30, 46, 28)
	name.TextStrokeTransparency = 0.3
	name.TextScaled = true
	name.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 0, 0.55, 0)
	status.Size = UDim2.new(1, 0, 0.45, 0)
	status.Font = Enum.Font.GothamMedium
	status.Text = "Waking up"
	status.TextColor3 = Color3.fromRGB(226, 244, 210)
	status.TextStrokeColor3 = Color3.fromRGB(30, 46, 28)
	status.TextStrokeTransparency = 0.4
	status.TextScaled = true
	status.Parent = gui
end

-- Fallback mower, built from scratch. This is ONLY used when a mower's model is
-- missing from ReplicatedStorage.Assets -- a missing asset shouldn't stop
-- automation dead, it should just look plain and warn.
--
-- The body is anchored (we drive it by tween); the catcher and blade are
-- UNANCHORED and welded, so they ride along instead of being left behind.
local function buildFallbackModel(def: any, home: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "AutoMower_" .. def.key

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 1.4, 4)
	body.Color = color(def.bodyColor)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CFrame = CFrame.new(home)
	body.Parent = model
	model.PrimaryPart = body

	local function attach(part: BasePart, offset: CFrame)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.CFrame = body.CFrame * offset
		part.Parent = model
		local weld = Instance.new("Weld")
		weld.Part0 = body
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = body
	end

	-- Grass-catcher box on the back.
	local catcher = Instance.new("Part")
	catcher.Name = "Catcher"
	catcher.Size = Vector3.new(2.4, 1.6, 1.4)
	catcher.Color = color(def.bodyColor):Lerp(Color3.new(0, 0, 0), 0.25)
	attach(catcher, CFrame.new(0, 0.1, 2.4))

	-- Cutting deck out front, so you can see which end does the work.
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(3.2, 0.3, 1.2)
	blade.Color = Color3.fromRGB(206, 210, 214)
	blade.Material = Enum.Material.Metal
	attach(blade, CFrame.new(0, -0.55, -2.2))

	attachTag(body, def)

	-- This one is built facing -Z already, and its blade hangs 0.7 studs below the
	-- body's origin, so that is how high off the ground the body needs to sit.
	model:SetAttribute("GroundOffset", 0.7)
	model:SetAttribute("DriveYaw", 0)
	body.CFrame = CFrame.new(home + Vector3.new(0, 0.7, 0))

	return model, body
end

-- Spawn a mower from its real model under ReplicatedStorage.Assets.
--
-- The imported models are toolbox freebies -- one is a scripted drivable vehicle,
-- one is a humanoid rig, one is ~200 loose parts around a seat -- so MowerRig
-- strips and rigidifies them into a single drivable assembly first. If the asset
-- is missing (not synced yet, or renamed) we warn with the exact name it looked
-- for and fall back to the box mower.
local function loadMowerModel(def: any, home: Vector3): (Model, BasePart)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = if assets and def.modelName then assets:FindFirstChild(def.modelName) else nil

	if template then
		local clone = template:Clone()
		local model: Model
		if clone:IsA("Model") then
			model = clone
		else
			-- Some assets export as a bare part; wrap it so we always have a Model.
			model = Instance.new("Model")
			clone.Parent = model
		end

		local driver = MowerRig.Prepare(model, def.modelLength)
		if driver then
			model.Name = "AutoMower_" .. def.key
			-- `home` is a GROUND position. Lift the driver by the model's own ground
			-- offset so the mower rests on the ground instead of floating above it.
			local offset = (model:GetAttribute("GroundOffset") :: number?) or 0
			model:PivotTo(CFrame.new(home + Vector3.new(0, offset, 0)))
			attachTag(driver, def)
			return model, driver
		end

		warn(string.format(
			"[AutoMowerService] Assets.%s had no parts after prep - using the fallback mower.",
			tostring(def.modelName)
		))
		model:Destroy()
	else
		warn(string.format(
			"[AutoMowerService] Assets.%s not found - using the fallback mower.",
			tostring(def.modelName)
		))
	end

	return buildFallbackModel(def, home)
end

local STATE_TEXT: { [string]: string } = {
	seeking = "Looking for grass",
	cutting = "Mowing",
	hauling = "Hauling to Gardener",
	idle = "Nothing to mow",
}

local function updateLabel(rt: Runtime)
	local status = rt.body:FindFirstChild("MowerTag")
	status = status and status:FindFirstChild("Status")
	if not status or not status:IsA("TextLabel") then
		return
	end
	local pct = math.clamp(math.floor((rt.storage / rt.def.storageCap) * 100), 0, 100)
	status.Text = string.format("%s  %d%%", STATE_TEXT[rt.state] or rt.state, pct)
end

-- Drive the mower toward a world position. Returns true once it has arrived.
local function driveToward(rt: Runtime, goal: Vector3, arriveDist: number): boolean
	local here = rt.body.Position
	local flatHere = Vector3.new(here.X, 0, here.Z)
	local flatGoal = Vector3.new(goal.X, 0, goal.Z)
	local delta = flatGoal - flatHere
	local dist = delta.Magnitude

	if dist <= arriveDist then
		return true
	end

	local dir = delta.Unit
	local stepDist = math.min(dist - arriveDist * 0.5, rt.def.moveSpeed * BRAIN_TICK)
	local nextPos = here + dir * stepDist
	-- Ease toward the goal's height so the mower rides up onto tiles smoothly.
	nextPos = Vector3.new(nextPos.X, here.Y + (goal.Y - here.Y) * 0.35, nextPos.Z)

	-- lookAt aims the part's -Z at the target; the yaw correction then swings the
	-- MODEL's own front to lead, instead of driving sideways.
	local goalCF = CFrame.lookAt(nextPos, nextPos + dir) * CFrame.Angles(0, math.rad(rt.yaw), 0)
	TweenService:Create(
		rt.body,
		TweenInfo.new(BRAIN_TICK, Enum.EasingStyle.Linear),
		{ CFrame = goalCF }
	):Play()

	return false
end

-- Where a mower should stand to cut a tile. BaseCFrame is the tile's ground plane,
-- so the mower's own ground offset is the only lift we add.
local function tileStandPosition(tile: BasePart, groundOffset: number): Vector3
	local baseCF = tile:GetAttribute("BaseCFrame") :: CFrame?
	local base = if baseCF then baseCF.Position else tile.Position
	return base + Vector3.new(0, groundOffset, 0)
end

local function targetIsValid(rt: Runtime): boolean
	local tile = rt.target
	if not tile or not tile.Parent then
		return false
	end
	return GrassService.IsCuttableTile(tile)
end

-- Unload a full mower at the Gardener: clippings become gold for the owner.
local function unload(player: Player, rt: Runtime)
	local banked = math.floor(rt.storage)
	rt.storage = 0
	if banked <= 0 then
		return
	end

	local gold = math.floor(banked * GameConfig.CLIPPING_TO_GOLD)
	PlayerDataService.GrantCurrency(player, gold, 0)
	Remotes.Get("AutoMowerBanked"):FireClient(player, {
		key = rt.def.key,
		name = rt.def.name,
		gold = gold,
		clippings = banked,
	})
	if QuestService then
		QuestService.Report(player, "automower_bank", gold, { mower = rt.def.name })
	end
end

-- One brain tick for one mower.
local function stepMower(player: Player, rt: Runtime)
	local def = rt.def

	-- Full? Haul it in, whatever else we were doing.
	if rt.state ~= "hauling" and rt.storage >= def.storageCap then
		rt.state = "hauling"
		rt.target = nil
	end

	if rt.state == "hauling" then
		if driveToward(rt, GARDENER + Vector3.new(0, rt.groundOffset, 0), DEPOSIT_DIST) then
			unload(player, rt)
			rt.state = "seeking"
		end

	elseif rt.state == "cutting" then
		if not targetIsValid(rt) then
			rt.target = nil
			rt.state = "seeking"
		elseif os.clock() >= rt.nextCutAt then
			rt.nextCutAt = os.clock() + def.cutInterval
			local tile = rt.target :: BasePart
			local cleared, reward = GrassService.MowerCut(player, tile, def.cutPower)
			if cleared then
				rt.storage = math.min(def.storageCap, rt.storage + reward)
				rt.target = nil
				rt.state = "seeking"
			elseif reward == 0 and not GrassService.IsCuttableTile(tile) then
				-- Could not dent it (shouldn't happen given zone gating) -- move on
				-- rather than sitting on it forever.
				rt.target = nil
				rt.state = "seeking"
			end
		end

	else -- "seeking" / "idle"
		if not targetIsValid(rt) then
			rt.target = GrassService.FindNearestCuttableTile(rt.body.Position, rt.zoneIndex)
		end

		local tile = rt.target
		if tile then
			rt.state = "seeking"
			if driveToward(rt, tileStandPosition(tile, rt.groundOffset), ARRIVE_DIST) then
				rt.state = "cutting"
				rt.nextCutAt = 0 -- swing immediately on arrival
			end
		else
			-- Nothing in range it is rated to cut. Park at its slot and wait; grass
			-- regrows / new districts open, and the next tick will look again.
			rt.state = "idle"
			driveToward(rt, rt.home, 2)
			if rt.storage > 0 then
				-- Don't sit on a part-full load forever with no work left.
				rt.state = "hauling"
			end
		end
	end

	updateLabel(rt)
end

local function despawn(player: Player, key: string)
	local perPlayer = live[player]
	if perPlayer and perPlayer[key] then
		perPlayer[key].model:Destroy()
		perPlayer[key] = nil
	end
end

local function spawnDeployed(player: Player, key: string)
	local def = mowerByKey[key]
	if not def then
		return
	end
	live[player] = live[player] or {}
	if live[player][key] then
		return -- already out
	end

	-- Ground-level parking spot; loadMowerModel seats the model on top of it.
	local home = slotPosition(key)
	local model, body = loadMowerModel(def, home)
	model.Parent = Workspace

	-- Measured seating, PLUS any deliberate lift from GameConfig. Some meshes hang
	-- below their own bounding box, so sitting them flush digs them into the dirt.
	local groundOffset = ((model:GetAttribute("GroundOffset") :: number?) or 0)
		+ (def.hoverOffset or 0)
	local autoYaw = (model:GetAttribute("DriveYaw") :: number?) or 0

	live[player][key] = {
		model = model,
		body = body,
		def = def,
		-- Stored as the DRIVER's parked position, ground offset included.
		home = home + Vector3.new(0, groundOffset, 0),
		state = "seeking",
		storage = 0,
		target = nil,
		nextCutAt = 0,
		zoneIndex = GrassService.GetGrassZoneIndex(def.zone),
		groundOffset = groundOffset,
		-- Measured correction, plus any manual nudge from GameConfig.
		yaw = autoYaw + (def.modelYaw or 0),
	}
end

-- Build the client-facing state snapshot.
local function buildState(player: Player): any
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local s = ensureState(profile)
	local perPlayer = live[player]
	local list = {}
	for _, def in ipairs(MOWERS) do
		local rt = perPlayer and perPlayer[def.key]
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			ratePerSec = def.ratePerSec,
			moveSpeed = def.moveSpeed,
			cutPower = def.cutPower,
			cutInterval = def.cutInterval,
			storageCap = def.storageCap,
			goldCost = def.goldCost,
			diamondCost = def.diamondCost,
			desc = def.desc,
			bodyColorR = def.bodyColor[1],
			bodyColorG = def.bodyColor[2],
			bodyColorB = def.bodyColor[3],
			owned = s.owned[def.key] == true,
			deployed = s.deployed[def.key] == true,
			unlocked = isZoneUnlocked(profile, def.zone),
			storage = if rt then rt.storage else 0,
			activity = if rt then rt.state else "parked",
		})
	end
	return { mowers = list, gold = profile.gold, diamonds = profile.diamonds }
end

local function pushState(player: Player)
	local state = buildState(player)
	if state then
		Remotes.Get("AutoMowerState"):FireClient(player, state)
	end
end

-- Re-create the visible mowers for everything the player has deployed.
local function respawnDeployed(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local s = ensureState(profile)
	for key in pairs(s.deployed) do
		if mowerByKey[key] then
			spawnDeployed(player, key)
		end
	end
end

-- Wait (briefly) for the player's profile to finish loading, then set them up.
local function onRequest(player: Player)
	local deadline = os.clock() + 10
	while not PlayerDataService.Get(player) and os.clock() < deadline do
		task.wait(0.25)
	end
	if not PlayerDataService.Get(player) then
		return
	end
	respawnDeployed(player)
	pushState(player)
end

local function onPurchase(player: Player, rawKey: unknown)
	if type(rawKey) ~= "string" then
		return
	end
	local def = mowerByKey[rawKey]
	if not def then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local s = ensureState(profile)
	if s.owned[def.key] then
		return -- already owned
	end
	if not isZoneUnlocked(profile, def.zone) then
		return -- haven't reached this mower's zone yet
	end
	if not PlayerDataService.SpendCurrency(player, def.goldCost, def.diamondCost) then
		return -- can't afford
	end
	s.owned[def.key] = true
	if QuestService then
		QuestService.ReportSpend(player, def.goldCost)
		QuestService.ReportPurchase(player)
	end
	PlayerDataService.PushState(player)
	pushState(player)
end

local function onToggle(player: Player, rawKey: unknown)
	if type(rawKey) ~= "string" then
		return
	end
	local def = mowerByKey[rawKey]
	if not def then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local s = ensureState(profile)
	if not s.owned[def.key] then
		return -- must own it first
	end
	if s.deployed[def.key] then
		-- Recall it. Any clippings still aboard are paid out rather than voided.
		local rt = live[player] and live[player][def.key]
		if rt then
			unload(player, rt)
		end
		s.deployed[def.key] = nil
		despawn(player, def.key)
	else
		-- Deploy it.
		s.deployed[def.key] = true
		spawnDeployed(player, def.key)
		if QuestService then
			QuestService.Report(player, "deploy_automower", 1, { mower = def.name })
		end
	end
	pushState(player)
end

local function onRemoving(player: Player)
	local perPlayer = live[player]
	if perPlayer then
		for _, rt in pairs(perPlayer) do
			rt.model:Destroy()
		end
	end
	live[player] = nil
end

function AutoMowerService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	GrassService = services.GrassService

	Remotes.Get("RequestAutoMowers").OnServerEvent:Connect(function(player)
		task.spawn(onRequest, player)
	end)
	Remotes.Get("PurchaseAutoMower").OnServerEvent:Connect(onPurchase)
	Remotes.Get("ToggleAutoMower").OnServerEvent:Connect(onToggle)
	Players.PlayerRemoving:Connect(onRemoving)
end

function AutoMowerService.Start()
	if not GrassService then
		warn("[AutoMowerService] GrassService missing - mowers cannot cut. Aborting loop.")
		return
	end

	-- Brain loop: every deployed mower gets one tick. Pushing state to the client
	-- is throttled to once a second so the HUD stays live without spamming the
	-- network at the brain tick rate.
	local lastPush = 0
	while true do
		task.wait(BRAIN_TICK)

		local now = os.clock()
		local shouldPush = (now - lastPush) >= 1
		if shouldPush then
			lastPush = now
		end

		for player, perPlayer in pairs(live) do
			if player.Parent == nil then
				onRemoving(player)
			else
				local profile = PlayerDataService.Get(player)
				if profile then
					local any = false
					for _, rt in pairs(perPlayer) do
						any = true
						local ok, err = pcall(stepMower, player, rt)
						if not ok then
							warn(string.format("[AutoMowerService] %s tick failed: %s", rt.def.key, tostring(err)))
						end
					end
					if any and shouldPush then
						pushState(player)
					end
				end
			end
		end
	end
end

return AutoMowerService

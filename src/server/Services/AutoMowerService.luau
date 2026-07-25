--!strict
-- AutoMowerService: the idle-income layer. Players buy an auto-mower once (gold +
-- diamonds), then DEPLOY it to send a little mower roaming the hub. While deployed
-- it passively generates clippings into its own storage; when that storage fills,
-- it AUTO-BANKS the clippings straight to gold -- no trip to the Gardener needed.
--
-- All balance lives in GameConfig.AUTO_MOWERS. Ownership + deployed state persist
-- on the player's profile (profile.autoMowers); each mower's live storage is kept
-- in memory for the session (it banks often, so nothing meaningful is lost on
-- rejoin). Deploy/auto-bank both report to the quest system via the generic
-- QuestService.Report, which already matches the deploy_automower / automower_bank
-- quests defined in QuestData.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AutoMowerService = {}

local PlayerDataService: any
local QuestService: any

local MOWERS: { any } = GameConfig.AUTO_MOWERS
local TICK: number = GameConfig.AUTO_MOWER_TICK or 1
local ANCHOR: Vector3 = GameConfig.AUTO_MOWER_DEPLOY_ANCHOR
local SLOT_SPACING: number = GameConfig.AUTO_MOWER_SLOT_SPACING or 7

-- key -> config, and key -> slot index (for a stable roam position).
local mowerByKey: { [string]: any } = {}
local slotIndex: { [string]: number } = {}
for i, def in ipairs(MOWERS) do
	mowerByKey[def.key] = def
	slotIndex[def.key] = i
end

-- Runtime, per-player state.
local models: { [Player]: { [string]: Model } } = {}
local storage: { [Player]: { [string]: number } } = {}

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

-- Build a small visible mower that roams a few studs around its slot.
local function buildMowerModel(def: any, home: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "AutoMower_" .. def.key

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 1.4, 4)
	body.Color = color(def.bodyColor)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = CFrame.new(home)
	body.Parent = model
	model.PrimaryPart = body

	local corner = Instance.new("SpecialMesh")
	corner.MeshType = Enum.MeshType.Brick
	corner.Parent = body

	-- A little grass-catcher box on the back.
	local catcher = Instance.new("Part")
	catcher.Name = "Catcher"
	catcher.Size = Vector3.new(2.4, 1.6, 1.4)
	catcher.Color = color(def.bodyColor):Lerp(Color3.new(0, 0, 0), 0.25)
	catcher.Material = Enum.Material.SmoothPlastic
	catcher.Anchored = true
	catcher.CanCollide = false
	catcher.Parent = model
	local catcherWeld = Instance.new("Weld")
	catcherWeld.Part0 = body
	catcherWeld.Part1 = catcher
	catcherWeld.C0 = CFrame.new(0, 0.1, 2.4)
	catcherWeld.Parent = body

	-- Floating label with the name + a live storage readout.
	local gui = Instance.new("BillboardGui")
	gui.Name = "MowerTag"
	gui.Size = UDim2.new(0, 150, 0, 44)
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
	status.Text = "0%"
	status.TextColor3 = Color3.fromRGB(226, 244, 210)
	status.TextStrokeColor3 = Color3.fromRGB(30, 46, 28)
	status.TextStrokeTransparency = 0.4
	status.TextScaled = true
	status.Parent = gui

	-- Gentle roam: drift around the home slot so the mower looks like it's working.
	task.spawn(function()
		local angle = 0
		while model.Parent do
			angle += math.rad(36)
			local target = CFrame.new(home + Vector3.new(math.cos(angle) * 4, math.sin(angle * 2) * 0.25, math.sin(angle) * 4))
				* CFrame.Angles(0, -angle + math.rad(90), 0)
			TweenService:Create(body, TweenInfo.new(TICK, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target }):Play()
			task.wait(TICK)
		end
	end)

	return model
end

local function despawn(player: Player, key: string)
	local perPlayer = models[player]
	if perPlayer and perPlayer[key] then
		perPlayer[key]:Destroy()
		perPlayer[key] = nil
	end
	if storage[player] then
		storage[player][key] = nil
	end
end

local function spawnDeployed(player: Player, key: string)
	local def = mowerByKey[key]
	if not def then
		return
	end
	models[player] = models[player] or {}
	storage[player] = storage[player] or {}
	if models[player][key] then
		return -- already out
	end
	local model = buildMowerModel(def, slotPosition(key))
	model.Parent = Workspace
	models[player][key] = model
	storage[player][key] = storage[player][key] or 0
end

local function updateLabel(player: Player, key: string)
	local perPlayer = models[player]
	local model = perPlayer and perPlayer[key]
	if not model then
		return
	end
	local def = mowerByKey[key]
	local cur = (storage[player] and storage[player][key]) or 0
	local pct = math.clamp(math.floor((cur / def.storageCap) * 100), 0, 100)
	local status = model:FindFirstChild("Status", true)
	if status and status:IsA("TextLabel") then
		status.Text = pct .. "%"
	end
end

-- Build the client-facing state snapshot.
local function buildState(player: Player): any
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local s = ensureState(profile)
	local list = {}
	for _, def in ipairs(MOWERS) do
		local cur = (storage[player] and storage[player][def.key]) or 0
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			ratePerSec = def.ratePerSec,
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
			storage = cur,
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
		-- Recall it.
		s.deployed[def.key] = nil
		despawn(player, def.key)
	else
		-- Deploy it.
		s.deployed[def.key] = true
		storage[player] = storage[player] or {}
		storage[player][def.key] = 0
		spawnDeployed(player, def.key)
		if QuestService then
			QuestService.Report(player, "deploy_automower", 1, { mower = def.name })
		end
	end
	pushState(player)
end

local function onRemoving(player: Player)
	local perPlayer = models[player]
	if perPlayer then
		for _, model in pairs(perPlayer) do
			model:Destroy()
		end
	end
	models[player] = nil
	storage[player] = nil
end

function AutoMowerService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService

	Remotes.Get("RequestAutoMowers").OnServerEvent:Connect(function(player)
		task.spawn(onRequest, player)
	end)
	Remotes.Get("PurchaseAutoMower").OnServerEvent:Connect(onPurchase)
	Remotes.Get("ToggleAutoMower").OnServerEvent:Connect(onToggle)
	Players.PlayerRemoving:Connect(onRemoving)
end

function AutoMowerService.Start()
	-- Idle-income loop: grow each deployed mower's storage and auto-bank when full.
	while true do
		task.wait(TICK)
		for player, perMower in pairs(storage) do
			local profile = PlayerDataService.Get(player)
			if profile then
				local s = ensureState(profile)
				local touched = false
				for key in pairs(s.deployed) do
					local def = mowerByKey[key]
					if def then
						touched = true
						local cur = (perMower[key] or 0) + def.ratePerSec * TICK
						if cur >= def.storageCap then
							local banked = math.floor(cur)
							local gold = math.floor(banked * GameConfig.CLIPPING_TO_GOLD)
							PlayerDataService.GrantCurrency(player, gold, 0)
							perMower[key] = 0
							Remotes.Get("AutoMowerBanked"):FireClient(player, { key = key, name = def.name, gold = gold })
							if QuestService then
								QuestService.Report(player, "automower_bank", gold, { mower = def.name })
							end
						else
							perMower[key] = cur
						end
						updateLabel(player, key)
					end
				end
				if touched then
					pushState(player)
				end
			end
		end
	end
end

return AutoMowerService

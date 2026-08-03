--!strict
-- BackpackService: the five per-zone backpacks -- buying them, upgrading them,
-- wearing them, and building the model that shows on the player's back.
--
-- One pack per zone, each gated behind having cut that zone's grass (the same
-- quests.reached check the auto-mowers use). A pack is bought once, then upgraded
-- along its OWN capacity ladder, and each pack can separately unlock auto-deposit.
-- Only the EQUIPPED pack decides carry capacity, so a later pack is a straight
-- upgrade rather than a side-grade.
--
-- This replaces the old single "bag" upgrade. Capacity is still answered by
-- PlayerDataService.GetBagCapacity, which now reads the equipped pack, so every
-- existing caller (ClippingsService, the HUD, the Gardener) keeps working untouched.
--
-- All balance lives in GameConfig.BACKPACKS. Ownership, level, auto-deposit and the
-- equipped key persist on the profile (profile.backpacks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BackpackService = {}

local PlayerDataService: any
local QuestService: any
local CutsceneService: any

local PACKS: { any } = GameConfig.BACKPACKS
local AUTO_TICK: number = GameConfig.BACKPACK_AUTO_DEPOSIT_TICK or 0.5

local packByKey: { [string]: any } = {}
for _, def in ipairs(PACKS) do
	packByKey[def.key] = def
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Same gate the auto-mowers use: the first zone is always open, everything else
-- needs the player to have actually cut that grass at least once.
local function isZoneUnlocked(profile: any, zoneKey: string): boolean
	if zoneKey == "Meadow" then
		return true
	end
	return profile.quests.reached[zoneKey] == true
end

-- ---------------------------------------------------------------------------
-- The model on the player's back
-- ---------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true -- never let the pack drag the character's physics around
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Each shape is a handful of primitives laid out relative to the pack body, so the
-- whole thing can be welded up as one piece. +Z points away from the player's back.
local function buildPack(def: any): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "ZoneBackpack"

	local body = rgb(def.color)
	local trim = rgb(def.accent)
	local shape = def.shape
	local main: BasePart

	if shape == "basket" then
		-- Shallow woven basket with a pale rim.
		main = part(model, "Body", Vector3.new(1.5, 1.4, 0.7), body, Enum.Material.Fabric)
		local rim = part(model, "Accent", Vector3.new(1.62, 0.18, 0.82), trim, Enum.Material.Fabric)
		rim.CFrame = main.CFrame * CFrame.new(0, 0.72, 0)
	elseif shape == "satchel" then
		-- Canvas box with a fold-over flap and a small buckle.
		main = part(model, "Body", Vector3.new(1.7, 1.5, 0.85), body, Enum.Material.Fabric)
		local flap = part(model, "Accent", Vector3.new(1.78, 0.7, 0.95), trim, Enum.Material.Fabric)
		flap.CFrame = main.CFrame * CFrame.new(0, 0.5, 0.02)
		local buckle = part(model, "Buckle", Vector3.new(0.28, 0.28, 0.12), Color3.fromRGB(226, 200, 120), Enum.Material.Metal)
		buckle.CFrame = main.CFrame * CFrame.new(0, 0.05, 0.5)
	elseif shape == "rucksack" then
		-- Tall sealed sack with a pouch on each side.
		main = part(model, "Body", Vector3.new(1.6, 1.9, 0.95), body, Enum.Material.Fabric)
		for i, side in ipairs({ -1, 1 }) do
			local pouch = part(model, "Pouch" .. i, Vector3.new(0.4, 0.7, 0.6), trim, Enum.Material.Fabric)
			pouch.CFrame = main.CFrame * CFrame.new(side * 0.95, -0.35, 0)
		end
		local strap = part(model, "Accent", Vector3.new(1.7, 0.16, 1.02), trim, Enum.Material.Fabric)
		strap.CFrame = main.CFrame * CFrame.new(0, 0.35, 0)
	elseif shape == "frame" then
		-- Hide slung on a hardwood carrying frame that pokes out top and bottom.
		main = part(model, "Body", Vector3.new(1.75, 2.05, 1.0), body, Enum.Material.Fabric)
		for i, side in ipairs({ -1, 1 }) do
			local rail = part(model, "Rail" .. i, Vector3.new(0.18, 2.6, 0.18), trim, Enum.Material.Wood)
			rail.CFrame = main.CFrame * CFrame.new(side * 0.82, 0.1, 0.1)
		end
		local crossbar = part(model, "Accent", Vector3.new(1.8, 0.18, 0.18), trim, Enum.Material.Wood)
		crossbar.CFrame = main.CFrame * CFrame.new(0, 1.2, 0.1)
	else
		-- "hauler": a hard shell around a glowing containment core.
		main = part(model, "Body", Vector3.new(1.85, 2.1, 1.1), body, Enum.Material.Metal)
		local core = part(model, "Accent", Vector3.new(0.75, 0.75, 0.3), trim, Enum.Material.Neon)
		core.CFrame = main.CFrame * CFrame.new(0, 0.25, 0.55)
		for i, side in ipairs({ -1, 1 }) do
			local vent = part(model, "Vent" .. i, Vector3.new(0.22, 1.3, 0.5), trim, Enum.Material.Neon)
			vent.CFrame = main.CFrame * CFrame.new(side * 1.0, -0.15, 0)
		end
	end

	model.PrimaryPart = main

	-- Shoulder straps, on every pack, so it reads as worn rather than stuck on.
	for i, side in ipairs({ -1, 1 }) do
		local strap = part(model, "Strap" .. i, Vector3.new(0.22, 1.5, 0.28), trim, Enum.Material.Fabric)
		strap.CFrame = main.CFrame * CFrame.new(side * 0.45, 0.1, -0.55)
	end

	return model, main
end

-- Weld every piece to the body, then the body to the torso. Only WeldConstraints
-- are used, so nothing is anchored and the pack rides the character normally.
local function attachPack(player: Player, def: any?)
	local character = player.Character
	if not character then
		return
	end

	local existing = character:FindFirstChild("ZoneBackpack")
	if existing then
		existing:Destroy()
	end
	if not def then
		return
	end

	-- R6 calls it Torso, R15 calls it UpperTorso. Falling back to the root part means
	-- a rig we do not recognise still gets a pack rather than nothing.
	local torso = character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return
	end

	local model, body = buildPack(def)

	-- Sit the pack just off the back. Characters face -Z, so +Z is behind them. Move
	-- the whole rig as one so the pieces keep their layout relative to the body.
	local target = torso.CFrame * CFrame.new(0, 0.15, torso.Size.Z * 0.5 + 0.42)
	local shift = target * body.CFrame:Inverse()
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst ~= body then
			inst.CFrame = shift * inst.CFrame
		end
	end
	body.CFrame = target

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = inst
			weld.Parent = body
		end
	end

	local hold = Instance.new("WeldConstraint")
	hold.Name = "PackWeld"
	hold.Part0 = torso
	hold.Part1 = body
	hold.Parent = body

	model.Parent = character
end

-- Re-dress the player in whatever pack their profile says is equipped. During the
-- intro cutscene we keep the back bare (and strip any existing pack) so it isn't
-- visible on the player's back mid-scene -- the pack goes on when the intro ends,
-- exactly like tools do.
local function refreshPack(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	if CutsceneService and CutsceneService.IsIntroPending(player) then
		attachPack(player, nil) -- removes any existing ZoneBackpack, adds nothing
		return
	end
	local def = PlayerDataService.GetEquippedBackpack(profile)
	attachPack(player, def)
end

-- Public: let CutsceneService dress the player the moment the intro finishes.
function BackpackService.RefreshPack(player: Player)
	refreshPack(player)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local function buildState(player: Player): any?
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local b = profile.backpacks
	local list = {}
	for _, def in ipairs(PACKS) do
		local level = math.clamp(b.level[def.key] or 1, 1, #def.levels)
		local nextDef = def.levels[level + 1]
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			desc = def.desc,
			goldCost = def.goldCost,
			diamondCost = def.diamondCost,
			colorR = def.color[1],
			colorG = def.color[2],
			colorB = def.color[3],
			owned = b.owned[def.key] == true,
			unlocked = isZoneUnlocked(profile, def.zone),
			equipped = b.equipped == def.key,
			level = level,
			maxLevel = #def.levels,
			capacity = def.levels[level].capacity,
			nextCapacity = if nextDef then nextDef.capacity else nil,
			nextCost = if nextDef then nextDef.cost else nil,
			autoDeposit = b.autoDeposit[def.key] == true,
			autoDepositCost = def.autoDepositCost,
			autoDepositDiamondCost = def.autoDepositDiamondCost,
		})
	end
	return { packs = list, gold = profile.gold, diamonds = profile.diamonds }
end

local function pushState(player: Player)
	local state = buildState(player)
	if state then
		Remotes.Get("BackpackState"):FireClient(player, state)
	end
end

-- Two panels need refreshing after any purchase: the pack list for its own cards,
-- and the main state for the HUD's capacity meter.
local function pushBoth(player: Player)
	PlayerDataService.PushState(player)
	pushState(player)
end

local function onRequest(player: Player)
	local deadline = os.clock() + 10
	while not PlayerDataService.Get(player) and os.clock() < deadline do
		task.wait(0.25)
	end
	if not PlayerDataService.Get(player) then
		return
	end
	pushState(player)
end

-- ---------------------------------------------------------------------------
-- Purchases
-- ---------------------------------------------------------------------------

local function onPurchase(player: Player, rawKey: unknown)
	if typeof(rawKey) ~= "string" then
		return
	end
	local def = packByKey[rawKey :: string]
	local profile = PlayerDataService.Get(player)
	if not def or not profile then
		return
	end
	local b = profile.backpacks
	if b.owned[def.key] then
		return -- already bought; never charge twice
	end
	if not isZoneUnlocked(profile, def.zone) then
		return -- has not reached that zone yet
	end
	if not PlayerDataService.SpendCurrency(player, def.goldCost, def.diamondCost) then
		return
	end

	b.owned[def.key] = true
	b.level[def.key] = b.level[def.key] or 1
	b.equipped = def.key -- a new pack is always bigger, so wear it straight away
	refreshPack(player)

	if QuestService and QuestService.ReportPurchase then
		QuestService.ReportPurchase(player, 1)
	end
	pushBoth(player)
end

-- Buys either the next capacity level, or the pack's one-off auto-deposit unlock.
local function onUpgrade(player: Player, rawKey: unknown, rawKind: unknown)
	if typeof(rawKey) ~= "string" then
		return
	end
	local def = packByKey[rawKey :: string]
	local profile = PlayerDataService.Get(player)
	if not def or not profile then
		return
	end
	local b = profile.backpacks
	if not b.owned[def.key] then
		return -- cannot upgrade a pack you do not own
	end

	if rawKind == "autoDeposit" then
		if b.autoDeposit[def.key] then
			return
		end
		if not PlayerDataService.SpendCurrency(player, def.autoDepositCost, def.autoDepositDiamondCost) then
			return
		end
		b.autoDeposit[def.key] = true
	else
		local level = math.clamp(b.level[def.key] or 1, 1, #def.levels)
		local nextDef = def.levels[level + 1]
		if not nextDef then
			return -- already at the top of this pack's ladder
		end
		if not PlayerDataService.SpendGold(player, nextDef.cost) then
			return
		end
		b.level[def.key] = level + 1
	end

	if QuestService and QuestService.ReportPurchase then
		QuestService.ReportPurchase(player, 1)
	end
	pushBoth(player)
end

local function onEquip(player: Player, rawKey: unknown)
	if typeof(rawKey) ~= "string" then
		return
	end
	local def = packByKey[rawKey :: string]
	local profile = PlayerDataService.Get(player)
	if not def or not profile then
		return
	end
	if not profile.backpacks.owned[def.key] then
		return
	end
	profile.backpacks.equipped = def.key
	refreshPack(player)
	pushBoth(player)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		-- The profile may still be loading on a cold join, and the character needs a
		-- moment to settle before a weld sticks, so wait for both.
		task.spawn(function()
			local deadline = os.clock() + 10
			while not PlayerDataService.Get(player) and os.clock() < deadline do
				task.wait(0.25)
			end
			task.wait(0.35)
			refreshPack(player)
		end)
	end)
	if player.Character then
		refreshPack(player)
	end
end

function BackpackService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	CutsceneService = services.CutsceneService

	Remotes.Get("RequestBackpacks").OnServerEvent:Connect(onRequest)
	Remotes.Get("PurchaseBackpack").OnServerEvent:Connect(onPurchase)
	Remotes.Get("UpgradeBackpack").OnServerEvent:Connect(onUpgrade)
	Remotes.Get("EquipBackpack").OnServerEvent:Connect(onEquip)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

function BackpackService.Start()
	-- Auto-deposit: a pack that bought the upgrade banks a full bag by itself, from
	-- anywhere. Polling is deliberate -- clippings arrive by several paths (manual
	-- cuts, pickups, mowers) and one cheap check here beats hooking all of them.
	while true do
		task.wait(AUTO_TICK)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = PlayerDataService.Get(player)
			if profile and profile.clippings > 0 and PlayerDataService.HasAutoDeposit(profile) then
				if PlayerDataService.IsBagFull(player) then
					local summary = PlayerDataService.Deposit(player)
					if summary.clippings > 0 then
						-- The same remote the Gardener fires, so the client shows the
						-- usual coins flying up to the counters.
						Remotes.Get("Deposited"):FireClient(player, summary)
						if QuestService and QuestService.ReportDeposit then
							QuestService.ReportDeposit(player, summary.gold, summary.diamonds)
						end
						pushState(player)
					end
				end
			end
		end
	end
end

return BackpackService

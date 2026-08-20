--!strict
-- PetService: complete server-authoritative foundation for all fifteen pets.
-- Owns recruitment, the three-slot loadout, essence feeding/levels, quest reports,
-- live stat refreshes, and replicated procedural companion models.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PetService = {}

local PlayerDataService: any
local QuestService: any
local MonsterService: any

local petFolder: Folder
local defByKey: { [string]: any } = {}
local activeModels: { [Player]: { any } } = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local SLOT_OFFSETS = {
	Vector3.new(-2.35, 0, 2.35),
	Vector3.new(2.35, 0, 2.35),
	Vector3.new(0, 0, 3.25),
}

local STAT_LABELS = {
	bagCapacity = "Bag capacity",
	clippingValue = "Clipping value",
	cutPower = "Cut power",
	swordDamage = "Sword damage",
	attackSpeed = "Attack speed",
	maxHealth = "Max health",
}

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function ensurePets(profile: any): any
	profile.pets = profile.pets or { owned = {}, equipped = {} }
	profile.pets.owned = profile.pets.owned or {}
	profile.pets.equipped = profile.pets.equipped or {}
	return profile.pets
end

local function petDef(key: unknown): any?
	return if type(key) == "string" then defByKey[key] else nil
end

local function hasReachedZone(profile: any, zone: string): boolean
	if zone == "Meadow" then
		return true
	end
	local reached = profile.quests and profile.quests.reached
	return reached ~= nil and reached[zone] == true
end

local function feedNeeded(level: number): number
	local cfg = GameConfig.PET_SYSTEM
	return (cfg.feedBase or 8) + math.max(0, level - 1) * (cfg.feedGrowth or 4)
end

local function scaledBonuses(def: any, data: any): { [string]: number }
	local result: { [string]: number } = {}
	local cfg = GameConfig.PET_SYSTEM
	local levelScale = 1 + math.max(0, (data.level or 1) - 1) * (cfg.levelBonusGrowth or 0.04)
	local goldenScale = if data.golden then (cfg.goldenBonusMultiplier or 1.5) else 1
	local rankScale = 1 + math.max(0, (data.rank or 1) - 1) * (cfg.rankBonusGrowth or 0.15)
	for stat, value in def.bonuses or {} do
		result[stat] = value * levelScale * goldenScale * rankScale
	end
	return result
end

local function cleanLoadout(profile: any)
	local pets = ensurePets(profile)
	local maxEquipped = GameConfig.PET_SYSTEM.maxEquipped or 3
	local cleaned = {}
	local seen: { [string]: boolean } = {}
	for _, key in ipairs(pets.equipped) do
		if #cleaned >= maxEquipped then
			break
		end
		if type(key) == "string" and not seen[key] and pets.owned[key] and defByKey[key] then
			seen[key] = true
			table.insert(cleaned, key)
		end
	end
	pets.equipped = cleaned
	local maxLevel = GameConfig.PET_SYSTEM.maxLevel or 25
	for key, data in pets.owned do
		if not defByKey[key] then
			continue
		end
		data.level = math.clamp(math.floor(tonumber(data.level) or 1), 1, maxLevel)
		data.xp = math.max(0, math.floor(tonumber(data.xp) or 0))
		data.golden = data.golden == true
		data.shards = math.max(0, math.floor(tonumber(data.shards) or 0))
		data.rank = math.clamp(math.floor(tonumber(data.rank) or 1), 1, GameConfig.PET_SYSTEM.maxRank or 5)
		if data.level >= maxLevel then
			data.xp = 0
		else
			data.xp = math.min(data.xp, feedNeeded(data.level) - 1)
		end
	end
end

local function equippedIndex(pets: any, key: string): number?
	for index, equippedKey in ipairs(pets.equipped) do
		if equippedKey == key then
			return index
		end
	end
	return nil
end

local function buildState(player: Player, message: string?): any
	local profile = PlayerDataService.Get(player)
	if not profile then
		return { pets = {}, loading = true, message = message }
	end
	cleanLoadout(profile)
	local pets = ensurePets(profile)
	local list = {}
	local maxLevel = GameConfig.PET_SYSTEM.maxLevel or 25
	for _, def in ipairs(GameConfig.PETS or {}) do
		local data = pets.owned[def.key]
		local level = if data then data.level else 1
		local body = def.bodyColor
		local accent = def.accentColor
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			rarity = def.rarity,
			owned = data ~= nil,
			equipped = equippedIndex(pets, def.key) ~= nil,
			equippedSlot = equippedIndex(pets, def.key),
			unlocked = hasReachedZone(profile, def.zone),
			level = level,
			maxLevel = maxLevel,
			xp = if data then data.xp else 0,
			nextFeed = if data and level < maxLevel then feedNeeded(level) else nil,
			golden = data and data.golden == true or false,
			shards = if data then data.shards or 0 else 0,
			rank = if data then data.rank or 1 else 1,
			maxRank = GameConfig.PET_SYSTEM.maxRank or 5,
			nextRankCost = if data and (data.rank or 1) < (GameConfig.PET_SYSTEM.maxRank or 5) then GameConfig.PET_SYSTEM.rankCosts[data.rank or 1] else nil,
			goldCost = def.goldCost or 0,
			diamondCost = def.diamondCost or 0,
			essenceKey = def.essenceKey,
			essenceName = if def.essenceKey and GameConfig.ESSENCE[def.essenceKey] then GameConfig.ESSENCE[def.essenceKey].name else "Essence",
			essenceCost = def.essenceCost or 0,
			bonuses = if data then scaledBonuses(def, data) else scaledBonuses(def, { level = 1, golden = false }),
			bodyR = body[1], bodyG = body[2], bodyB = body[3],
			accentR = accent[1], accentG = accent[2], accentB = accent[3],
		})
	end
	return {
		pets = list,
		gold = profile.gold,
		diamonds = profile.diamonds,
		essence = table.clone(profile.essence or {}),
		equippedCount = #pets.equipped,
		maxEquipped = GameConfig.PET_SYSTEM.maxEquipped or 3,
		aggregateBonuses = PlayerDataService.GetPetBonuses(profile),
		statLabels = STAT_LABELS,
		message = message,
	}
end

function PetService.PushState(player: Player, message: string?)
	Remotes.Get("PetState"):FireClient(player, buildState(player, message))
end

local function modelPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function addWing(model: Model, side: number, color: Color3, y: number)
	modelPart(
		model,
		"Wing",
		Vector3.new(0.18, 0.9, 1.05),
		color,
		CFrame.new(side * 0.8, y, 0.15) * CFrame.Angles(0, 0, math.rad(side * -24)),
		Enum.PartType.Ball
	)
end

local function buildPetModel(player: Player, def: any, data: any, slot: number): Model
	local model = Instance.new("Model")
	model.Name = player.Name .. "_" .. def.key
	model:SetAttribute("PetOwnerUserId", player.UserId)
	model:SetAttribute("PetKey", def.key)
	model:SetAttribute("PetSlot", slot)
	model:SetAttribute("PetLevel", data.level)
	model:SetAttribute("PetRank", data.rank or 1)
	model:SetAttribute("Golden", data.golden == true)

	local bodyColor = c3(def.bodyColor)
	local accentColor = c3(def.accentColor)
	if data.golden then
		bodyColor = Color3.fromRGB(246, 205, 80)
		accentColor = Color3.fromRGB(255, 242, 160)
	end
	local dark = bodyColor:Lerp(Color3.new(0, 0, 0), 0.38)
	local light = bodyColor:Lerp(Color3.new(1, 1, 1), 0.42)
	local body = modelPart(model, "Body", Vector3.new(1.55, 1.25, 1.8), bodyColor, CFrame.new(0, 0, 0.1), Enum.PartType.Ball)
	model.PrimaryPart = body
	modelPart(model, "Head", Vector3.new(1.18, 1.08, 1.08), light, CFrame.new(0, 0.38, -0.92), Enum.PartType.Ball)
	modelPart(model, "Eye", Vector3.new(0.15, 0.18, 0.12), Color3.fromRGB(24, 28, 26), CFrame.new(-0.25, 0.52, -1.43), Enum.PartType.Ball)
	modelPart(model, "Eye", Vector3.new(0.15, 0.18, 0.12), Color3.fromRGB(24, 28, 26), CFrame.new(0.25, 0.52, -1.43), Enum.PartType.Ball)

	local visual = def.visual
	if visual == "bunny" then
		modelPart(model, "Ear", Vector3.new(0.3, 0.95, 0.3), accentColor, CFrame.new(-0.28, 1.15, -0.92), Enum.PartType.Ball)
		modelPart(model, "Ear", Vector3.new(0.3, 0.95, 0.3), accentColor, CFrame.new(0.28, 1.15, -0.92), Enum.PartType.Ball)
		modelPart(model, "Tail", Vector3.new(0.48, 0.48, 0.48), light, CFrame.new(0, 0.15, 1.05), Enum.PartType.Ball)
	elseif visual == "bee" then
		addWing(model, -1, Color3.fromRGB(220, 240, 242), 0.25)
		addWing(model, 1, Color3.fromRGB(220, 240, 242), 0.25)
		modelPart(model, "Stripe", Vector3.new(1.58, 0.28, 0.26), dark, CFrame.new(0, 0, 0.35), Enum.PartType.Ball)
		modelPart(model, "Stinger", Vector3.new(0.22, 0.22, 0.52), dark, CFrame.new(0, 0, 1.13), Enum.PartType.Ball)
	elseif visual == "lamb" then
		for x = -1, 1, 2 do
			modelPart(model, "Ear", Vector3.new(0.42, 0.22, 0.55), accentColor, CFrame.new(x * 0.62, 0.55, -0.91) * CFrame.Angles(0, 0, math.rad(x * 15)), Enum.PartType.Ball)
		end
		for i = 1, 5 do
			local angle = (i / 5) * math.pi * 2
			modelPart(model, "Wool", Vector3.new(0.55, 0.55, 0.55), light, CFrame.new(math.cos(angle) * 0.55, 0.5, math.sin(angle) * 0.45), Enum.PartType.Ball)
		end
	elseif visual == "fox" then
		for x = -1, 1, 2 do
			modelPart(model, "Ear", Vector3.new(0.42, 0.7, 0.32), dark, CFrame.new(x * 0.38, 1.02, -0.92) * CFrame.Angles(0, 0, math.rad(x * 18)), Enum.PartType.Ball)
		end
		modelPart(model, "Tail", Vector3.new(0.5, 0.55, 1.35), bodyColor, CFrame.new(0.58, 0.15, 1.0) * CFrame.Angles(math.rad(30), 0, math.rad(-28)), Enum.PartType.Ball)
	elseif visual == "bird" then
		addWing(model, -1, accentColor, 0.15)
		addWing(model, 1, accentColor, 0.15)
		modelPart(model, "Beak", Vector3.new(0.32, 0.25, 0.42), Color3.fromRGB(236, 170, 72), CFrame.new(0, 0.34, -1.5), Enum.PartType.Ball)
	elseif visual == "hedgehog" then
		for i = 1, 7 do
			local angle = ((i - 1) / 7) * math.pi * 2
			modelPart(model, "Quill", Vector3.new(0.18, 0.7, 0.18), dark, CFrame.new(math.cos(angle) * 0.72, 0.5, math.sin(angle) * 0.62) * CFrame.Angles(0, 0, angle), Enum.PartType.Ball)
		end
	elseif visual == "frog" then
		for x = -1, 1, 2 do
			modelPart(model, "EyeBump", Vector3.new(0.44, 0.44, 0.44), accentColor, CFrame.new(x * 0.38, 0.88, -1.0), Enum.PartType.Ball)
		end
		modelPart(model, "Mouth", Vector3.new(0.55, 0.08, 0.08), dark, CFrame.new(0, 0.22, -1.48), Enum.PartType.Block)
	elseif visual == "firefly" then
		addWing(model, -1, Color3.fromRGB(196, 230, 224), 0.25)
		addWing(model, 1, Color3.fromRGB(196, 230, 224), 0.25)
		local glow = modelPart(model, "Glow", Vector3.new(0.8, 0.8, 0.8), accentColor, CFrame.new(0, 0.05, 0.95), Enum.PartType.Ball)
		glow.Material = Enum.Material.Neon
	elseif visual == "newt" then
		modelPart(model, "Tail", Vector3.new(0.42, 0.35, 1.55), accentColor, CFrame.new(0, -0.05, 1.15) * CFrame.Angles(0, math.rad(18), 0), Enum.PartType.Ball)
		for x = -1, 1, 2 do
			modelPart(model, "Gill", Vector3.new(0.12, 0.5, 0.4), accentColor, CFrame.new(x * 0.6, 0.5, -0.95), Enum.PartType.Ball)
		end
	elseif visual == "badger" then
		modelPart(model, "Stripe", Vector3.new(0.28, 1.0, 1.1), accentColor, CFrame.new(0, 0.45, -0.96), Enum.PartType.Ball)
		for x = -1, 1, 2 do
			modelPart(model, "Ear", Vector3.new(0.34, 0.34, 0.26), dark, CFrame.new(x * 0.43, 0.92, -0.92), Enum.PartType.Ball)
		end
	elseif visual == "owl" then
		addWing(model, -1, dark, 0.1)
		addWing(model, 1, dark, 0.1)
		for x = -1, 1, 2 do
			modelPart(model, "EyeDisc", Vector3.new(0.48, 0.48, 0.16), accentColor, CFrame.new(x * 0.27, 0.52, -1.45), Enum.PartType.Ball)
		end
	elseif visual == "boar" then
		modelPart(model, "Snout", Vector3.new(0.7, 0.45, 0.42), accentColor, CFrame.new(0, 0.2, -1.48), Enum.PartType.Ball)
		for x = -1, 1, 2 do
			modelPart(model, "Tusk", Vector3.new(0.14, 0.38, 0.14), Color3.fromRGB(244, 232, 200), CFrame.new(x * 0.4, 0.08, -1.56) * CFrame.Angles(0, 0, math.rad(x * 25)), Enum.PartType.Ball)
		end
	elseif visual == "beetle" then
		local shell = modelPart(model, "Shell", Vector3.new(1.3, 0.85, 1.45), bodyColor, CFrame.new(0, 0.4, 0.2), Enum.PartType.Ball)
		shell.Material = Enum.Material.Metal
		modelPart(model, "ShellLine", Vector3.new(0.08, 0.6, 1.25), accentColor, CFrame.new(0, 0.78, 0.2), Enum.PartType.Block)
	elseif visual == "phoenix" then
		addWing(model, -1, accentColor, 0.2)
		addWing(model, 1, accentColor, 0.2)
		modelPart(model, "Crest", Vector3.new(0.24, 0.75, 0.24), accentColor, CFrame.new(0, 1.08, -0.9) * CFrame.Angles(math.rad(-20), 0, 0), Enum.PartType.Ball)
		for x = -1, 1, 2 do
			local flame = modelPart(model, "TailFlame", Vector3.new(0.28, 0.28, 1.2), accentColor, CFrame.new(x * 0.25, 0, 1.15) * CFrame.Angles(math.rad(-20), 0, 0), Enum.PartType.Ball)
			flame.Material = Enum.Material.Neon
		end
	elseif visual == "dragon" then
		addWing(model, -1, accentColor, 0.35)
		addWing(model, 1, accentColor, 0.35)
		modelPart(model, "Tail", Vector3.new(0.38, 0.38, 1.6), bodyColor, CFrame.new(0, 0, 1.2) * CFrame.Angles(0, math.rad(-18), 0), Enum.PartType.Ball)
		for x = -1, 1, 2 do
			modelPart(model, "Horn", Vector3.new(0.18, 0.62, 0.18), accentColor, CFrame.new(x * 0.34, 1.04, -0.91) * CFrame.Angles(0, 0, math.rad(x * 18)), Enum.PartType.Ball)
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Adornee = body
	billboard.Size = UDim2.fromOffset(150, 34)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = (data.golden and "Golden " or "") .. def.name .. "  Lv." .. tostring(data.level) .. "  R" .. tostring(data.rank or 1)
	label.TextColor3 = if data.golden then Color3.fromRGB(255, 226, 92) else Color3.fromRGB(246, 250, 238)
	label.TextStrokeColor3 = Color3.fromRGB(28, 42, 31)
	label.TextStrokeTransparency = 0.2
	label.TextSize = 13
	label.Parent = billboard

	model.Parent = petFolder
	model:PivotTo(CFrame.new(0, -500, 0))
	return model
end

local function clearVisuals(player: Player)
	local entries = activeModels[player]
	if entries then
		for _, entry in entries do
			if entry.model and entry.model.Parent then
				entry.model:Destroy()
			end
		end
	end
	activeModels[player] = nil
end

local function rebuildVisuals(player: Player)
	clearVisuals(player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	cleanLoadout(profile)
	local entries = {}
	for slot, key in ipairs(profile.pets.equipped) do
		local def = defByKey[key]
		local data = profile.pets.owned[key]
		if def and data then
			table.insert(entries, { model = buildPetModel(player, def, data, slot), def = def, slot = slot })
		end
	end
	activeModels[player] = entries
end

local function applyLiveStats(player: Player)
	if MonsterService and typeof(MonsterService.ApplyMaxHP) == "function" then
		MonsterService.ApplyMaxHP(player, true)
	end
end

local function allowAction(player: Player): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.12 then
		return false
	end
	lastAction[player] = now
	return true
end

local function finishAction(player: Player, message: string)
	cleanLoadout(PlayerDataService.Get(player))
	applyLiveStats(player)
	rebuildVisuals(player)
	PlayerDataService.PushState(player)
	PetService.PushState(player, message)
end

function PetService.RefreshPlayer(player: Player, message: string?)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	finishAction(player, message or "Pet collection updated.")
end

local function onRecruit(player: Player, rawKey: unknown)
	if not allowAction(player) then
		return
	end
	local def = petDef(rawKey)
	local profile = PlayerDataService.Get(player)
	if not def or not profile then
		return
	end
	local pets = ensurePets(profile)
	if pets.owned[def.key] then
		PetService.PushState(player, def.name .. " is already in your collection.")
		return
	end
	if not hasReachedZone(profile, def.zone) then
		PetService.PushState(player, "Reach " .. def.zone .. " before recruiting this pet.")
		return
	end
	if not PlayerDataService.SpendCurrency(player, def.goldCost or 0, def.diamondCost or 0, def.essenceKey, def.essenceCost or 0) then
		PetService.PushState(player, "You do not have enough currency for " .. def.name .. ".")
		return
	end
	pets.owned[def.key] = { level = 1, xp = 0, golden = false, shards = 0, rank = 1 }
	if #pets.equipped < (GameConfig.PET_SYSTEM.maxEquipped or 3) then
		table.insert(pets.equipped, def.key)
	end
	if QuestService then
		if typeof(QuestService.ReportSpend) == "function" then
			QuestService.ReportSpend(player, def.goldCost or 0)
		end
		if typeof(QuestService.ReportPurchase) == "function" then
			QuestService.ReportPurchase(player)
		end
		if typeof(QuestService.ReportPetRecruitment) == "function" then
			QuestService.ReportPetRecruitment(player, def.name)
		end
	end
	finishAction(player, "Recruited " .. def.name .. "!")
end

local function onEquip(player: Player, rawKey: unknown)
	if not allowAction(player) then
		return
	end
	local def = petDef(rawKey)
	local profile = PlayerDataService.Get(player)
	if not def or not profile then
		return
	end
	local pets = ensurePets(profile)
	if not pets.owned[def.key] then
		return
	end
	local index = equippedIndex(pets, def.key)
	local message: string
	if index then
		table.remove(pets.equipped, index)
		message = "Unequipped " .. def.name .. "."
	else
		if #pets.equipped >= (GameConfig.PET_SYSTEM.maxEquipped or 3) then
			PetService.PushState(player, "All three pet slots are occupied.")
			return
		end
		table.insert(pets.equipped, def.key)
		message = "Equipped " .. def.name .. "."
	end
	finishAction(player, message)
end

local function essenceToMax(data: any): number
	local maxLevel = GameConfig.PET_SYSTEM.maxLevel or 25
	if data.level >= maxLevel then
		return 0
	end
	local total = feedNeeded(data.level) - data.xp
	for level = data.level + 1, maxLevel - 1 do
		total += feedNeeded(level)
	end
	return total
end

local function onFeed(player: Player, rawKey: unknown, rawAmount: unknown)
	if not allowAction(player) then
		return
	end
	local def = petDef(rawKey)
	local profile = PlayerDataService.Get(player)
	local numericAmount = tonumber(rawAmount)
	if not def
		or not profile
		or not numericAmount
		or numericAmount ~= numericAmount
		or numericAmount == math.huge
		or numericAmount == -math.huge
		or numericAmount <= 0
	then
		return
	end
	local requested = math.clamp(math.floor(numericAmount), 1, 1000)
	local pets = ensurePets(profile)
	local data = pets.owned[def.key]
	if not data then
		return
	end
	local spendAmount = math.min(requested, essenceToMax(data))
	if spendAmount <= 0 then
		PetService.PushState(player, def.name .. " is already max level.")
		return
	end
	if not PlayerDataService.SpendCurrency(player, 0, 0, def.essenceKey, spendAmount) then
		PetService.PushState(player, "Not enough " .. GameConfig.ESSENCE[def.essenceKey].name .. ".")
		return
	end
	data.xp += spendAmount
	local oldLevel = data.level
	local maxLevel = GameConfig.PET_SYSTEM.maxLevel or 25
	while data.level < maxLevel do
		local needed = feedNeeded(data.level)
		if data.xp < needed then
			break
		end
		data.xp -= needed
		data.level += 1
	end
	if data.level >= maxLevel then
		data.xp = 0
	end
	local message = if data.level > oldLevel
		then def.name .. " reached level " .. tostring(data.level) .. "!"
		else "Fed " .. def.name .. " " .. tostring(spendAmount) .. " essence."
	finishAction(player, message)
end

local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.65)
		applyLiveStats(player)
		rebuildVisuals(player)
	end)
	task.spawn(function()
		local deadline = os.clock() + 20
		while player.Parent and not PlayerDataService.Get(player) and os.clock() < deadline do
			task.wait(0.2)
		end
		local profile = PlayerDataService.Get(player)
		if not profile then
			return
		end
		cleanLoadout(profile)
		if QuestService and typeof(QuestService.ReportPetRecruitment) == "function" then
			QuestService.ReportPetRecruitment(player, nil)
		end
		applyLiveStats(player)
		rebuildVisuals(player)
		PetService.PushState(player)
	end)
end

function PetService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	MonsterService = services.MonsterService
	for _, def in ipairs(GameConfig.PETS or {}) do
		defByKey[def.key] = def
	end
	local existing = Workspace:FindFirstChild("Pets")
	if existing and existing:IsA("Folder") then
		petFolder = existing
	else
		if existing then
			existing:Destroy()
		end
		petFolder = Instance.new("Folder")
		petFolder.Name = "Pets"
		petFolder.Parent = Workspace
	end
end

function PetService.Start()
	Remotes.Get("RequestPets").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < 0.25 then
			return
		end
		lastRequest[player] = now
		PetService.PushState(player)
	end)
	Remotes.Get("RecruitPet").OnServerEvent:Connect(onRecruit)
	Remotes.Get("EquipPet").OnServerEvent:Connect(onEquip)
	Remotes.Get("FeedPet").OnServerEvent:Connect(onFeed)

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		clearVisuals(player)
		lastAction[player] = nil
		lastRequest[player] = nil
	end)

	local followAccumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		followAccumulator += dt
		local interval = 1 / (GameConfig.PET_SYSTEM.followUpdateHz or 30)
		if followAccumulator < interval then
			return -- quicker, smaller follower corrections at a capped update rate
		end
		local step = math.min(followAccumulator, 0.1)
		followAccumulator = 0
		local responsiveness = GameConfig.PET_SYSTEM.followResponsiveness or 8
		local alpha = 1 - math.exp(-responsiveness * step)
		local now = os.clock()
		for player, entries in activeModels do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
				continue
			end
			for _, entry in entries do
				local model = entry.model
				if not model or not model.Parent then
					continue
				end
				local offset = SLOT_OFFSETS[entry.slot] or SLOT_OFFSETS[1]
				-- HumanoidRootPart sits roughly three studs above the floor. Ground pets
				-- stay near the player's feet; flying pets hover near waist height.
				local baseHeight = if entry.def.flying then 0.65 else -1.65
				local bob = math.sin(now * 3 + entry.slot * 1.7) * (if entry.def.flying then 0.35 else 0.12)
				local rootPart = root :: BasePart
				local prediction = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
					* (GameConfig.PET_SYSTEM.followPredictionSeconds or 0.08)
				local target = (rootPart.CFrame * CFrame.new(offset.X, baseHeight + bob, offset.Z)) + prediction
				local current = model:GetPivot()
				if (current.Position - target.Position).Magnitude > (GameConfig.PET_SYSTEM.followSnapDistance or 12) then
					model:PivotTo(target)
				else
					model:PivotTo(current:Lerp(target, alpha))
				end
			end
		end
	end)
	print("[PetService] fifteen-pet collection, loadout, feeding, stats, and followers ready.")
end

return PetService

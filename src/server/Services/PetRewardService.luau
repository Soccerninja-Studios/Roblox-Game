--!strict
-- PetRewardService: server-authoritative Golden Pet Wheel, pet-shard crate,
-- persisted pity counters, daily free spin, and shard-rank upgrades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PetRewardService = {}

local PlayerDataService: any
local PetService: any
local QuestService: any
local WheelWorldService: any
local rng = Random.new()

local defByKey: { [string]: any } = {}
local busyUntil: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local lastRankAction: { [Player]: number } = {}

local ZONE_ORDER = { "Meadow", "Wild", "Mossmire", "Thicket", "Ironweed" }

local function ensurePets(profile: any): any
	profile.pets = profile.pets or { owned = {}, equipped = {} }
	profile.pets.owned = profile.pets.owned or {}
	profile.pets.equipped = profile.pets.equipped or {}
	return profile.pets
end

local function ensureRewards(profile: any): any
	profile.petRewards = profile.petRewards or {}
	local rewards = profile.petRewards
	rewards.lastFreeSpin = math.max(0, tonumber(rewards.lastFreeSpin) or 0)
	rewards.wheelPity = math.max(0, math.floor(tonumber(rewards.wheelPity) or 0))
	rewards.cratePity = math.max(0, math.floor(tonumber(rewards.cratePity) or 0))
	rewards.totalSpins = math.max(0, math.floor(tonumber(rewards.totalSpins) or 0))
	rewards.totalCrates = math.max(0, math.floor(tonumber(rewards.totalCrates) or 0))
	return rewards
end

local function hasReached(profile: any, zone: string): boolean
	if zone == "Meadow" then
		return true
	end
	return profile.quests and profile.quests.reached and profile.quests.reached[zone] == true
end

local function highestRing(profile: any): number
	local highest = 1
	for index, zone in ipairs(ZONE_ORDER) do
		if hasReached(profile, zone) then
			highest = index
		end
	end
	return highest
end

local function reachedPetDefs(profile: any): { any }
	local list = {}
	for _, def in ipairs(GameConfig.PETS or {}) do
		if hasReached(profile, def.zone) then
			table.insert(list, def)
		end
	end
	return list
end

local function ownedPetDefs(profile: any): { any }
	local pets = ensurePets(profile)
	local list = {}
	for _, def in ipairs(GameConfig.PETS or {}) do
		if pets.owned[def.key] then
			table.insert(list, def)
		end
	end
	return list
end

local function randomEntry(list: { any }): any?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function freeSpinRemaining(profile: any): number
	local rewards = ensureRewards(profile)
	local elapsed = math.max(0, os.time() - rewards.lastFreeSpin)
	return math.max(0, (GameConfig.PET_REWARDS.freeSpinCooldown or 86400) - elapsed)
end

local function resultId(player: Player, kind: string, count: number): string
	return tostring(player.UserId) .. ":" .. kind .. ":" .. tostring(count) .. ":" .. tostring(os.time())
end

local function buildState(player: Player, result: any?, message: string?): any
	local profile = PlayerDataService.Get(player)
	if not profile then
		return { loading = true, result = result, message = message }
	end
	local rewards = ensureRewards(profile)
	local ownedCount = #ownedPetDefs(profile)
	local slots = {}
	for index, slot in ipairs(GameConfig.PET_REWARDS.wheelSlots or {}) do
		table.insert(slots, { index = index, kind = slot.kind, label = slot.label })
	end
	return {
		gold = profile.gold,
		diamonds = profile.diamonds,
		freeSpinRemaining = freeSpinRemaining(profile),
		paidSpinDiamonds = GameConfig.PET_REWARDS.paidSpinDiamonds or 5,
		wheelPity = rewards.wheelPity,
		wheelPitySpins = GameConfig.PET_REWARDS.wheelPitySpins or 20,
		crateDiamonds = GameConfig.PET_REWARDS.crateDiamonds or 4,
		cratePity = rewards.cratePity,
		crateRarePity = GameConfig.PET_REWARDS.crateRarePity or 8,
		ownedPetCount = ownedCount,
		canOpenCrate = ownedCount > 0,
		totalSpins = rewards.totalSpins,
		totalCrates = rewards.totalCrates,
		wheelSlots = slots,
		result = result,
		message = message,
	}
end

function PetRewardService.PushState(player: Player, result: any?, message: string?)
	Remotes.Get("PetRewardState"):FireClient(player, buildState(player, result, message))
end

local function reportRecruitment(player: Player, petName: string)
	if QuestService and typeof(QuestService.ReportPetRecruitment) == "function" then
		QuestService.ReportPetRecruitment(player, petName)
	end
end

local function autoEquip(pets: any, key: string)
	for _, equippedKey in ipairs(pets.equipped) do
		if equippedKey == key then
			return
		end
	end
	if #pets.equipped < (GameConfig.PET_SYSTEM.maxEquipped or 3) then
		table.insert(pets.equipped, key)
	end
end

local function refreshEverything(player: Player, result: any, message: string)
	if PetService and typeof(PetService.RefreshPlayer) == "function" then
		PetService.RefreshPlayer(player, message)
	else
		PlayerDataService.PushState(player)
	end
	PetRewardService.PushState(player, result, message)
end

local function grantGolden(player: Player, profile: any): any
	local pets = ensurePets(profile)
	local reached = reachedPetDefs(profile)
	local preferred = {}
	for _, def in ipairs(reached) do
		local data = pets.owned[def.key]
		if not data or not data.golden then
			table.insert(preferred, def)
		end
	end
	local def = randomEntry(if #preferred > 0 then preferred else reached)
	if not def then
		return { kind = "gold", label = "Golden fallback", amount = 500 }
	end
	local data = pets.owned[def.key]
	local newlyOwned = data == nil
	if not data then
		data = { level = 1, xp = 0, golden = false, shards = 0, rank = 1 }
		pets.owned[def.key] = data
		autoEquip(pets, def.key)
	end
	local duplicate = data.golden == true
	if duplicate then
		local compensation = GameConfig.PET_REWARDS.duplicateGoldenShards or 50
		data.shards = (data.shards or 0) + compensation
		return {
			kind = "golden_duplicate",
			petKey = def.key,
			petName = def.name,
			amount = compensation,
			label = "Golden duplicate: +" .. tostring(compensation) .. " " .. def.name .. " shards",
		}
	end
	data.golden = true
	data.rank = data.rank or 1
	if newlyOwned then
		reportRecruitment(player, def.name)
	end
	return {
		kind = "golden",
		petKey = def.key,
		petName = def.name,
		newlyOwned = newlyOwned,
		label = "Golden " .. def.name,
	}
end

local function ringEssence(ringIndex: number): (string, string)
	local zone = ZONE_ORDER[ringIndex]
	for key, meta in GameConfig.ESSENCE do
		if meta.zone == zone then
			return key, meta.name
		end
	end
	return "MeadowPollen", "Meadow Pollen"
end

local function applyWheelSlot(player: Player, profile: any, slotIndex: number): any
	local config = GameConfig.PET_REWARDS
	local slot = config.wheelSlots[slotIndex]
	local ringIndex = highestRing(profile)
	local goldScale = config.goldScaleByRing[ringIndex] or 1
	if slot.kind == "gold" then
		local amount = math.max(1, math.floor((slot.amount or 0) * goldScale))
		profile.gold += amount
		return { kind = "gold", slot = slotIndex, amount = amount, label = string.format("%d Gold", amount) }
	elseif slot.kind == "diamonds" then
		local amount = slot.amount or 1
		profile.diamonds += amount
		return { kind = "diamonds", slot = slotIndex, amount = amount, label = tostring(amount) .. " Diamonds" }
	elseif slot.kind == "essence" then
		local key, name = ringEssence(ringIndex)
		local amount = config.essenceByRing[ringIndex] or 8
		profile.essence = profile.essence or {}
		profile.essence[key] = (profile.essence[key] or 0) + amount
		return { kind = "essence", slot = slotIndex, essenceKey = key, amount = amount, label = tostring(amount) .. " " .. name }
	elseif slot.kind == "shards" then
		local def = randomEntry(ownedPetDefs(profile))
		if not def then
			local amount = math.max(1, math.floor(250 * goldScale))
			profile.gold += amount
			return { kind = "gold", slot = slotIndex, amount = amount, label = tostring(amount) .. " Gold (no owned pet for shards)" }
		end
		local data = profile.pets.owned[def.key]
		local amount = slot.amount or 8
		data.shards = (data.shards or 0) + amount
		return { kind = "shards", slot = slotIndex, petKey = def.key, petName = def.name, amount = amount, label = tostring(amount) .. " " .. def.name .. " Shards" }
	elseif slot.kind == "golden" then
		local result = grantGolden(player, profile)
		result.slot = slotIndex
		return result
	end
	return { kind = "none", slot = slotIndex, label = "No reward" }
end

local function onSpin(player: Player)
	local now = os.clock()
	if now < (busyUntil[player] or 0) then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local rewards = ensureRewards(profile)
	local usingFree = freeSpinRemaining(profile) <= 0
	if usingFree then
		rewards.lastFreeSpin = os.time()
	else
		local cost = GameConfig.PET_REWARDS.paidSpinDiamonds or 5
		if not PlayerDataService.SpendCurrency(player, 0, cost) then
			PetRewardService.PushState(player, nil, "You need " .. tostring(cost) .. " diamonds to spin.")
			return
		end
	end

	local goldenSlot = #(GameConfig.PET_REWARDS.wheelSlots or {})
	local pityLimit = GameConfig.PET_REWARDS.wheelPitySpins or 20
	local slotIndex = if rewards.wheelPity >= pityLimit - 1 then goldenSlot else rng:NextInteger(1, goldenSlot)
	if slotIndex == goldenSlot then
		rewards.wheelPity = 0
	else
		rewards.wheelPity += 1
	end
	rewards.totalSpins += 1
	busyUntil[player] = now + (GameConfig.PET_REWARDS.wheelLockSeconds or 2.6)
	local result = applyWheelSlot(player, profile, slotIndex)
	if WheelWorldService and typeof(WheelWorldService.SpinForResult) == "function" then
		WheelWorldService.SpinForResult(slotIndex)
	end
	result.action = "wheel"
	result.id = resultId(player, "wheel", rewards.totalSpins)
	result.usedFreeSpin = usingFree
	refreshEverything(player, result, "Wheel reward: " .. tostring(result.label))
end

local function onCrate(player: Player)
	local now = os.clock()
	if now < (busyUntil[player] or 0) then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local owned = ownedPetDefs(profile)
	if #owned == 0 then
		PetRewardService.PushState(player, nil, "Recruit at least one pet before opening a shard crate.")
		return
	end
	local cost = GameConfig.PET_REWARDS.crateDiamonds or 4
	if not PlayerDataService.SpendCurrency(player, 0, cost) then
		PetRewardService.PushState(player, nil, "You need " .. tostring(cost) .. " diamonds for a shard crate.")
		return
	end
	local rewards = ensureRewards(profile)
	local pityLimit = GameConfig.PET_REWARDS.crateRarePity or 8
	local roll = rng:NextInteger(1, 100)
	local tier: string
	local amount: number
	if rewards.cratePity >= pityLimit - 1 or roll <= 10 then
		tier, amount = "Rare", 30
		rewards.cratePity = 0
	elseif roll <= 40 then
		tier, amount = "Uncommon", 15
		rewards.cratePity += 1
	else
		tier, amount = "Common", 8
		rewards.cratePity += 1
	end
	local def = randomEntry(owned) :: any
	local data = profile.pets.owned[def.key]
	data.shards = (data.shards or 0) + amount
	rewards.totalCrates += 1
	busyUntil[player] = now + (GameConfig.PET_REWARDS.crateLockSeconds or 1.25)
	local result = {
		action = "crate",
		kind = "shards",
		id = resultId(player, "crate", rewards.totalCrates),
		petKey = def.key,
		petName = def.name,
		tier = tier,
		amount = amount,
		label = tier .. " crate: " .. tostring(amount) .. " " .. def.name .. " Shards",
	}
	refreshEverything(player, result, tostring(result.label))
end

local function onRankUpgrade(player: Player, rawKey: unknown)
	local now = os.clock()
	if now - (lastRankAction[player] or -math.huge) < 0.2 then
		return
	end
	lastRankAction[player] = now
	if type(rawKey) ~= "string" then
		return
	end
	local profile = PlayerDataService.Get(player)
	local def = defByKey[rawKey]
	if not profile or not def then
		return
	end
	local data = ensurePets(profile).owned[rawKey]
	if not data then
		return
	end
	local rank = math.clamp(math.floor(tonumber(data.rank) or 1), 1, GameConfig.PET_SYSTEM.maxRank or 5)
	if rank >= (GameConfig.PET_SYSTEM.maxRank or 5) then
		PetRewardService.PushState(player, nil, def.name .. " is already maximum rank.")
		return
	end
	local cost = GameConfig.PET_SYSTEM.rankCosts[rank]
	if not cost or (data.shards or 0) < cost then
		PetRewardService.PushState(player, nil, "Not enough " .. def.name .. " shards.")
		return
	end
	data.shards -= cost
	data.rank = rank + 1
	local rewards = ensureRewards(profile)
	local result = {
		action = "rank",
		kind = "rank",
		id = resultId(player, "rank", rewards.totalSpins + rewards.totalCrates + data.rank),
		petKey = def.key,
		petName = def.name,
		rank = data.rank,
		label = def.name .. " reached rank " .. tostring(data.rank),
	}
	refreshEverything(player, result, tostring(result.label))
end

local function hookPlayer(player: Player)
	task.spawn(function()
		local deadline = os.clock() + 20
		while player.Parent and not PlayerDataService.Get(player) and os.clock() < deadline do
			task.wait(0.2)
		end
		if PlayerDataService.Get(player) then
			PetRewardService.PushState(player)
		end
	end)
end

function PetRewardService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	PetService = services.PetService
	QuestService = services.QuestService
	WheelWorldService = services.WheelWorldService
	for _, def in ipairs(GameConfig.PETS or {}) do
		defByKey[def.key] = def
	end
end

function PetRewardService.Start()
	Remotes.Get("RequestPetRewards").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < 0.25 then
			return
		end
		lastRequest[player] = now
		PetRewardService.PushState(player)
	end)
	Remotes.Get("SpinPetWheel").OnServerEvent:Connect(onSpin)
	Remotes.Get("OpenPetCrate").OnServerEvent:Connect(onCrate)
	Remotes.Get("UpgradePetRank").OnServerEvent:Connect(onRankUpgrade)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		busyUntil[player] = nil
		lastRequest[player] = nil
		lastRankAction[player] = nil
	end)
	print("[PetRewardService] Golden Wheel, shard crates, pity, and pet ranks ready.")
end

return PetRewardService

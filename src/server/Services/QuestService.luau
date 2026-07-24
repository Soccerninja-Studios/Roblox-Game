--!strict
-- QuestService: tracks quest progress, hands out rewards, and syncs the quest
-- board to clients. All 150 quests live in Shared/QuestData. Objective "kinds"
-- that already have game systems are tracked live; kinds that wait on future
-- systems (combat, pets, villagers, auto-mowers, abilities) stay at 0 progress
-- until those systems call QuestService.Report* -- no quest code needs to change
-- when they ship.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local QuestData = require(ReplicatedStorage.Shared.QuestData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local QuestService = {}

local PlayerDataService: any

-- Objective kinds we can track with systems that exist today. Everything else
-- is defined in QuestData but simply never advances until its system reports in.
local LIVE_KINDS: { [string]: boolean } = {
	mow_type = true,
	fill_bag = true,
	deposit_gold = true,
	earn_diamonds = true,
	spend_gold = true,
	purchase_upgrades = true,
	skill_level = true,
	buy_equip_tool = true,
}

-- grass key -> the tool tier whose favored grass matches (the zone "specialist"
-- tool). Built from GameConfig so quest tool targets track the real ladder even
-- if tool names change.
local favoredTierByGrass: { [string]: number } = {}

-- The grass type each player most recently mowed, used to attribute zone-scoped
-- objectives like "fill your bag in the Meadow Ring".
local lastGrass: { [Player]: string } = {}

local function ensureQuests(profile: any)
	profile.quests = profile.quests or {}
	profile.quests.progress = profile.quests.progress or {}
	profile.quests.claimed = profile.quests.claimed or {}
	profile.quests.reached = profile.quests.reached or {}
	return profile.quests
end

local function isUnlocked(profile: any, zoneKey: string): boolean
	if zoneKey == "Meadow" then
		return true -- the first ring is always open
	end
	local q = ensureQuests(profile)
	return q.reached[zoneKey] == true
end

-- Resolve the display name + tier for a buy_equip_tool objective from the live
-- tool ladder (favored grass -> tier).
local function resolveTool(grass: string): (number?, string?)
	local tier = favoredTierByGrass[grass]
	if not tier then
		return nil, nil
	end
	local def = GameConfig.TOOL_TIERS[tier]
	return tier, def and def.name or nil
end

-- Add `amount` to a quest's progress (capped at target). Returns whether the
-- quest became newly complete on this call.
local function addProgress(profile: any, quest: any, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local q = ensureQuests(profile)
	local key = tostring(quest.id)
	if q.claimed[key] then
		return false
	end
	local target = quest.objective.target or 1
	local current = q.progress[key] or 0
	if current >= target then
		return false
	end
	local updated = math.min(target, current + amount)
	q.progress[key] = updated
	return current < target and updated >= target
end

-- Set progress to at least `value` (for level-style objectives). Returns whether
-- it became newly complete.
local function setAtLeast(profile: any, quest: any, value: number): boolean
	local q = ensureQuests(profile)
	local key = tostring(quest.id)
	if q.claimed[key] then
		return false
	end
	local target = quest.objective.target or 1
	local current = q.progress[key] or 0
	local updated = math.clamp(math.max(current, value), 0, target)
	if updated == current then
		return false
	end
	q.progress[key] = updated
	return current < target and updated >= target
end

-- Fire a small client toast when a quest completes or a reward is claimed.
local function toast(player: Player, payload: { [string]: any })
	Remotes.Get("QuestToast"):FireClient(player, payload)
end

-- Build and send the full quest board for a player.
function QuestService.PushState(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local q = ensureQuests(profile)
	local list = {}
	for _, quest in ipairs(QuestData.QUESTS) do
		local key = tostring(quest.id)
		local desc = quest.desc
		if quest.objective.kind == "buy_equip_tool" then
			local _, toolName = resolveTool(quest.objective.grass)
			if toolName then
				desc = "Buy and equip the " .. toolName .. "."
			end
		end
		table.insert(list, {
			id = quest.id,
			zone = quest.zone,
			name = quest.name,
			desc = desc,
			target = quest.objective.target or 1,
			progress = q.progress[key] or 0,
			claimed = q.claimed[key] == true,
			unlocked = isUnlocked(profile, quest.zone),
			live = LIVE_KINDS[quest.objective.kind] == true,
			reward = quest.reward,
		})
	end
	Remotes.Get("QuestState"):FireClient(player, { zones = QuestData.ZONES, quests = list })
end

-- Generic sweep over every quest, applying `apply(quest)` (which returns whether
-- that quest newly completed). Emits completion toasts and pushes state if
-- anything changed.
local function sweep(player: Player, predicate: (any) -> boolean, apply: (any) -> boolean)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local completed = false
	local changed = false
	for _, quest in ipairs(QuestData.QUESTS) do
		if LIVE_KINDS[quest.objective.kind] and isUnlocked(profile, quest.zone) and predicate(quest) then
			local wasComplete = apply(quest)
			changed = true
			if wasComplete then
				completed = true
				toast(player, { kind = "complete", name = quest.name })
			end
		end
	end
	if completed then
		QuestService.PushState(player)
	end
	return changed
end

-- ---- Public reporting API (called by other services / future systems) ----

-- Player mowed one tuft of the given grass type.
function QuestService.ReportMow(player: Player, grass: string)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local q = ensureQuests(profile)
	if not q.reached[grass] then
		q.reached[grass] = true -- unlocks that ring's quests
		QuestService.PushState(player)
	end
	lastGrass[player] = grass
	sweep(player, function(quest)
		return quest.objective.kind == "mow_type" and quest.objective.grass == grass
	end, function(quest)
		return addProgress(profile, quest, 1)
	end)
end

-- Player's carry bag just filled to capacity (attributed to their current ring).
function QuestService.ReportFillBag(player: Player)
	local grass = lastGrass[player]
	if not grass then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	sweep(player, function(quest)
		return quest.objective.kind == "fill_bag" and quest.zone == grass
	end, function(quest)
		return addProgress(profile, quest, 1)
	end)
end

-- Player deposited gold (and possibly diamonds) at the Gardener.
function QuestService.ReportDeposit(player: Player, gold: number, diamonds: number)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	if gold and gold > 0 then
		sweep(player, function(quest)
			return quest.objective.kind == "deposit_gold"
		end, function(quest)
			return addProgress(profile, quest, gold)
		end)
	end
	if diamonds and diamonds > 0 then
		sweep(player, function(quest)
			return quest.objective.kind == "earn_diamonds"
		end, function(quest)
			return addProgress(profile, quest, diamonds)
		end)
	end
end

-- Player spent gold at the Shop (any purchase).
function QuestService.ReportSpend(player: Player, gold: number)
	local profile = PlayerDataService.Get(player)
	if not profile or not gold or gold <= 0 then
		return
	end
	sweep(player, function(quest)
		return quest.objective.kind == "spend_gold"
	end, function(quest)
		return addProgress(profile, quest, gold)
	end)
end

-- Player completed a purchase of any kind (tool/skill/bag).
function QuestService.ReportPurchase(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	sweep(player, function(quest)
		return quest.objective.kind == "purchase_upgrades"
	end, function(quest)
		return addProgress(profile, quest, 1)
	end)
end

-- A skill reached a new level (e.g. SharpBlades -> Blade Sharpness).
function QuestService.ReportSkill(player: Player, skill: string, level: number)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	sweep(player, function(quest)
		return quest.objective.kind == "skill_level" and quest.objective.skill == skill
	end, function(quest)
		return setAtLeast(profile, quest, level)
	end)
end

-- Player's tool tier advanced (auto-equipped). Completes buy_equip_tool quests
-- whose resolved specialist tier is now owned.
function QuestService.ReportToolTier(player: Player, tier: number)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	sweep(player, function(quest)
		if quest.objective.kind ~= "buy_equip_tool" then
			return false
		end
		local needed = favoredTierByGrass[quest.objective.grass]
		return needed ~= nil and tier >= needed
	end, function(quest)
		return addProgress(profile, quest, 1)
	end)
end

-- Generic entry point for future systems: QuestService.Report(player, kind, amount, context)
-- context may carry fields like { grass=, monster=, boss=, essence=, ... } to
-- match objective params. Unknown/duplicate matching is safe (progress caps).
function QuestService.Report(player: Player, kind: string, amount: number?, context: { [string]: any }?)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local add = amount or 1
	local ctx = context or {}
	sweep(player, function(quest)
		if quest.objective.kind ~= kind then
			return false
		end
		for field, value in pairs(ctx) do
			if quest.objective[field] ~= value then
				return false
			end
		end
		return true
	end, function(quest)
		return addProgress(profile, quest, add)
	end)
end

-- ---- Claiming ----

local questById: { [number]: any } = {}

local function onClaim(player: Player, rawId: unknown)
	local id = tonumber(rawId)
	if not id then
		return
	end
	local quest = questById[id]
	if not quest then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	if not LIVE_KINDS[quest.objective.kind] then
		return -- objective's system isn't live yet
	end
	if not isUnlocked(profile, quest.zone) then
		return
	end
	local q = ensureQuests(profile)
	local key = tostring(id)
	if q.claimed[key] then
		return -- already claimed
	end
	local target = quest.objective.target or 1
	if (q.progress[key] or 0) < target then
		return -- not finished
	end
	q.claimed[key] = true
	local reward = quest.reward
	-- Only gold + diamonds are payable today; essence and named items (trophies,
	-- crowns, perks) are recorded on the quest data and will be granted once those
	-- systems exist.
	PlayerDataService.GrantCurrency(player, reward.gold or 0, reward.diamonds or 0)
	toast(player, {
		kind = "claimed",
		name = quest.name,
		gold = reward.gold or 0,
		diamonds = reward.diamonds or 0,
	})
	QuestService.PushState(player)
end

function QuestService.Init(services: any)
	PlayerDataService = services.PlayerDataService

	-- Index quests + build the favored-tool-tier map from the live tool ladder.
	for _, quest in ipairs(QuestData.QUESTS) do
		questById[quest.id] = quest
	end
	for tier, def in ipairs(GameConfig.TOOL_TIERS) do
		if def.favored and def.favored ~= "all" and not favoredTierByGrass[def.favored] then
			favoredTierByGrass[def.favored] = tier
		end
	end

	Remotes.Get("ClaimQuest").OnServerEvent:Connect(onClaim)
	Remotes.Get("RequestQuests").OnServerEvent:Connect(function(player)
		QuestService.PushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastGrass[player] = nil
	end)
end

function QuestService.Start() end

return QuestService

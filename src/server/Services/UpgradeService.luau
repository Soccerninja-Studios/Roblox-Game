--!strict
-- UpgradeService: validates and applies purchases of tool tiers and Kingdom Skills.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local SKILLS: { [string]: any } = GameConfig.SKILLS

local UpgradeService = {}

local PlayerDataService: any
local ToolService: any
local QuestService: any

local function onPurchase(player: Player, kind: unknown, id: unknown)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	if kind == "tool" then
		local nextTier = profile.toolTier + 1
		local toolDef = GameConfig.TOOL_TIERS[nextTier]
		if not toolDef then
			return -- already at max tier
		end
		if PlayerDataService.SpendGold(player, toolDef.cost) then
			profile.toolTier = nextTier
			-- Swap the held shears to the new tier's look
			if ToolService then
				ToolService.GiveTool(player)
			end
			if QuestService then
				QuestService.ReportSpend(player, toolDef.cost)
				QuestService.ReportPurchase(player)
				QuestService.ReportToolTier(player, nextTier)
			end
		end
	elseif kind == "skill" and type(id) == "string" then
		local skillDef = SKILLS[id]
		if not skillDef then
			return
		end
		local level = profile.skills[id] or 0
		if level >= skillDef.maxLevel then
			return
		end
		local cost = StatCalculator.GetSkillCost(id, level)
		if PlayerDataService.SpendGold(player, cost) then
			profile.skills[id] = level + 1
			if QuestService then
				QuestService.ReportSpend(player, cost)
				QuestService.ReportPurchase(player)
				QuestService.ReportSkill(player, id, level + 1)
			end
		end
	elseif kind == "bag" then
		local nextTier = (profile.bagTier or 1) + 1
		local bagDef = GameConfig.BAG_TIERS[nextTier]
		if not bagDef then
			return -- already at the biggest bag
		end
		if PlayerDataService.SpendGold(player, bagDef.cost) then
			profile.bagTier = nextTier
			if QuestService then
				QuestService.ReportSpend(player, bagDef.cost)
				QuestService.ReportPurchase(player)
			end
		end
	end

	PlayerDataService.PushState(player)
end

function UpgradeService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	ToolService = services.ToolService
	QuestService = services.QuestService
	Remotes.Get("PurchaseUpgrade").OnServerEvent:Connect(onPurchase)
end

return UpgradeService

--!strict
-- UpgradeService: validates and applies purchases of tool tiers and Kingdom Skills.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local SKILLS: { [string]: any } = GameConfig.SKILLS

local UpgradeService = {}

local PlayerDataService: any

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
		if PlayerDataService.Spend(player, toolDef.cost) then
			profile.toolTier = nextTier
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
		if PlayerDataService.Spend(player, cost) then
			profile.skills[id] = level + 1
		end
	end

	PlayerDataService.PushState(player)
end

function UpgradeService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	Remotes.Get("PurchaseUpgrade").OnServerEvent:Connect(onPurchase)
end

return UpgradeService

--!strict
-- SwordService: the combat counterpart to ToolService. It sells, upgrades, hands
-- out, and equips SWORDS (a separate hotbar Tool tagged with the "Sword" attribute
-- so the player can swap between shears and a blade), and resolves every sword
-- swing on the server: it finds the monsters in reach in front of the swinger and
-- applies damage through MonsterService. All tunables live in GameConfig.SWORDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local StatCalculator = require(Shared.StatCalculator)
local Remotes = require(Shared.Remotes)

local SwordService = {}

local PlayerDataService
local MonsterService
local QuestService
local CutsceneService

local lastSwing: { [Player]: number } = {}

-- Base (pre-scale) blade dimensions, shared by the visible sword mesh AND the
-- swing hitbox so the two can never drift apart.
local SWORD_BLADE_SIZE = Vector3.new(0.32, 3.8, 0.95)
-- The swing hitbox is blown up this much versus the blade so small swords still
-- connect comfortably.
local HITBOX_SCALE = 2

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function swordDef(key): any
	if not key then
		return nil
	end
	for _, d in ipairs(GameConfig.SWORDS) do
		if d.key == key then
			return d
		end
	end
	return nil
end

-- A player can only buy/equip a sword once they have REACHED its zone. Meadow is
-- always open; other zones unlock through quests.reached (same gate the backpacks
-- and mowers use).
local function hasReachedZone(profile, zone: string): boolean
	if zone == "All" then
		local kills = profile.bosses and profile.bosses.kills
		if not kills then
			return false
		end
		for _, boss in ipairs(GameConfig.BOSSES or {}) do
			if (kills[boss.key] or 0) < 1 then
				return false
			end
		end
		return #(GameConfig.BOSSES or {}) > 0
	end
	if zone == "Meadow" then
		return true
	end
	local reached = profile.quests and profile.quests.reached
	return reached ~= nil and reached[zone] == true
end


local function canUnlockSword(profile: any, def: any): boolean
	if not hasReachedZone(profile, def.zone) then
		return false
	end
	if def.requiresAllBosses then
		return PlayerDataService.HasDefeatedAllBosses(profile)
	end
	return true
end

-- Build a lightweight procedural sword Tool: handle in the palm, a crossguard, and
-- a blade -- no uploaded mesh required (like the starter shears).
local function buildSwordTool(def): Tool
	local scale = def.scale or 1

	local tool = Instance.new("Tool")
	tool.Name = "Sword"
	tool.ToolTip = def.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("Sword", true)
	tool:SetAttribute("SwordKey", def.key)

	-- The gripped Handle is an INVISIBLE anchor: it is what the hand holds (via the
	-- engine's RightGrip), so it can never rotate on its own. Every VISIBLE part of
	-- the sword -- the wooden Hilt, the Guard, and the Blade -- hangs off it through a
	-- single "Pivot" Motor6D, so when we swing the Pivot the ENTIRE sword (grip
	-- included) rotates around the hand. This is what fixes the handle not swinging.
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.4, 0.4) * scale
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	-- Visible wooden grip. Rests exactly on the invisible Handle so it sits in the
	-- hand, and swings with the blade because it is the Pivot's moving side.
	local hilt = Instance.new("Part")
	hilt.Name = "Hilt"
	hilt.Size = Vector3.new(0.4, 1.4, 0.4) * scale
	hilt.Color = c3(def.handleColor or { 90, 60, 40 })
	hilt.Material = Enum.Material.Wood
	hilt.CanCollide = false
	hilt.CanQuery = false
	hilt.CanTouch = false
	hilt.Massless = true
	hilt.Parent = tool

	-- The Pivot joins the invisible Handle (Part0 = grip origin) to the visible Hilt
	-- (Part1). RestC0 keeps the Hilt on the grip; SwungC0 rotates the whole assembly
	-- forward-down around that grip. SwordController tweens between these two poses --
	-- the exact same RestC0/SwungC0 contract the mowing tools use, which is why it
	-- animates on any R6/R15 rig.
	local restPose = CFrame.new()
	local pivot = Instance.new("Motor6D")
	pivot.Name = "Pivot"
	pivot.Part0 = handle
	pivot.Part1 = hilt
	pivot.C0 = restPose
	pivot:SetAttribute("RestC0", restPose)
	pivot:SetAttribute("SwungC0", restPose * CFrame.Angles(math.rad(-120), 0, 0))
	pivot.Parent = handle

	-- Guard and Blade weld onto the Hilt, so grip + guard + blade move as one rigid
	-- sword whenever the Pivot swings.
	local guard = Instance.new("Part")
	guard.Name = "Guard"
	guard.Size = Vector3.new(1.7, 0.28, 0.55) * scale
	guard.Color = Color3.fromRGB(214, 202, 150)
	guard.Material = Enum.Material.Metal
	guard.CanCollide = false
	guard.CanQuery = false
	guard.CanTouch = false
	guard.Massless = true
	guard.Parent = tool
	local gw = Instance.new("Weld")
	gw.Part0 = hilt
	gw.Part1 = guard
	gw.C0 = CFrame.new(0, 0.75 * scale, 0)
	gw.Parent = hilt

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = SWORD_BLADE_SIZE * scale
	blade.Color = c3(def.bladeColor or { 205, 212, 222 })
	blade.Material = Enum.Material.Metal
	blade.Reflectance = 0.14
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.Massless = true
	blade.Parent = tool
	local bw = Instance.new("Weld")
	bw.Part0 = hilt
	bw.Part1 = blade
	bw.C0 = CFrame.new(0, 0.75 * scale + 1.9 * scale, 0)
	bw.Parent = hilt

	return tool
end

local function clearSwordTools(player: Player)
	local function clear(container: Instance?)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Sword") then
				child:Destroy()
			end
		end
	end
	clear(player.Character)
	clear(player:FindFirstChildOfClass("Backpack"))
end

-- Remove any swords the player is carrying, then hand them the sword they have
-- equipped (if any). During the intro, this deliberately stops after cleanup so
-- no sword can appear in the hotbar or character while the cutscene is playing.
function SwordService.GiveSword(player: Player)
	clearSwordTools(player)
	if CutsceneService and CutsceneService.IsIntroPending(player) then
		return
	end

	local profile = PlayerDataService and PlayerDataService.Get(player)
	if not profile then
		return
	end

	local swords = profile.swords
	local key = swords and swords.equipped
	if not key then
		return
	end
	if not (swords.owned and swords.owned[key]) then
		return
	end
	local def = swordDef(key)
	if not def then
		return
	end

	local tool = buildSwordTool(def)
	tool.Parent = player:FindFirstChildOfClass("Backpack") or player.Character
end

-- Client asked us to resolve a swing. Validate the held tool + cooldown, then let
-- MonsterService damage everything in reach in front of the player.
local function onSwordSwing(player: Player)
	local profile = PlayerDataService and PlayerDataService.Get(player)
	if not profile then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not root then
		return
	end

	local held = char:FindFirstChildOfClass("Tool")
	if not held or not held:GetAttribute("Sword") then
		return
	end
	local key = held:GetAttribute("SwordKey")
	local def = swordDef(key)
	if not def then
		return
	end

	local now = os.clock()
	local cd = StatCalculator.GetSwordCooldown(key, profile.skills)
	if now - (lastSwing[player] or 0) < cd * 0.85 then
		return
	end
	lastSwing[player] = now

	local level = (profile.swords.level and profile.swords.level[key]) or 1
	local damage = StatCalculator.GetSwordDamage(key, level, profile.skills)
	local reach = StatCalculator.GetSwordReach(key)
	if MonsterService then
		local rootPart = root :: BasePart
		if def.special == "whirlwind" then
			-- Kingsedge is the all-boss reward: a complete 360-degree sweep whose
			-- true damage bypasses temporary boss armor.
			local radius = def.specialRadius or reach
			MonsterService.DamageMonstersInRadius(player, rootPart.Position, radius, damage, true)
			Remotes.Get("SwordSpecial"):FireClient(player, "whirlwind", rootPart.Position, radius)
		else
			-- Normal swords use a generous oriented volume in front of the player.
			local scale = def.scale or 1
			local bladeLen = SWORD_BLADE_SIZE.Y * scale * HITBOX_SCALE
			local bladeThick = SWORD_BLADE_SIZE.Z * scale * HITBOX_SCALE
			local forward = math.max(bladeLen, reach)
			local hitboxSize = Vector3.new(math.max(bladeThick, 2.5), math.max(bladeLen, 4), forward)
			local hitboxCFrame = rootPart.CFrame * CFrame.new(0, -0.5, -forward * 0.5)
			MonsterService.DamageMonstersInHitbox(player, hitboxCFrame, hitboxSize, damage)
		end
	end
end

-- Build the shop-tab snapshot for one player.
local function buildState(player: Player): any
	local profile = PlayerDataService.Get(player)
	local list = {}
	if profile then
		for _, def in ipairs(GameConfig.SWORDS) do
			local owned = profile.swords.owned[def.key] == true
			local level = math.clamp(profile.swords.level[def.key] or 1, 1, #def.levels)
			local maxLevel = #def.levels
			local blade = def.bladeColor or { 200, 200, 200 }
			table.insert(list, {
				key = def.key,
				name = def.name,
				zone = def.zone,
				desc = def.desc,
				goldCost = def.goldCost or 0,
				diamondCost = def.diamondCost or 0,
				essenceKey = def.essenceKey,
				essenceName = if def.essenceKey and GameConfig.ESSENCE[def.essenceKey] then GameConfig.ESSENCE[def.essenceKey].name else nil,
				essenceCost = def.essenceCost or 0,
				damage = def.levels[level].damage,
				nextDamage = if owned and level < maxLevel then def.levels[level + 1].damage else nil,
				nextCost = if owned and level < maxLevel then def.levels[level + 1].cost else nil,
				level = level,
				maxLevel = maxLevel,
				owned = owned,
				unlocked = canUnlockSword(profile, def),
				requirementText = def.requirementText,
				equipped = profile.swords.equipped == def.key,
				bladeR = blade[1],
				bladeG = blade[2],
				bladeB = blade[3],
			})
		end
	end
	local essence = {}
	if profile and profile.essence then
		for k, v in profile.essence do
			essence[k] = v
		end
	end
	return {
		swords = list,
		gold = profile and profile.gold or 0,
		diamonds = profile and profile.diamonds or 0,
		essence = essence,
	}
end

function SwordService.PushState(player: Player)
	Remotes.Get("SwordState"):FireClient(player, buildState(player))
end

local function onPurchase(player: Player, key)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local def = swordDef(key)
	if not def then
		return
	end
	if profile.swords.owned[key] then
		return
	end
	if not canUnlockSword(profile, def) then
		return
	end
	if not PlayerDataService.SpendCurrency(
		player,
		def.goldCost or 0,
		def.diamondCost or 0,
		def.essenceKey,
		def.essenceCost or 0
	) then
		return
	end
	profile.swords.owned[key] = true
	profile.swords.level[key] = 1
	if QuestService and typeof(QuestService.ReportSwordPurchase) == "function" then
		QuestService.ReportSwordPurchase(player, def.name)
	end
	if not profile.swords.equipped then
		profile.swords.equipped = key
		SwordService.GiveSword(player)
	end
	PlayerDataService.PushState(player)
	SwordService.PushState(player)
end

local function onUpgrade(player: Player, key)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local def = swordDef(key)
	if not def then
		return
	end
	if not profile.swords.owned[key] then
		return
	end
	local level = profile.swords.level[key] or 1
	if level >= #def.levels then
		return
	end
	local cost = def.levels[level + 1].cost or 0
	if not PlayerDataService.SpendGold(player, cost) then
		return
	end
	profile.swords.level[key] = level + 1
	PlayerDataService.PushState(player)
	SwordService.PushState(player)
end

local function onEquip(player: Player, key)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	if not profile.swords.owned[key] then
		return
	end
	profile.swords.equipped = key
	SwordService.GiveSword(player)
	SwordService.PushState(player)
end

function SwordService.Init(services)
	PlayerDataService = services.PlayerDataService
	MonsterService = services.MonsterService
	QuestService = services.QuestService
	CutsceneService = services.CutsceneService
end

function SwordService.Start()
	Remotes.Get("SwordSwing").OnServerEvent:Connect(onSwordSwing)
	Remotes.Get("PurchaseSword").OnServerEvent:Connect(onPurchase)
	Remotes.Get("UpgradeSword").OnServerEvent:Connect(onUpgrade)
	Remotes.Get("EquipSword").OnServerEvent:Connect(onEquip)
	Remotes.Get("RequestSwords").OnServerEvent:Connect(function(player)
		SwordService.PushState(player)
	end)

	-- Everyone starts with the first sword owned + equipped, exactly like the starter
	-- shears -- monsters can appear from the very first grass cut, so the player must
	-- always have a weapon in hand.
	local function ensureStarterSword(player: Player)
		local profile = PlayerDataService and PlayerDataService.Get(player)
		if not profile or not profile.swords then
			return
		end
		local swords = profile.swords
		swords.owned = swords.owned or {}
		swords.level = swords.level or {}
		local starter = GameConfig.SWORDS[1]
		if not starter then
			return
		end
		if not swords.owned[starter.key] then
			swords.owned[starter.key] = true
			swords.level[starter.key] = swords.level[starter.key] or 1
		end
		if not swords.equipped then
			swords.equipped = starter.key
		end
		if QuestService and typeof(QuestService.ReportSwordPurchase) == "function" then
			QuestService.ReportSwordPurchase(player, starter.name)
		end
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.6)
			ensureStarterSword(player)
			SwordService.GiveSword(player)
		end)
		if player.Character then
			ensureStarterSword(player)
			SwordService.GiveSword(player)
		end
	end
	for _, plr in Players:GetPlayers() do
		hook(plr)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(plr)
		lastSwing[plr] = nil
	end)
	print("[SwordService] ready.")
end

return SwordService

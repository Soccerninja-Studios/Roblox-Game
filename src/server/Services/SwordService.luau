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

local lastSwing: { [Player]: number } = {}

-- Base (pre-scale) blade dimensions, shared by the visible sword mesh AND the
-- swing hitbox so the two can never drift apart.
local SWORD_BLADE_SIZE = Vector3.new(0.32, 3.8, 0.95)
-- The swing hitbox is blown up this much versus the blade so small swords still
-- connect comfortably.
local HITBOX_SCALE = 1.5

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
	if zone == "Meadow" then
		return true
	end
	local reached = profile.quests and profile.quests.reached
	return reached ~= nil and reached[zone] == true
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

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.4, 0.4) * scale
	handle.Color = c3(def.handleColor or { 90, 60, 40 })
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

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
	gw.Part0 = handle
	gw.Part1 = guard
	gw.C0 = CFrame.new(0, 0.75 * scale, 0)
	gw.Parent = handle

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
	bw.Part0 = handle
	bw.Part1 = blade
	bw.C0 = CFrame.new(0, 0.75 * scale + 1.9 * scale, 0)
	bw.Parent = handle

	return tool
end

-- Remove any swords the player is carrying, then hand them the sword they have
-- equipped (if any). The sword goes into the BACKPACK, not the character, so it
-- sits in the hotbar next to the shears and the player picks which to hold.
function SwordService.GiveSword(player: Player)
	local profile = PlayerDataService and PlayerDataService.Get(player)
	if not profile then
		return
	end

	local function clearOld(container: Instance?)
		if not container then
			return
		end
		for _, ch in container:GetChildren() do
			if ch:IsA("Tool") and ch:GetAttribute("Sword") then
				ch:Destroy()
			end
		end
	end
	clearOld(player.Character)
	clearOld(player:FindFirstChildOfClass("Backpack"))

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
		-- New combat model: no aiming or clicking on a target. We sweep a generous
		-- swing volume in front of the player -- the blade blown up 1.5x so small
		-- blades still land -- and damage every monster it overlaps. Forward depth
		-- uses the sword's reach stat so longer swords keep their range advantage.
		local scale = def.scale or 1
		local bladeLen = SWORD_BLADE_SIZE.Y * scale * HITBOX_SCALE
		local bladeThick = SWORD_BLADE_SIZE.Z * scale * HITBOX_SCALE
		local forward = math.max(bladeLen, reach)
		-- Width & height stay forgiving (min floors) so you don't have to line up
		-- the monster precisely; depth is the forward reach of the slam.
		local hitboxSize = Vector3.new(math.max(bladeThick, 2.5), math.max(bladeLen, 4), forward)
		local rootPart = root :: BasePart
		-- Center the box in front of the player, dropped slightly to match where the
		-- blade slams down.
		local hitboxCFrame = rootPart.CFrame * CFrame.new(0, -0.5, -forward * 0.5)
		MonsterService.DamageMonstersInHitbox(player, hitboxCFrame, hitboxSize, damage)
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
				damage = def.levels[level].damage,
				nextDamage = if owned and level < maxLevel then def.levels[level + 1].damage else nil,
				nextCost = if owned and level < maxLevel then def.levels[level + 1].cost else nil,
				level = level,
				maxLevel = maxLevel,
				owned = owned,
				unlocked = hasReachedZone(profile, def.zone),
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
	if not hasReachedZone(profile, def.zone) then
		return
	end
	if not PlayerDataService.SpendCurrency(player, def.goldCost or 0, def.diamondCost or 0) then
		return
	end
	profile.swords.owned[key] = true
	profile.swords.level[key] = 1
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
end

function SwordService.Start()
	Remotes.Get("SwordSwing").OnServerEvent:Connect(onSwordSwing)
	Remotes.Get("PurchaseSword").OnServerEvent:Connect(onPurchase)
	Remotes.Get("UpgradeSword").OnServerEvent:Connect(onUpgrade)
	Remotes.Get("EquipSword").OnServerEvent:Connect(onEquip)
	Remotes.Get("RequestSwords").OnServerEvent:Connect(function(player)
		SwordService.PushState(player)
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.6)
			SwordService.GiveSword(player)
		end)
		if player.Character then
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

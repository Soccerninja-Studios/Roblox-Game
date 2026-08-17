--!strict
-- MonsterService: the risk half of combat. Two jobs:
--   (1) PLAYER HP: set each player's zone-scaled max HP, and when they die scatter
--       their UNBANKED clippings into a recoverable pile (nothing is ever lost).
--   (2) MONSTERS: spawn, run, and kill roaming monsters. A monster can appear when
--       a player FULLY CLEARS a grass tile, gated by a self-correcting "pity" roll
--       so spawns never cluster and never dry up. All tunables live in GameConfig
--       (COMBAT, MONSTER_SPAWN, MONSTERS).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local StatCalculator = require(Shared.StatCalculator)
local Remotes = require(Shared.Remotes)

local MonsterService = {}

local PlayerDataService
local QuestService
local BossService

local ZONE_KEY_BY_INDEX = { "Meadow", "Wild", "Mossmire", "Thicket", "Ironweed" }

local monsterFolder: Folder
local monstersByZone: { [string]: { any } } = {}
local defByKey: { [string]: any } = {}
local aliveByZone: { [string]: number } = {}
local dryCount: { [Player]: number } = {}
local lastHurt: { [Player]: number } = {}
local guardStates: { [Player]: any } = {}

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- =========================================================================
-- Player HP + death scatter
-- =========================================================================

function MonsterService.ApplyMaxHP(player: Player, preserveHealth: boolean?)
	local profile = PlayerDataService and PlayerDataService.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local reached = profile and profile.quests and profile.quests.reached
	local baseHP = StatCalculator.GetPlayerMaxHP(reached)
	local healthBonus = if profile then PlayerDataService.GetPetBonus(profile, "maxHealth") else 0
	local maxHP = math.max(1, math.floor(baseHP * (1 + healthBonus) + 0.5))
	local oldMax = hum.MaxHealth
	local oldHealth = hum.Health
	hum.MaxHealth = maxHP
	if preserveHealth then
		hum.Health = math.clamp(oldHealth + math.max(0, maxHP - oldMax), 0, maxHP)
	else
		hum.Health = maxHP
	end
end

-- A glowing pile the owner runs back to in order to reclaim scattered clippings.
local function spawnScatterPile(player: Player, pos: Vector3, amount: number)
	local cfg = GameConfig.COMBAT
	local pile = Instance.new("Part")
	pile.Name = "ClippingPile"
	pile.Shape = Enum.PartType.Ball
	pile.Size = Vector3.new(2.4, 2.4, 2.4)
	pile.Color = Color3.fromRGB(126, 204, 84)
	pile.Material = Enum.Material.Neon
	pile.Anchored = true
	pile.CanCollide = false
	pile.CanQuery = false
	pile.CanTouch = false
	pile.Position = pos + Vector3.new(0, 1.5, 0)
	pile.Parent = Workspace

	local beam = Instance.new("Part")
	beam.Name = "Beacon"
	beam.Size = Vector3.new(0.6, 40, 0.6)
	beam.Color = Color3.fromRGB(150, 235, 90)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.55
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Position = pos + Vector3.new(0, 20, 0)
	beam.Parent = pile

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = pile
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextSize = 20
	label.Text = "\u{1F33F} " .. amount
	label.Parent = billboard

	local range = cfg.scatterReclaimRange or 6
	local reclaimed = false

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if reclaimed then
			return
		end
		if not pile.Parent or not player.Parent then
			-- Owner left or the pile is already gone: clean up. The pile is
			-- otherwise PERMANENT and waits indefinitely to be reclaimed (no timer).
			if conn then
				conn:Disconnect()
			end
			if not player.Parent and pile.Parent then
				pile:Destroy()
			end
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and ((root :: BasePart).Position - pile.Position).Magnitude <= range then
			reclaimed = true
			if conn then
				conn:Disconnect()
			end
			local profile = PlayerDataService.Get(player)
			if profile then
				local cap = PlayerDataService.GetBagCapacity(profile)
				profile.clippings = math.min(cap, (profile.clippings or 0) + amount)
				PlayerDataService.PushState(player)
			end
			Remotes.Get("ClippingsRecovered"):FireClient(player, amount)
			pile:Destroy()
		end
	end)
end

local function onDied(player: Player, character: Model)
	guardStates[player] = nil
	local profile = PlayerDataService and PlayerDataService.Get(player)
	if not profile then
		return
	end
	local carried = profile.clippings or 0
	local root = character:FindFirstChild("HumanoidRootPart")
	local pos = if root then (root :: BasePart).Position else character:GetPivot().Position
	if carried > 0 then
		profile.clippings = 0
		PlayerDataService.PushState(player)
		spawnScatterPile(player, pos, carried)
	end
	Remotes.Get("ClippingsScattered"):FireClient(player, carried)
end

-- =========================================================================
-- Monster model + brain
-- =========================================================================

-- Project a combat spawn onto real collidable ground. Raycasts used to stop on
-- GrassTile blades (and other non-collidable effects), placing monsters several
-- studs in the air. Recast past those decorations and exclude characters and
-- existing monsters so every common enemy and boss minion shares the same fix.
local function groundPosition(pos: Vector3): Vector3
	local exclusions: { Instance } = {}
	if monsterFolder then
		table.insert(exclusions, monsterFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclusions, player.Character)
		end
	end

	for _ = 1, 16 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclusions
		local hit = Workspace:Raycast(pos + Vector3.new(0, 64, 0), Vector3.new(0, -256, 0), params)
		if not hit then
			break
		end
		local instance = hit.Instance
		local ignore = instance:IsA("BasePart")
			and (not instance.CanCollide or instance.Name == "GrassTile" or instance.Name == "GrassBarrier")
		if not ignore then
			return hit.Position
		end
		table.insert(exclusions, instance)
	end
	return pos
end

function MonsterService.GetGroundPosition(pos: Vector3): Vector3
	return groundPosition(pos)
end

local function updateNameplate(model: Model)
	local head = model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("HP")
	if not gui then
		return
	end
	local bar = gui:FindFirstChild("Bar")
	local fill = bar and bar:FindFirstChild("Fill")
	local hp = model:GetAttribute("Health") or 0
	local max = model:GetAttribute("MaxHealth") or 1
	if fill then
		(fill :: Frame).Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
	end
end

local function buildMonster(def, cframe: CFrame): Model
	local scale = def.scale or 1

	local model = Instance.new("Model")
	model.Name = "Monster_" .. def.key

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1) * scale
	torso.Color = c3(def.bodyColor)
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = false
	torso.CanCollide = false
	torso.CanQuery = false
	torso.Massless = true
	torso.Parent = model
	local tw = Instance.new("Weld")
	tw.Part0 = root
	tw.Part1 = torso
	tw.Parent = root

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.5, 1.5, 1.5) * scale
	head.Color = c3(def.headColor or def.bodyColor)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = false
	head.CanCollide = false
	head.CanQuery = false
	head.Massless = true
	head.Parent = model
	local hw = Instance.new("Weld")
	hw.Part0 = root
	hw.Part1 = head
	hw.C0 = CFrame.new(0, 1.75 * scale, 0)
	hw.Parent = root

	for i = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.32, 0.32, 0.32) * scale
		eye.Color = Color3.fromRGB(20, 20, 24)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Anchored = false
		eye.CanCollide = false
		eye.CanQuery = false
		eye.Massless = true
		eye.Parent = model
		local ew = Instance.new("Weld")
		ew.Part0 = root
		ew.Part1 = eye
		ew.C0 = CFrame.new(0.32 * i * scale, 1.85 * scale, -0.6 * scale)
		ew.Parent = root
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HP"
	billboard.Size = UDim2.fromOffset(90, 30)
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 14)
	name.Font = Enum.Font.FredokaOne
	name.Text = def.name
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.TextSize = 13
	name.Parent = billboard
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 0, 0, 16)
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(220, 80, 70)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	model.PrimaryPart = root
	model:SetAttribute("MonsterKey", def.key)
	model:SetAttribute("MaxHealth", def.hp)
	model:SetAttribute("Health", def.hp)

	local ground = groundPosition(cframe.Position)
	root.CFrame = CFrame.new(ground.X, ground.Y + (1 * scale) + 0.5, ground.Z)
	return model
end

local function killMonster(model: Model, byPlayer: Player?)
	if model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("Dead", true)
	local def = defByKey[model:GetAttribute("MonsterKey")]
	if def and byPlayer then
		local essenceAmount = def.essenceReward or 0
		local essenceMeta = if def.essenceKey then GameConfig.ESSENCE[def.essenceKey] else nil
		local essenceName = if essenceMeta then essenceMeta.name else ""
		PlayerDataService.GrantCurrency(byPlayer, def.goldReward or 0, 0)
		if def.essenceKey and essenceAmount > 0 then
			PlayerDataService.GrantEssence(byPlayer, def.essenceKey, essenceAmount)
		end
		if QuestService and typeof(QuestService.ReportMonsterDefeated) == "function" then
			QuestService.ReportMonsterDefeated(byPlayer, def.name, def.zone, essenceName, essenceAmount)
		end
		Remotes.Get("MonsterDefeated"):FireClient(
			byPlayer,
			def.name,
			def.goldReward or 0,
			essenceName,
			essenceAmount
		)
	end
	Debris:AddItem(model, 0.05)
end

local function applyDamage(model: Model, damage: number, byPlayer: Player?): number
	local hp = model:GetAttribute("Health") or 0
	if hp <= 0 or model:GetAttribute("Dead") then
		return 0
	end
	local finalDamage = math.max(0, damage)
	if (model:GetAttribute("ArmorBreakUntil") or 0) > os.clock() then
		finalDamage *= model:GetAttribute("ArmorBreakDamageMultiplier") or 1.2
	end
	finalDamage = math.max(1, math.floor(finalDamage + 0.5))
	local dealt = math.min(hp, finalDamage)
	local newHp = math.max(0, hp - finalDamage)
	model:SetAttribute("Health", newHp)
	updateNameplate(model)
	local pp = model.PrimaryPart
	if byPlayer and pp then
		Remotes.Get("MonsterHit"):FireClient(byPlayer, pp.Position + Vector3.new(0, 2.5, 0), dealt, newHp <= 0)
	end
	if newHp <= 0 then
		killMonster(model, byPlayer)
	end
	return dealt
end

-- Shared model-damage router used by ordinary swings, specials, damage-over-time,
-- reflection, and Kingsedge. Bosses remain authoritative inside BossService.
function MonsterService.DamageModel(player: Player, model: Model, damage: number, trueDamage: boolean?): number
	if not model or not model.Parent or model:GetAttribute("Dead") then
		return 0
	end
	if model:GetAttribute("BossKey") and BossService then
		local before = model:GetAttribute("Health") or 0
		BossService.DamageBoss(model, damage, player, trueDamage == true)
		local after = model:GetAttribute("Health") or 0
		return math.max(0, before - after)
	end
	return applyDamage(model, damage, player)
end

function MonsterService.GetMonstersInHitbox(hitboxCFrame: CFrame, hitboxSize: Vector3): { Model }
	local found: { Model } = {}
	if not monsterFolder then
		return found
	end
	local half = hitboxSize * 0.5
	for _, model in monsterFolder:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart and not model:GetAttribute("Dead") then
			local pp = model.PrimaryPart :: BasePart
			local rel = hitboxCFrame:PointToObjectSpace(pp.Position)
			local mhalf = pp.Size * 0.5
			if math.abs(rel.X) <= half.X + mhalf.X
				and math.abs(rel.Y) <= half.Y + mhalf.Y
				and math.abs(rel.Z) <= half.Z + mhalf.Z
			then
				table.insert(found, model)
			end
		end
	end
	return found
end

function MonsterService.GetMonstersInRadius(center: Vector3, radius: number): { Model }
	local found: { Model } = {}
	if not monsterFolder then
		return found
	end
	for _, model in monsterFolder:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart and not model:GetAttribute("Dead") then
			local distance = (model.PrimaryPart.Position - center).Magnitude
			if distance <= radius + model.PrimaryPart.Size.Magnitude * 0.35 then
				table.insert(found, model)
			end
		end
	end
	return found
end

function MonsterService.DamageMonstersInHitbox(player: Player, hitboxCFrame: CFrame, hitboxSize: Vector3, damage: number): { any }
	local results = {}
	for _, model in MonsterService.GetMonstersInHitbox(hitboxCFrame, hitboxSize) do
		table.insert(results, { model = model, damage = MonsterService.DamageModel(player, model, damage, false) })
	end
	return results
end

function MonsterService.DamageMonstersInRadius(
	player: Player,
	center: Vector3,
	radius: number,
	damage: number,
	trueDamage: boolean?
): { any }
	local results = {}
	for _, model in MonsterService.GetMonstersInRadius(center, radius) do
		table.insert(results, { model = model, damage = MonsterService.DamageModel(player, model, damage, trueDamage) })
	end
	return results
end

-- Refreshing the same effect replaces its older task instead of stacking an
-- unbounded number of bleed/poison loops. Every tick still routes through the
-- authoritative damage and reward paths above.
function MonsterService.ApplyDamageOverTime(
	player: Player,
	model: Model,
	effectName: string,
	damagePerTick: number,
	ticks: number,
	tickRate: number
)
	if not model or not model.Parent or model:GetAttribute("Dead") then
		return
	end
	local tokenAttribute = "Status" .. effectName .. "Token"
	local token = (model:GetAttribute(tokenAttribute) or 0) + 1
	model:SetAttribute(tokenAttribute, token)
	model:SetAttribute(effectName .. "Until", os.clock() + ticks * tickRate)
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(tickRate)
			if not model.Parent or model:GetAttribute("Dead") or model:GetAttribute(tokenAttribute) ~= token then
				return
			end
			MonsterService.DamageModel(player, model, damagePerTick, false)
		end
	end)
end

function MonsterService.ApplyArmorBreak(model: Model, duration: number, reductionMultiplier: number, damageMultiplier: number)
	if not model or not model.Parent or model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("ArmorBreakUntil", math.max(model:GetAttribute("ArmorBreakUntil") or 0, os.clock() + duration))
	model:SetAttribute("ArmorBreakReductionMultiplier", math.clamp(reductionMultiplier, 0, 1))
	model:SetAttribute("ArmorBreakDamageMultiplier", math.max(1, damageMultiplier))
end

function MonsterService.SetPlayerGuard(player: Player, kind: string, duration: number, power: number, reflectScale: number, damageReduction: number?)
	guardStates[player] = {
		kind = kind,
		expiresAt = os.clock() + duration,
		power = math.max(0, power),
		reflectScale = math.max(0, reflectScale),
		damageReduction = math.clamp(damageReduction or 0, 0, 0.9),
	}
end

-- Shared authoritative damage path for common monsters and boss hazards. Keeping
-- lastHurt here prevents out-of-combat regeneration from running during boss hits.
function MonsterService.DamagePlayer(player: Player, damage: number, sourceModel: Model?): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or damage <= 0 then
		return false
	end
	local state = guardStates[player]
	if state and os.clock() > state.expiresAt then
		guardStates[player] = nil
		state = nil
	end
	if state and state.kind == "parry" then
		guardStates[player] = nil -- a parry consumes the guard on the first blocked hit
		if sourceModel and sourceModel.Parent then
			MonsterService.DamageModel(player, sourceModel, state.power * state.reflectScale, false)
		end
		if root and root:IsA("BasePart") then
			Remotes.Get("SwordSpecial"):FireClient(player, "parry", root.Position, 5)
		end
		return true
	end

	local finalDamage = damage
	if state and state.kind == "thorns" then
		finalDamage *= (1 - state.damageReduction)
		if sourceModel and sourceModel.Parent then
			MonsterService.DamageModel(player, sourceModel, state.power * state.reflectScale, false)
		end
		if root and root:IsA("BasePart") then
			Remotes.Get("SwordSpecial"):FireClient(player, "thorns", root.Position, 6)
		end
	end
	finalDamage = math.max(0.1, finalDamage)
	humanoid:TakeDamage(finalDamage)
	lastHurt[player] = os.clock()
	Remotes.Get("PlayerHurt"):FireClient(player, finalDamage)
	return true
end

local function runMonster(model: Model, def, origin: Vector3)
	local root = model.PrimaryPart :: BasePart
	local lastAttack = 0
	local roamTarget = origin
	local roamNext = 0

	-- The monster THINKS (scans players, picks a goal, attacks) on a coarse tick, but
	-- MOVES every frame toward its current goal. Decoupling the two keeps the decision
	-- cost low while making motion fine-grained -- roughly a tenth of a stud per frame
	-- instead of a big ~1-stud hop every 0.15s -- so the lock-on camera that follows a
	-- monster no longer jolts on each step.
	local THINK_INTERVAL = 0.15
	local sinceThink = math.huge -- force a think on the very first frame
	local goal: Vector3? = nil
	local moveSpeed = def.moveSpeed or 10

	while model.Parent and not model:GetAttribute("Dead") and (model:GetAttribute("Health") or 0) > 0 do
		local dt = task.wait()
		if not root or not root.Parent then
			break
		end
		local pos = root.Position

		sinceThink += dt
		if sinceThink >= THINK_INTERVAL then
			sinceThink = 0

			local target: Model? = nil
			local tdist = math.huge
			for _, plr in Players:GetPlayers() do
				local ch = plr.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local d = ((hrp :: BasePart).Position - pos).Magnitude
					if d < tdist then
						tdist = d
						target = ch
					end
				end
			end

			if target and tdist <= (def.aggroRange or 40) then
				moveSpeed = def.moveSpeed or 10
				local thrp = target:FindFirstChild("HumanoidRootPart")
				goal = if thrp then (thrp :: BasePart).Position else nil
				-- Attack reach halved (0.5x): monsters must close right up before they
				-- can land a hit, giving the player room to swing first.
				if tdist <= (def.attackRange or 6) * 0.5 then
					goal = nil
					local now = os.clock()
					if now - lastAttack >= (def.attackCooldown or 1.2) then
						lastAttack = now
						local plr = Players:GetPlayerFromCharacter(target)
						local hum = target:FindFirstChildOfClass("Humanoid")
						if plr then
							MonsterService.DamagePlayer(plr, def.damage or 1, model)
						elseif hum and hum.Health > 0 then
							hum:TakeDamage(def.damage or 1)
						end
					end
				end
			else
				if os.clock() >= roamNext then
					roamNext = os.clock() + math.random(2, 4)
					local ang = math.random() * math.pi * 2
					local r = math.random() * (def.roamRange or 16)
					roamTarget = origin + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
				end
				goal = roamTarget
				moveSpeed = (def.moveSpeed or 10) * 0.5
			end
		end

		if goal then
			local flat = Vector3.new(goal.X, pos.Y, goal.Z)
			local dir = flat - pos
			local dist = dir.Magnitude
			if dist > 0.05 then
				local step = dir.Unit * math.min(moveSpeed * dt, dist)
				local newPos = pos + step
				root.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(dir.X, 0, dir.Z))
			end
		end
	end
end

-- =========================================================================
-- Spawning (pity system)
-- =========================================================================

function MonsterService.Spawn(zoneKey: string, nearPos: Vector3, options: any?): Model?
	local cfg = GameConfig.MONSTER_SPAWN
	if (aliveByZone[zoneKey] or 0) >= (cfg.maxAlivePerZone or 12) then
		return nil
	end
	local pool = monstersByZone[zoneKey]
	if not pool or #pool == 0 then
		return nil
	end

	local total = 0
	for _, d in ipairs(pool) do
		total += (d.spawnWeight or 1)
	end
	local roll = math.random() * total
	local def = pool[1]
	for _, d in ipairs(pool) do
		roll -= (d.spawnWeight or 1)
		if roll <= 0 then
			def = d
			break
		end
	end

	local ang = math.random() * math.pi * 2
	local offsetRadius = 5
	if options and type(options.spawnRadius) == "number" then
		offsetRadius = math.max(0, options.spawnRadius)
	end
	local spawnPos = nearPos + Vector3.new(math.cos(ang) * offsetRadius, 0, math.sin(ang) * offsetRadius)
	local model = buildMonster(def, CFrame.new(spawnPos))
	model:SetAttribute("Zone", zoneKey)
	if options and type(options.summonerKey) == "string" then
		model:SetAttribute("BossSummoned", true)
		model:SetAttribute("SummonedByBossKey", options.summonerKey)
	end
	model.Parent = monsterFolder
	aliveByZone[zoneKey] = (aliveByZone[zoneKey] or 0) + 1

	local originPos = model.PrimaryPart and model.PrimaryPart.Position or spawnPos
	task.spawn(function()
		runMonster(model, def, originPos)
		aliveByZone[zoneKey] = math.max(0, (aliveByZone[zoneKey] or 1) - 1)
	end)
	return model
end

-- Called by GrassService when a player fully clears a tile. Runs the pity roll:
-- suppressed right after a spawn, ramping up through droughts, guaranteed after a
-- hard cap -- so monsters neither cluster nor dry up.
function MonsterService.OnTileCleared(player: Player, position: Vector3, zoneIndex: number)
	local zoneKey = ZONE_KEY_BY_INDEX[zoneIndex]
	if not zoneKey then
		return
	end
	local pool = monstersByZone[zoneKey]
	if not pool or #pool == 0 then
		return -- no monsters designed for this zone yet
	end
	local cfg = GameConfig.MONSTER_SPAWN
	if (aliveByZone[zoneKey] or 0) >= (cfg.maxAlivePerZone or 12) then
		return
	end

	local n = dryCount[player] or 0
	local chance
	if n >= (cfg.guaranteeAfter or 24) then
		chance = 1
	elseif n < (cfg.suppressTiles or 4) then
		local t = n / math.max(1, cfg.suppressTiles or 4)
		chance = (cfg.minChance or 0.02) + ((cfg.baseChance or 0.1) - (cfg.minChance or 0.02)) * t
	else
		chance = math.min(cfg.maxChance or 0.85, (cfg.baseChance or 0.1) + (n - (cfg.suppressTiles or 4) + 1) * (cfg.droughtRamp or 0.05))
	end

	if math.random() < chance then
		dryCount[player] = 0
		MonsterService.Spawn(zoneKey, position)
	else
		dryCount[player] = n + 1
	end
end

function MonsterService.Init(services)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	BossService = services.BossService
end

function MonsterService.Start()
	local existing = Workspace:FindFirstChild("Monsters")
	if existing and existing:IsA("Folder") then
		monsterFolder = existing
	else
		if existing then
			existing:Destroy()
		end
		monsterFolder = Instance.new("Folder")
		monsterFolder.Name = "Monsters"
		monsterFolder.Parent = Workspace
	end

	for _, def in ipairs(GameConfig.MONSTERS) do
		defByKey[def.key] = def
		monstersByZone[def.zone] = monstersByZone[def.zone] or {}
		table.insert(monstersByZone[def.zone], def)
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.wait(0.4)
			MonsterService.ApplyMaxHP(player)
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Died:Connect(function()
					onDied(player, character)
				end)
			end
		end)
		if player.Character then
			MonsterService.ApplyMaxHP(player)
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Died:Connect(function()
					onDied(player, player.Character :: Model)
				end)
			end
		end
	end
	for _, plr in Players:GetPlayers() do
		hook(plr)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(plr)
		dryCount[plr] = nil
		lastHurt[plr] = nil
		guardStates[plr] = nil
	end)

	-- Gentle out-of-combat regen so a 3-HP Meadow start isn't a death sentence.
	task.spawn(function()
		while true do
			task.wait(1)
			local cfg = GameConfig.COMBAT
			local regen = cfg.regenPerSecond or 0
			if regen > 0 then
				for _, plr in Players:GetPlayers() do
					local ch = plr.Character
					local hum = ch and ch:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
						if os.clock() - (lastHurt[plr] or 0) >= (cfg.regenDelay or 5) then
							hum.Health = math.min(hum.MaxHealth, hum.Health + regen)
						end
					end
				end
			end
		end
	end)

	print("[MonsterService] ready.")
end

return MonsterService

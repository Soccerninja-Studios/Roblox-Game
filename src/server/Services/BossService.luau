--!strict
-- BossService: complete five-ring boss framework.
--
-- Every boss is spawned when the last grass tile in its ring is cleared, fights
-- through a server-authoritative state machine, telegraphs every area attack, and
-- awards every player who contributed damage. Bosses respawn after a configurable
-- delay so champion/repeat quests remain completable without regrowing the ring.
-- All stats, rewards, colors, abilities, and timing live in GameConfig.BOSSES.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local BossService = {}

local PlayerDataService: any
local QuestService: any
local MonsterService: any
local monsterFolder: Folder

local ZONE_KEY_BY_INDEX = { "Meadow", "Wild", "Mossmire", "Thicket", "Ironweed" }

local bossByKey: { [string]: any } = {}
local bossByZone: { [string]: any } = {}
local activeByZone: { [string]: Model } = {}
local unlockedZones: { [string]: boolean } = {}
local spawnOrigins: { [string]: Vector3 } = {}
local spawnOwners: { [string]: Player } = {}
local contributors: { [Model]: { [Player]: boolean } } = {}
local respawnGeneration: { [string]: number } = {}
local summonLastAt: { [Model]: number } = {}

local spawnBoss: (string, Vector3, Player?) -> Model?

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function groundPoint(pos: Vector3): Vector3
	if MonsterService and typeof(MonsterService.GetGroundPosition) == "function" then
		return MonsterService.GetGroundPosition(pos)
	end
	return pos
end

local function makeWeldedPart(
	model: Model,
	root: BasePart,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	worldCFrame: CFrame,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = worldCFrame
	part.Parent = model

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = root.CFrame:ToObjectSpace(worldCFrame)
	weld.Parent = root
	return part
end

local function addBossSilhouette(model: Model, root: BasePart, def: any, scale: number)
	local bodyColor = c3(def.bodyColor)
	local accent = c3(def.accentColor or def.headColor or def.bodyColor)
	local visual = def.visual

	if visual == "flower" then
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * 1.25 * scale, 2.25 * scale, math.sin(angle) * 1.25 * scale)
			makeWeldedPart(
				model,
				root,
				"Petal",
				Vector3.new(0.85, 1.65, 0.32) * scale,
				accent,
				Enum.Material.SmoothPlastic,
				CFrame.new(root.Position + offset) * CFrame.Angles(0, -angle, angle),
				nil
			)
		end
	elseif visual == "broodmother" then
		for side = -1, 1, 2 do
			for i = 1, 4 do
				local z = (i - 2.5) * 0.85 * scale
				local x = side * (2.0 + i * 0.18) * scale
				makeWeldedPart(
					model,
					root,
					"Leg",
					Vector3.new(2.7, 0.28, 0.28) * scale,
					bodyColor,
					Enum.Material.Wood,
					CFrame.new(root.Position + Vector3.new(x, 0.15 * scale, z)) * CFrame.Angles(0, math.rad(12 * side * (i - 2.5)), math.rad(18 * side)),
					nil
				)
			end
		end
	elseif visual == "mirequeen" then
		for i = -1, 1 do
			makeWeldedPart(
				model,
				root,
				"CrownSpire",
				Vector3.new(0.28, (1.3 - math.abs(i) * 0.25), 0.28) * scale,
				accent,
				Enum.Material.Neon,
				CFrame.new(root.Position + Vector3.new(i * 0.65 * scale, 3.3 * scale, 0)),
				nil
			)
		end
	elseif visual == "vine" then
		for side = -1, 1, 2 do
			makeWeldedPart(
				model,
				root,
				"Branch",
				Vector3.new(0.36, 3.4, 0.36) * scale,
				accent,
				Enum.Material.Wood,
				CFrame.new(root.Position + Vector3.new(side * 1.15 * scale, 2.2 * scale, 0)) * CFrame.Angles(0, 0, math.rad(-28 * side)),
				nil
			)
		end
	elseif visual == "ironking" then
		for i = -2, 2 do
			local height = if i == 0 then 1.65 else 1.1
			makeWeldedPart(
				model,
				root,
				"Crown",
				Vector3.new(0.34, height, 0.34) * scale,
				accent,
				Enum.Material.Metal,
				CFrame.new(root.Position + Vector3.new(i * 0.42 * scale, (3.1 + height * 0.4) * scale, 0)),
				nil
			)
		end
		for side = -1, 1, 2 do
			makeWeldedPart(
				model,
				root,
				"ShoulderPlate",
				Vector3.new(1.4, 0.65, 1.25) * scale,
				accent,
				Enum.Material.Metal,
				CFrame.new(root.Position + Vector3.new(side * 1.5 * scale, 1.2 * scale, 0)),
				nil
			)
		end
	end
end

local function buildBoss(def: any, position: Vector3): Model
	local scale = def.scale or 2
	local ground = groundPoint(position)
	local rootPos = ground + Vector3.new(0, 1.15 * scale, 0)

	local model = Instance.new("Model")
	model.Name = "Boss_" .. def.key

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.5, 2.5, 2.5) * scale
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(rootPos)
	root.Parent = model

	local body = makeWeldedPart(
		model,
		root,
		"Torso",
		Vector3.new(2.8, 2.6, 2.4) * scale,
		c3(def.bodyColor),
		Enum.Material.SmoothPlastic,
		CFrame.new(rootPos),
		nil
	)
	body:SetAttribute("BossBody", true)

	local head = makeWeldedPart(
		model,
		root,
		"Head",
		Vector3.new(1.75, 1.75, 1.75) * scale,
		c3(def.headColor or def.bodyColor),
		Enum.Material.SmoothPlastic,
		CFrame.new(rootPos + Vector3.new(0, 2.05 * scale, 0)),
		Enum.PartType.Ball
	)

	for side = -1, 1, 2 do
		makeWeldedPart(
			model,
			root,
			"Eye",
			Vector3.new(0.34, 0.34, 0.34) * scale,
			Color3.fromRGB(24, 20, 24),
			Enum.Material.Neon,
			CFrame.new(rootPos + Vector3.new(0.38 * side * scale, 2.2 * scale, -0.78 * scale)),
			Enum.PartType.Ball
		)
	end

	addBossSilhouette(model, root, def, scale)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HP"
	billboard.Size = UDim2.fromOffset(170, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.1 * scale, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300
	billboard.Parent = head

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.FredokaOne
	title.Text = def.name
	title.TextColor3 = Color3.fromRGB(255, 239, 170)
	title.TextStrokeTransparency = 0.25
	title.TextSize = 18
	title.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 0, 0, 25)
	bar.Size = UDim2.new(1, 0, 0, 12)
	bar.BackgroundColor3 = Color3.fromRGB(42, 38, 42)
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = c3(def.accentColor or { 225, 80, 80 })
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	model.PrimaryPart = root
	model:SetAttribute("BossKey", def.key)
	model:SetAttribute("Zone", def.zone)
	model:SetAttribute("MaxHealth", def.hp)
	model:SetAttribute("Health", def.hp)
	model:SetAttribute("DamageReduction", 0)
	model:SetAttribute("Casting", false)
	return model
end

local function updateNameplate(model: Model)
	local head = model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("HP")
	local bar = gui and gui:FindFirstChild("Bar")
	local fill = bar and bar:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		local hp = model:GetAttribute("Health") or 0
		local maxHealth = model:GetAttribute("MaxHealth") or 1
		fill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, maxHealth), 0, 1), 1)
	end
end

local function bossPayload(model: Model, def: any, action: string, phase: string?): any
	return {
		action = action,
		key = def.key,
		name = def.name,
		zone = def.zone,
		health = model:GetAttribute("Health") or 0,
		maxHealth = model:GetAttribute("MaxHealth") or def.hp,
		phase = phase or model:GetAttribute("Phase") or "Engaged",
		model = model,
		color = def.accentColor,
	}
end

local function broadcast(model: Model, def: any, action: string, phase: string?)
	Remotes.Get("BossState"):FireAllClients(bossPayload(model, def, action, phase))
end

local function setPhase(model: Model, def: any, phase: string)
	model:SetAttribute("Phase", phase)
	broadcast(model, def, "update", phase)
end

local function nearestTarget(position: Vector3, maxDistance: number): (Player?, BasePart?, number)
	local bestPlayer: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = maxDistance
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance then
				bestPlayer = player
				bestRoot = root
				bestDistance = distance
			end
		end
	end
	return bestPlayer, bestRoot, bestDistance
end

local function makeTelegraph(center: Vector3, radius: number, color: Color3, lifetime: number): Part
	local ground = groundPoint(center)
	local marker = Instance.new("Part")
	marker.Name = "BossTelegraph"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.14, radius * 2, radius * 2)
	marker.CFrame = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Color = color
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.58
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = Workspace
	TweenService:Create(marker, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 0.2,
		Color = Color3.fromRGB(255, 80, 70),
	}):Play()
	Debris:AddItem(marker, lifetime + 0.25)
	return marker
end

local function makeLane(startPos: Vector3, endPos: Vector3, width: number, color: Color3, lifetime: number): Part
	local flatEnd = Vector3.new(endPos.X, startPos.Y, endPos.Z)
	local distance = math.max(1, (flatEnd - startPos).Magnitude)
	local middle = startPos:Lerp(flatEnd, 0.5)
	local ground = groundPoint(middle)
	local marker = Instance.new("Part")
	marker.Name = "BossLaneTelegraph"
	marker.Size = Vector3.new(width, 0.18, distance)
	marker.CFrame = CFrame.lookAt(Vector3.new(middle.X, ground.Y + 0.12, middle.Z), Vector3.new(flatEnd.X, ground.Y + 0.12, flatEnd.Z))
	marker.Color = color
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.6
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = Workspace
	TweenService:Create(marker, TweenInfo.new(lifetime), { Transparency = 0.18, Color = Color3.fromRGB(255, 80, 70) }):Play()
	Debris:AddItem(marker, lifetime + 0.2)
	return marker
end

local function damagePlayersAtPoints(points: { Vector3 }, radius: number, damage: number, source: Model?)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			for _, point in points do
				local delta = root.Position - point
				local flatDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if flatDistance <= radius and math.abs(delta.Y) <= 12 then
					MonsterService.DamagePlayer(player, damage, source)
					break
				end
			end
		end
	end
end

local function raiseSpike(point: Vector3, radius: number, height: number, color: Color3)
	local ground = groundPoint(point)
	local spike = Instance.new("Part")
	spike.Name = "BossSpike"
	spike.Size = Vector3.new(radius * 0.75, 0.2, radius * 0.75)
	spike.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0))
	spike.Color = color
	spike.Material = Enum.Material.Neon
	spike.Anchored = true
	spike.CanCollide = false
	spike.CanQuery = false
	spike.CanTouch = false
	spike.Parent = Workspace
	TweenService:Create(spike, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 0.75, height, radius * 0.75),
		CFrame = CFrame.new(ground + Vector3.new(0, height * 0.5, 0)),
	}):Play()
	task.delay(0.55, function()
		if spike.Parent then
			TweenService:Create(spike, TweenInfo.new(0.25), {
				Size = Vector3.new(radius * 0.75, 0.1, radius * 0.75),
				CFrame = CFrame.new(ground),
				Transparency = 1,
			}):Play()
		end
	end)
	Debris:AddItem(spike, 0.9)
end

local function countBossMinions(bossKey: string): number
	if not monsterFolder then
		return 0
	end
	local count = 0
	for _, child in monsterFolder:GetChildren() do
		if child:IsA("Model")
			and child:GetAttribute("SummonedByBossKey") == bossKey
			and not child:GetAttribute("Dead")
		then
			count += 1
		end
	end
	return count
end

local function clearBossMinions(bossKey: string)
	if not monsterFolder then
		return
	end
	for _, child in monsterFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("SummonedByBossKey") == bossKey then
			child:Destroy()
		end
	end
end

local function castSummon(model: Model, def: any, ability: any)
	local root = model.PrimaryPart
	if not root or not root.Parent then
		return
	end
	local system = GameConfig.BOSS_SYSTEM or {}
	local maxAlive = ability.maxAlive or system.maxSummonsPerBoss or 4
	local availableSlots = math.max(0, maxAlive - countBossMinions(def.key))
	if availableSlots <= 0 then
		return
	end
	local cooldown = ability.summonCooldown or ability.cooldown or system.summonCooldown or 18
	local now = os.clock()
	if now - (summonLastAt[model] or -math.huge) < cooldown then
		return
	end
	local playerRange = ability.playerRange or system.summonPlayerRange or 85
	playerRange = math.min(playerRange, def.aggroRange or playerRange)
	local nearbyPlayer = nearestTarget(root.Position, playerRange)
	if not nearbyPlayer then
		return -- never summon while every living player is outside the encounter
	end

	local count = math.min(ability.count or 2, availableSlots)
	local windup = ability.windup or 1.6
	local spawnRadius = ability.spawnRadius or 8
	local indicatorRadius = ability.indicatorRadius or system.summonIndicatorRadius or 2.8
	local angleOffset = math.random() * math.pi * 2
	local points: { Vector3 } = {}
	summonLastAt[model] = now -- reserve the cooldown before the warning begins
	setPhase(model, def, ability.label or "Calling reinforcements")
	for i = 1, count do
		local angle = angleOffset + ((i - 1) / math.max(1, count)) * math.pi * 2
		local point = root.Position + Vector3.new(math.cos(angle) * spawnRadius, 0, math.sin(angle) * spawnRadius)
		point = groundPoint(point)
		table.insert(points, point)
		makeTelegraph(point, indicatorRadius, Color3.fromRGB(255, 60, 55), windup)
	end
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	local playerStillNearby = nearestTarget(root.Position, playerRange)
	if not playerStillNearby then
		return -- the warning completes, but no minions appear after players leave
	end
	for _, point in points do
		if countBossMinions(def.key) >= maxAlive then
			break
		end
		MonsterService.Spawn(def.zone, point, { spawnRadius = 0, summonerKey = def.key })
	end
end

local function castSlam(model: Model, def: any, ability: any)
	local root = model.PrimaryPart
	if not root then
		return
	end
	setPhase(model, def, ability.label or "Ground slam")
	local center = root.Position
	local radius = ability.radius or 10
	local windup = ability.windup or 1
	makeTelegraph(center, radius, c3(def.accentColor), windup)
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	damagePlayersAtPoints({ center }, radius, ability.damage or def.damage, model)
	raiseSpike(center, radius, ability.height or 3, c3(def.accentColor))
end

-- Raise one hollow square ridge. Four separate sides make a true ring instead of
-- the old solid cube, and each side samples the actual ground beneath it.
local function raiseSquareShockwaveRing(center: Vector3, radius: number, width: number, height: number, color: Color3, riseTime: number)
	local sides = {
		{ offset = Vector3.new(0, 0, -radius), size = Vector3.new(radius * 2 + width, height, width) },
		{ offset = Vector3.new(0, 0, radius), size = Vector3.new(radius * 2 + width, height, width) },
		{ offset = Vector3.new(-radius, 0, 0), size = Vector3.new(width, height, math.max(width, radius * 2 - width)) },
		{ offset = Vector3.new(radius, 0, 0), size = Vector3.new(width, height, math.max(width, radius * 2 - width)) },
	}
	for _, side in sides do
		local ground = groundPoint(center + side.offset)
		local ridge = Instance.new("Part")
		ridge.Name = "MirequakeSquareRing"
		ridge.Size = Vector3.new(side.size.X, 0.12, side.size.Z)
		ridge.CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0))
		ridge.Color = color
		ridge.Material = Enum.Material.Neon
		ridge.Transparency = 0.22
		ridge.Anchored = true
		ridge.CanCollide = false
		ridge.CanQuery = false
		ridge.CanTouch = false
		ridge.Parent = Workspace
		TweenService:Create(ridge, TweenInfo.new(riseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = side.size,
			CFrame = CFrame.new(ground + Vector3.new(0, height * 0.5, 0)),
		}):Play()
		task.delay(riseTime + 0.3, function()
			if ridge.Parent then
				TweenService:Create(ridge, TweenInfo.new(0.35), {
					Transparency = 1,
					CFrame = ridge.CFrame + Vector3.new(0, 0.8, 0),
				}):Play()
			end
		end)
		Debris:AddItem(ridge, riseTime + 0.75)
	end
end

local function damagePlayersAtSquareRing(center: Vector3, radius: number, width: number, damage: number, source: Model)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local offset = root.Position - center
			local squareDistance = math.max(math.abs(offset.X), math.abs(offset.Z))
			if math.abs(squareDistance - radius) <= width * 0.65 and math.abs(offset.Y) <= 12 then
				MonsterService.DamagePlayer(player, damage, source)
			end
		end
	end
end

local function castShockwave(model: Model, def: any, ability: any)
	local root = model.PrimaryPart
	if not root then
		return
	end
	setPhase(model, def, ability.label or "Shaking the mire")
	local center = groundPoint(root.Position)
	local startRadius = ability.startRadius or 6
	local ringCount = ability.ringCount or 5
	local spacing = ability.ringSpacing or 4
	local maxRadius = ability.maxRadius or (startRadius + (ringCount - 1) * spacing)
	local width = ability.ringWidth or 2.2
	local height = ability.height or 2.4
	local windup = ability.windup or 1.3
	local riseTime = ability.riseTime or 0.3
	local stepDelay = ability.stepDelay or 0.28
	local color = c3(def.poolColor or def.accentColor)

	-- One large warning disc establishes the complete danger area; the square
	-- ridges then rise and deal damage one-by-one from the center outward.
	makeTelegraph(center, maxRadius, color, windup)
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	for index = 1, ringCount do
		if not model.Parent or model:GetAttribute("Dead") then
			return
		end
		local radius = math.min(maxRadius, startRadius + (index - 1) * spacing)
		raiseSquareShockwaveRing(center, radius, width, height, color, riseTime)
		task.wait(riseTime)
		damagePlayersAtSquareRing(center, radius, width, ability.damage or def.damage, model)
		task.wait(stepDelay)
	end
end

local function spikePoints(model: Model, ability: any): { Vector3 }
	local root = model.PrimaryPart
	if not root then
		return {}
	end
	local points = {}
	local count = ability.count or 6
	if ability.pattern == "line" then
		local _, targetRoot = nearestTarget(root.Position, 140)
		local targetPos = if targetRoot then targetRoot.Position else root.Position - root.CFrame.LookVector * 30
		local flat = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
		local spacing = ability.spacing or 6
		for i = 1, count do
			table.insert(points, root.Position + direction * (i * spacing))
		end
	else
		local ringRadius = ability.ringRadius or 12
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			table.insert(points, root.Position + Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius))
		end
	end
	return points
end

local function castSpikes(model: Model, def: any, ability: any)
	setPhase(model, def, ability.label or "Raising spikes")
	local points = spikePoints(model, ability)
	local radius = ability.radius or 3.5
	local windup = ability.windup or 1.1
	for _, point in points do
		makeTelegraph(point, radius, c3(def.accentColor), windup)
	end
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	damagePlayersAtPoints(points, radius, ability.damage or def.damage, model)
	for _, point in points do
		raiseSpike(point, radius, ability.height or 8, c3(def.accentColor))
	end
end

local function castPools(model: Model, def: any, ability: any)
	local root = model.PrimaryPart
	if not root then
		return
	end
	setPhase(model, def, ability.label or "Corrupting the ground")
	local _, targetRoot = nearestTarget(root.Position, 140)
	local anchor = if targetRoot then targetRoot.Position else root.Position
	local points = {}
	local count = ability.count or 3
	local radius = ability.radius or 5
	local windup = ability.windup or 1.05
	for i = 1, count do
		local angle = ((i - 1) / count) * math.pi * 2 + math.random()
		local distance = if i == 1 then 0 else (ability.spread or 9)
		local point = anchor + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		table.insert(points, point)
		makeTelegraph(point, radius, c3(def.accentColor), windup)
	end
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	local duration = ability.duration or 5
	for _, point in points do
		local ground = groundPoint(point)
		local pool = Instance.new("Part")
		pool.Name = "BossDamagePool"
		pool.Shape = Enum.PartType.Cylinder
		pool.Size = Vector3.new(0.16, radius * 2, radius * 2)
		pool.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pool.Color = c3(def.poolColor or def.accentColor)
		pool.Material = Enum.Material.Neon
		pool.Transparency = 0.35
		pool.Anchored = true
		pool.CanCollide = false
		pool.CanQuery = false
		pool.CanTouch = false
		pool.Parent = Workspace
		Debris:AddItem(pool, duration)
	end
	task.spawn(function()
		local elapsed = 0
		local tickRate = ability.tickRate or 1
		while elapsed < duration and model.Parent and not model:GetAttribute("Dead") do
			damagePlayersAtPoints(points, radius, ability.damage or 1, model)
			task.wait(tickRate)
			elapsed += tickRate
		end
	end)
end

local function castCharge(model: Model, def: any, ability: any)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local _, targetRoot = nearestTarget(root.Position, 140)
	if not targetRoot then
		return
	end
	setPhase(model, def, ability.label or "Charging")
	local startPos = root.Position
	local delta = Vector3.new(targetRoot.Position.X - startPos.X, 0, targetRoot.Position.Z - startPos.Z)
	if delta.Magnitude < 2 then
		return
	end
	local distance = math.min(delta.Magnitude + 5, ability.maxDistance or 38)
	local endPos = startPos + delta.Unit * distance
	endPos = Vector3.new(endPos.X, startPos.Y, endPos.Z)
	local windup = ability.windup or 0.9
	makeLane(startPos, endPos, ability.width or 8, c3(def.accentColor), windup)
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	local duration = ability.duration or 0.5
	local steps = math.max(4, math.floor(duration / 0.05))
	local hit: { [Player]: boolean } = {}
	for i = 1, steps do
		if not model.Parent or model:GetAttribute("Dead") then
			return
		end
		local alpha = i / steps
		local pos = startPos:Lerp(endPos, alpha)
		root.CFrame = CFrame.lookAt(pos, pos + delta.Unit)
		for _, player in Players:GetPlayers() do
			if not hit[player] then
				local character = player.Character
				local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if playerRoot and playerRoot:IsA("BasePart") and humanoid and humanoid.Health > 0 then
					local flat = Vector3.new(playerRoot.Position.X - pos.X, 0, playerRoot.Position.Z - pos.Z)
					if flat.Magnitude <= (ability.width or 8) * 0.65 then
						hit[player] = true
						MonsterService.DamagePlayer(player, ability.damage or def.damage, model)
					end
				end
			end
		end
		task.wait(duration / steps)
	end
end

local function castArmor(model: Model, def: any, ability: any)
	setPhase(model, def, ability.label or "Armored phase")
	local windup = ability.windup or 0.7
	task.wait(windup)
	if not model.Parent or model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("DamageReduction", ability.reduction or 0.55)
	local body = model:FindFirstChild("Torso")
	local oldMaterial = if body and body:IsA("BasePart") then body.Material else nil
	if body and body:IsA("BasePart") then
		body.Material = Enum.Material.Neon
	end
	castSummon(model, def, {
		label = ability.label,
		count = ability.count or 3,
		windup = ability.summonWindup or 1.6,
		cooldown = ability.summonCooldown,
		maxAlive = ability.maxAlive,
		spawnRadius = ability.spawnRadius,
		indicatorRadius = ability.indicatorRadius,
		playerRange = ability.playerRange,
	})
	task.wait(ability.duration or 5)
	if model.Parent then
		model:SetAttribute("DamageReduction", 0)
		if body and body:IsA("BasePart") and oldMaterial then
			body.Material = oldMaterial
		end
	end
end

local function castAbility(model: Model, def: any, ability: any)
	if model:GetAttribute("Casting") or model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("Casting", true)
	local ok, err = pcall(function()
		if ability.kind == "summon" then
			castSummon(model, def, ability)
		elseif ability.kind == "slam" then
			castSlam(model, def, ability)
		elseif ability.kind == "shockwave" then
			castShockwave(model, def, ability)
		elseif ability.kind == "spikes" then
			castSpikes(model, def, ability)
		elseif ability.kind == "pools" then
			castPools(model, def, ability)
		elseif ability.kind == "charge" then
			castCharge(model, def, ability)
		elseif ability.kind == "armor" then
			castArmor(model, def, ability)
		end
	end)
	if not ok then
		warn(string.format("[BossService] %s ability '%s' failed: %s", def.name, tostring(ability.kind), tostring(err)))
	end
	if model.Parent and not model:GetAttribute("Dead") then
		model:SetAttribute("Casting", false)
		setPhase(model, def, "Engaged")
	end
end

local function scheduleRespawn(zone: string)
	if not unlockedZones[zone] then
		return
	end
	respawnGeneration[zone] = (respawnGeneration[zone] or 0) + 1
	local generation = respawnGeneration[zone]
	local delaySeconds = (GameConfig.BOSS_SYSTEM and GameConfig.BOSS_SYSTEM.respawnSeconds) or 60
	task.delay(delaySeconds, function()
		if respawnGeneration[zone] ~= generation or activeByZone[zone] or not unlockedZones[zone] then
			return
		end
		local origin = spawnOrigins[zone]
		if origin and #Players:GetPlayers() > 0 then
			spawnBoss(zone, origin, spawnOwners[zone])
		end
	end)
end

local function runBoss(model: Model, def: any, origin: Vector3)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local lastBasic = 0
	local lastSeen = os.clock()
	local nextAbility = os.clock() + (def.firstAbilityDelay or 3)
	local abilityLast: { [string]: number } = {}
	local globalAbilityCooldown = def.globalAbilityCooldown or 2.4

	while model.Parent and not model:GetAttribute("Dead") and (model:GetAttribute("Health") or 0) > 0 do
		local dt = task.wait()
		if not root.Parent then
			break
		end
		local now = os.clock()
		local player, targetRoot, distance = nearestTarget(root.Position, def.aggroRange or 90)

		if player and targetRoot then
			lastSeen = now
			local phase = model:GetAttribute("Phase")
			if phase == "Awakened" or phase == "Waiting for a challenger" or phase == "Returning to its arena" then
				setPhase(model, def, "Engaged")
			end
			if not model:GetAttribute("Casting") then
				local available = {}
				if now >= nextAbility then
					for index, ability in ipairs(def.abilities or {}) do
						local abilityId = tostring(index) .. ":" .. tostring(ability.kind)
						local ready = now - (abilityLast[abilityId] or -math.huge) >= (ability.cooldown or 8)
						if ready and ability.kind == "summon" then
							local system = GameConfig.BOSS_SYSTEM or {}
							local maxAlive = ability.maxAlive or system.maxSummonsPerBoss or 4
							local summonCooldown = ability.summonCooldown or ability.cooldown or system.summonCooldown or 18
							ready = countBossMinions(def.key) < maxAlive
								and now - (summonLastAt[model] or -math.huge) >= summonCooldown
						end
						if ready then
							table.insert(available, { id = abilityId, ability = ability })
						end
					end
				end
				if #available > 0 then
					local selected = available[math.random(1, #available)]
					abilityLast[selected.id] = now
					nextAbility = now + globalAbilityCooldown
					task.spawn(castAbility, model, def, selected.ability)
				elseif distance <= (def.attackRange or 7) then
					if now - lastBasic >= (def.attackCooldown or 1.3) then
						lastBasic = now
						MonsterService.DamagePlayer(player, def.damage or 1, model)
					end
				else
					local target = targetRoot.Position
					local flat = Vector3.new(target.X, root.Position.Y, target.Z)
					local delta = flat - root.Position
					if delta.Magnitude > 0.1 then
						local step = delta.Unit * math.min((def.moveSpeed or 7) * dt, delta.Magnitude)
						local nextPos = root.Position + step
						root.CFrame = CFrame.lookAt(nextPos, nextPos + Vector3.new(delta.X, 0, delta.Z))
					end
				end
			end
		elseif now - lastSeen >= (def.resetDelay or 10) and not model:GetAttribute("Casting") then
			local resetDistance = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
			if resetDistance > 2 or (model:GetAttribute("Health") or 0) < def.hp then
				setPhase(model, def, "Returning to its arena")
				clearBossMinions(def.key)
				summonLastAt[model] = nil
				local grounded = groundPoint(origin)
				local height = 1.15 * (def.scale or 2)
				root.CFrame = CFrame.new(grounded + Vector3.new(0, height, 0))
				model:SetAttribute("Health", def.hp)
				model:SetAttribute("DamageReduction", 0)
				model:SetAttribute("ArmorBreakUntil", nil)
				model:SetAttribute("ArmorBreakReductionMultiplier", nil)
				contributors[model] = {}
				updateNameplate(model)
				setPhase(model, def, "Waiting for a challenger")
			end
			lastSeen = now
		end
	end

	if activeByZone[def.zone] == model then
		activeByZone[def.zone] = nil
		contributors[model] = nil
		summonLastAt[model] = nil
		clearBossMinions(def.key)
		scheduleRespawn(def.zone)
	end
end

spawnBoss = function(zone: string, position: Vector3, owner: Player?): Model?
	if activeByZone[zone] then
		return activeByZone[zone]
	end
	local def = bossByZone[zone]
	if not def or not monsterFolder then
		return nil
	end
	clearBossMinions(def.key)
	local model = buildBoss(def, position)
	model:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	model:SetAttribute("Phase", "Awakened")
	model.Parent = monsterFolder
	activeByZone[zone] = model
	contributors[model] = {}
	spawnOrigins[zone] = position
	if owner then
		spawnOwners[zone] = owner
	end
	broadcast(model, def, "spawn", "Awakened")
	task.spawn(runBoss, model, def, position)
	print(string.format("[BossService] %s awakened in %s.", def.name, zone))
	return model
end

local function killBoss(model: Model, def: any, finalPlayer: Player?)
	if model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("Dead", true)
	model:SetAttribute("Casting", false)
	model:SetAttribute("Health", 0)
	updateNameplate(model)

	local rewarded = contributors[model] or {}
	if finalPlayer then
		rewarded[finalPlayer] = true
	end
	for player in pairs(rewarded) do
		if player.Parent and PlayerDataService.Get(player) then
			PlayerDataService.GrantCurrency(player, def.goldReward or 0, def.diamondReward or 0)
			if def.essenceKey and (def.essenceReward or 0) > 0 then
				PlayerDataService.GrantEssence(player, def.essenceKey, def.essenceReward)
			end
			local count, firstKill = PlayerDataService.RecordBossDefeat(player, def.key)
			if QuestService and typeof(QuestService.ReportBossDefeated) == "function" then
				QuestService.ReportBossDefeated(player, def.name, def.zone)
			end
			local essenceMeta = if def.essenceKey then GameConfig.ESSENCE[def.essenceKey] else nil
			Remotes.Get("BossDefeated"):FireClient(player, {
				key = def.key,
				name = def.name,
				zone = def.zone,
				gold = def.goldReward or 0,
				diamonds = def.diamondReward or 0,
				essence = def.essenceReward or 0,
				essenceName = if essenceMeta then essenceMeta.name else "",
				killCount = count,
				firstKill = firstKill,
			})
		end
	end

	if activeByZone[def.zone] == model then
		activeByZone[def.zone] = nil
	end
	contributors[model] = nil
	summonLastAt[model] = nil
	clearBossMinions(def.key)
	Remotes.Get("BossState"):FireAllClients({ action = "defeated", key = def.key, name = def.name, zone = def.zone, model = model })
	Debris:AddItem(model, 0.8)
	scheduleRespawn(def.zone)
end

function BossService.DamageBoss(model: Model, rawDamage: number, player: Player, trueDamage: boolean?): boolean
	if not model or not model.Parent or model:GetAttribute("Dead") then
		return false
	end
	local key = model:GetAttribute("BossKey")
	local def = if type(key) == "string" then bossByKey[key] else nil
	if not def then
		return false
	end
	local health = model:GetAttribute("Health") or 0
	if health <= 0 then
		return false
	end
	local damage = math.max(0, tonumber(rawDamage) or 0)
	if not trueDamage then
		local reduction = math.clamp(model:GetAttribute("DamageReduction") or 0, 0, 0.9)
		if (model:GetAttribute("ArmorBreakUntil") or 0) > os.clock() then
			reduction *= model:GetAttribute("ArmorBreakReductionMultiplier") or 0.4
		end
		damage *= (1 - reduction)
	end
	damage = math.max(1, math.floor(damage + 0.5))
	local newHealth = math.max(0, health - damage)
	model:SetAttribute("Health", newHealth)
	contributors[model] = contributors[model] or {}
	contributors[model][player] = true
	updateNameplate(model)
	local root = model.PrimaryPart
	if root then
		Remotes.Get("MonsterHit"):FireClient(player, root.Position + Vector3.new(0, 4, 0), damage, newHealth <= 0)
	end
	broadcast(model, def, "update", model:GetAttribute("Phase") or "Engaged")
	if newHealth <= 0 then
		killBoss(model, def, player)
	end
	return true
end

-- Called once by GrassService when the final tile in a ring is removed.
function BossService.OnZoneCleared(player: Player, position: Vector3, zoneIndex: number)
	local zone = ZONE_KEY_BY_INDEX[zoneIndex]
	if not zone or not bossByZone[zone] then
		return
	end
	unlockedZones[zone] = true
	spawnOrigins[zone] = position
	spawnOwners[zone] = player
	respawnGeneration[zone] = (respawnGeneration[zone] or 0) + 1
	spawnBoss(zone, position, player)
end

-- Studio-only spawn hook for focused testing without clearing a ring. It is also
-- exposed through DebugSpawnBoss, so testing never depends on Command Bar context
-- or the exact ServerScriptService hierarchy.
function BossService.SpawnForStudio(player: Player, zone: string, testHealth: number?): boolean
	if not RunService:IsStudio() or not bossByZone[zone] then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local position = root.Position + root.CFrame.LookVector * 24
	-- Match normal progression: clearing a ring reaches it before awakening its boss.
	local profile = PlayerDataService.Get(player)
	if profile then
		profile.quests = profile.quests or { progress = {}, claimed = {}, reached = {} }
		profile.quests.reached = profile.quests.reached or {}
		profile.quests.reached[zone] = true
		PlayerDataService.PushState(player)
		MonsterService.ApplyMaxHP(player)
		if QuestService and typeof(QuestService.PushState) == "function" then
			QuestService.PushState(player)
		end
	end
	unlockedZones[zone] = true
	spawnOrigins[zone] = position
	spawnOwners[zone] = player
	local existing = activeByZone[zone]
	if existing then
		contributors[existing] = nil
		summonLastAt[existing] = nil
		clearBossMinions(existing:GetAttribute("BossKey") or zone)
		activeByZone[zone] = nil
		existing:Destroy()
	end
	local spawned = spawnBoss(zone, position, player)
	if spawned and testHealth and testHealth > 0 then
		local health = math.max(1, math.floor(testHealth))
		spawned:SetAttribute("MaxHealth", health)
		spawned:SetAttribute("Health", health)
		updateNameplate(spawned)
		local def = bossByZone[zone]
		if def then
			broadcast(spawned, def, "update", "Studio test")
		end
	end
	return spawned ~= nil
end

function BossService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	MonsterService = services.MonsterService
	for _, def in ipairs(GameConfig.BOSSES or {}) do
		bossByKey[def.key] = def
		bossByZone[def.zone] = def
	end
end

function BossService.Start()
	-- BossService and MonsterService start concurrently. Reconcile one shared folder
	-- instead of waiting on start order or accidentally binding to a duplicate.
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

	Remotes.Get("DebugSpawnBoss").OnServerEvent:Connect(function(player: Player, rawZone: unknown, rawHealth: unknown)
		if not RunService:IsStudio() then
			return -- never expose debug spawning in a published/live server
		end
		if type(rawZone) ~= "string" or not bossByZone[rawZone] then
			Remotes.Get("BossDebugResult"):FireClient(player, false, "Unknown boss zone: " .. tostring(rawZone))
			return
		end
		local health: number? = nil
		if type(rawHealth) == "number" then
			health = math.clamp(math.floor(rawHealth), 1, 1000000)
		end
		local ok, result = pcall(BossService.SpawnForStudio, player, rawZone, health)
		if not ok then
			warn("[BossService] Studio spawn failed: " .. tostring(result))
			Remotes.Get("BossDebugResult"):FireClient(player, false, "Boss spawn failed; check Server Output.")
			return
		end
		if result then
			local def = bossByZone[rawZone]
			local suffix = if health then " with " .. tostring(health) .. " HP" else ""
			Remotes.Get("BossDebugResult"):FireClient(player, true, "Spawned " .. def.name .. suffix .. ".")
		else
			Remotes.Get("BossDebugResult"):FireClient(player, false, "Boss could not spawn; make sure your character is alive.")
		end
	end)

	Remotes.Get("RequestBossState").OnServerEvent:Connect(function(player: Player)
		for zone, model in activeByZone do
			local def = bossByZone[zone]
			if def and model.Parent and not model:GetAttribute("Dead") then
				Remotes.Get("BossState"):FireClient(player, bossPayload(model, def, "spawn", model:GetAttribute("Phase")))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, set in contributors do
			set[player] = nil
		end
		for zone, owner in spawnOwners do
			if owner == player then
				spawnOwners[zone] = nil
			end
		end
	end)
	ReplicatedStorage:SetAttribute("BossServiceStatus", "Ready")
	print("[BossService] five-ring boss framework ready. Studio testing: DebugSpawnBoss remote is available.")
end

return BossService

--!strict
-- VillagerService: builds one trapped neighbor in every ring. Rescues are
-- server-authoritative, persistent, quest-aware, and unlock immediate stat perks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local VillagerService = {}

local PlayerDataService: any
local QuestService: any
local PetService: any
local defByKey: { [string]: any } = {}
local requestTimes: { [Player]: number } = {}

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function isReached(profile: any, zone: string): boolean
	if zone == "Meadow" then
		return true
	end
	return profile.quests and profile.quests.reached and profile.quests.reached[zone] == true
end

local function stateFor(player: Player, message: string?): any
	local profile = PlayerDataService.Get(player)
	if not profile then
		return { loading = true, rows = {}, message = message }
	end
	local villagers = profile.villagers or { rescued = {}, features = {} }
	local rows = {}
	for _, def in ipairs(GameConfig.VILLAGERS or {}) do
		table.insert(rows, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			feature = def.feature,
			desc = def.desc,
			bonus = def.bonus,
			reached = isReached(profile, def.zone),
			rescued = villagers.rescued[def.key] == true,
		})
	end
	return {
		rows = rows,
		bonuses = PlayerDataService.GetVillagerBonuses(profile),
		rescuedCount = (function()
			local count = 0
			for _, row in rows do
				if row.rescued then count += 1 end
			end
			return count
		end)(),
		message = message,
	}
end

function VillagerService.PushState(player: Player, message: string?, shouldOpen: boolean?)
	Remotes.Get("VillagerState"):FireClient(player, stateFor(player, message))
	if shouldOpen then
		Remotes.Get("OpenVillagerMenu"):FireClient(player)
	end
end

local function rescue(player: Player, def: any)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	if not isReached(profile, def.zone) then
		VillagerService.PushState(player, "Reach " .. def.zone .. " before attempting this rescue.", true)
		return
	end
	profile.villagers = profile.villagers or { rescued = {}, features = {} }
	profile.villagers.rescued = profile.villagers.rescued or {}
	profile.villagers.features = profile.villagers.features or {}
	if profile.villagers.rescued[def.key] then
		VillagerService.PushState(player, def.name .. " is already safe. " .. def.feature .. " remains active.", true)
		return
	end
	profile.villagers.rescued[def.key] = true
	profile.villagers.features[def.feature] = true
	if QuestService and typeof(QuestService.ReportVillagerRescue) == "function" then
		QuestService.ReportVillagerRescue(player, def.name)
	end
	if PetService and typeof(PetService.RefreshPlayer) == "function" then
		PetService.RefreshPlayer(player, def.feature .. " unlocked!")
	else
		PlayerDataService.PushState(player)
	end
	VillagerService.PushState(player, "Rescued " .. def.name .. ". Permanent perk unlocked: " .. def.feature .. ".", true)
end

local function zonePart(zone: string): BasePart?
	local exact = Workspace:FindFirstChild("Zone_" .. zone, true)
	if exact and exact:IsA("BasePart") then
		return exact
	end
	local best: BasePart? = nil
	local bestArea = 0
	for _, value in Workspace:GetDescendants() do
		if value:IsA("BasePart") then
			local tagged = value:GetAttribute("GrassType") == zone
				or value:GetAttribute("Zone") == zone
				or value:GetAttribute("ZoneKey") == zone
			if tagged then
				local area = value.Size.X * value.Size.Z
				if area > bestArea then
					best = value
					bestArea = area
				end
			end
		end
	end
	return best
end

local function groundAt(position: Vector3, ignore: Instance): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position else position
end

local function npcPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, tint: Color3, material: Enum.Material?): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.CFrame = cframe
	value.Color = tint
	value.Material = material or Enum.Material.SmoothPlastic
	value.Anchored = true
	value.CanCollide = name == "Torso" or name == "CageFloor"
	value.CanQuery = true
	value.CanTouch = false
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.Parent = parent
	return value
end

local function buildVillager(parent: Instance, def: any, index: number)
	local anchor = zonePart(def.zone)
	local seed = if anchor then anchor.Position else GameConfig.QUEST_GIVER_POSITION + Vector3.new(index * 9, 0, 22)
	if anchor then
		local right = math.clamp(anchor.Size.X * 0.33, 5, 22)
		local forward = math.clamp(anchor.Size.Z * 0.31, 5, 22)
		seed = anchor.Position + anchor.CFrame.RightVector * right + anchor.CFrame.LookVector * forward
	end
	local ground = groundAt(seed, parent)
	local origin = CFrame.new(ground + Vector3.new(0, 3.1, 0)) * CFrame.Angles(0, math.rad(180 - index * 17), 0)
	local model = Instance.new("Model")
	model.Name = "Trapped_" .. def.key
	model:SetAttribute("VillagerKey", def.key)
	model:SetAttribute("Zone", def.zone)
	model.Parent = parent
	local body = color(def.bodyColor)
	local accent = color(def.accentColor)
	local torso = npcPart(model, "Torso", Vector3.new(2.5, 3.1, 1.45), origin, body)
	npcPart(model, "Head", Vector3.new(2, 2, 2), origin * CFrame.new(0, 2.55, 0), Color3.fromRGB(224, 181, 143))
	npcPart(model, "Hat", Vector3.new(2.6, 0.55, 2.6), origin * CFrame.new(0, 3.55, 0), accent)
	npcPart(model, "LeftLeg", Vector3.new(0.85, 2.2, 0.9), origin * CFrame.new(-0.72, -2.55, 0), Color3.fromRGB(62, 66, 73))
	npcPart(model, "RightLeg", Vector3.new(0.85, 2.2, 0.9), origin * CFrame.new(0.72, -2.55, 0), Color3.fromRGB(62, 66, 73))
	local cageColor = Color3.fromRGB(92, 98, 108)
	npcPart(model, "CageFloor", Vector3.new(7, 0.5, 7), CFrame.new(ground + Vector3.new(0, 0.25, 0)), Color3.fromRGB(69, 72, 80), Enum.Material.Metal)
	for _, x in { -3.1, 3.1 } do
		for _, z in { -3.1, 0, 3.1 } do
			npcPart(model, "CageBar", Vector3.new(0.28, 7, 0.28), CFrame.new(ground + Vector3.new(x, 3.5, z)), cageColor, Enum.Material.Metal)
		end
	end
	for _, z in { -3.1, 3.1 } do
		for _, x in { -1.55, 0, 1.55 } do
			npcPart(model, "CageBar", Vector3.new(0.28, 7, 0.28), CFrame.new(ground + Vector3.new(x, 3.5, z)), cageColor, Enum.Material.Metal)
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ActionText = "Rescue"
	prompt.ObjectText = def.name .. " - " .. def.feature
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = torso
	prompt.Triggered:Connect(function(player: Player)
		rescue(player, def)
	end)
	local sign = Instance.new("BillboardGui")
	sign.Name = "VillagerName"
	sign.Adornee = torso
	sign.AlwaysOnTop = true
	sign.MaxDistance = 85
	sign.StudsOffsetWorldSpace = Vector3.new(0, 5.3, 0)
	sign.Size = UDim2.fromOffset(260, 62)
	sign.Parent = torso
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(31, 38, 39)
	label.BackgroundTransparency = 0.18
	label.Font = Enum.Font.FredokaOne
	label.Text = def.name .. "\n" .. def.zone .. " rescue"
	label.TextColor3 = Color3.fromRGB(255, 250, 218)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.58
	label.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 11)
	corner.Parent = label
end

local function buildWorld()
	local previous = Workspace:FindFirstChild("RescueVillagers")
	if previous then previous:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "RescueVillagers"
	folder.Parent = Workspace
	for index, def in ipairs(GameConfig.VILLAGERS or {}) do
		buildVillager(folder, def, index)
	end
	print("[VillagerService] five persistent neighbor rescues and perks ready.")
end

function VillagerService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	PetService = services.PetService
	for _, def in ipairs(GameConfig.VILLAGERS or {}) do
		defByKey[def.key] = def
	end
end

function VillagerService.Start()
	Remotes.Get("RequestVillagers").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (requestTimes[player] or -math.huge) < 0.25 then return end
		requestTimes[player] = now
		VillagerService.PushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		requestTimes[player] = nil
	end)
	task.delay(3, buildWorld)
end

return VillagerService

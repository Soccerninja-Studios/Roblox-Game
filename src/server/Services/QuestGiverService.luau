--!strict
-- QuestGiverService: spawns "Sprig the Quartermaster", the quest board post that
-- stands at the front-center of the house (between the shop and the gardener).
-- There is no hand-authored Sprig model yet, so this builds a tidy quest kiosk in
-- code: a wooden post, a glowing walk-in pad, a floating "!" marker, a signboard
-- reading "QUESTS", and a ProximityPrompt the client hooks to open the board.
-- Swap in a real NPC model later by cloning it over Workspace.QuestGiver and
-- keeping the QuestPrompt + QuestZone parts.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local QuestGiverService = {}

local POST_COLOR = Color3.fromRGB(122, 84, 52)
local BOARD_COLOR = Color3.fromRGB(158, 116, 74)
local ZONE_FILL = Color3.fromRGB(250, 208, 96) -- warm gold to stand apart from shop/gardener
local ZONE_EDGE = Color3.fromRGB(214, 164, 58)
local ACCENT = Color3.fromRGB(255, 226, 150)

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	return p
end

-- Slow transparency pulse so the walk-in pad reads as interactive.
local function pulse(zone: BasePart)
	task.spawn(function()
		while zone.Parent do
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.72 }):Play()
			task.wait(1.1)
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.42 }):Play()
			task.wait(1.1)
		end
	end)
end

local function buildKiosk(): Model
	local model = Instance.new("Model")
	model.Name = "QuestGiver"

	-- Ground pad the player walks onto (glowing gold disc).
	local zone = makePart("QuestZone", Vector3.new(GameConfig.QUEST_GIVER_ZONE_RADIUS * 2, 0.2, GameConfig.QUEST_GIVER_ZONE_RADIUS * 2), ZONE_FILL, Enum.Material.Neon)
	zone.Shape = Enum.PartType.Cylinder
	zone.Transparency = 0.5
	-- Cylinder parts lie on their side; rotate so the flat face points up.
	zone.CFrame = CFrame.new(GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Parent = model

	local ring = makePart("QuestZoneRing", Vector3.new(GameConfig.QUEST_GIVER_ZONE_RADIUS * 2 + 1.2, 0.3, GameConfig.QUEST_GIVER_ZONE_RADIUS * 2 + 1.2), ZONE_EDGE, Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	-- Wooden post.
	local post = makePart("Post", Vector3.new(0.6, 6, 0.6), POST_COLOR, Enum.Material.Wood)
	post.CanCollide = true
	post.Position = GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 3, 0)
	post.Parent = model

	-- Signboard on top of the post.
	local board = makePart("Board", Vector3.new(6, 3.4, 0.35), BOARD_COLOR, Enum.Material.WoodPlanks)
	board.Position = GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 6.6, 0)
	board.Parent = model

	local frame = makePart("BoardFrame", Vector3.new(6.5, 3.9, 0.2), ACCENT, Enum.Material.SmoothPlastic)
	frame.Position = board.Position + Vector3.new(0, 0, -0.12)
	frame.Parent = model

	-- Sign text on the front face.
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SignGui"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(600, 340)
	surface.Parent = board

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.5, 0)
	title.Position = UDim2.new(0, 0, 0.08, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "QUESTS"
	title.TextColor3 = Color3.fromRGB(60, 40, 24)
	title.TextScaled = true
	title.Parent = surface

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0.28, 0)
	subtitle.Position = UDim2.new(0, 0, 0.62, 0)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "Sprig the Quartermaster"
	subtitle.TextColor3 = Color3.fromRGB(80, 56, 34)
	subtitle.TextScaled = true
	subtitle.Parent = surface

	-- Floating "!" quest marker above the board.
	local markerAnchor = makePart("MarkerAnchor", Vector3.new(0.2, 0.2, 0.2), ACCENT, Enum.Material.Neon)
	markerAnchor.Transparency = 1
	markerAnchor.Position = board.Position + Vector3.new(0, 3, 0)
	markerAnchor.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Marker"
	billboard.Size = UDim2.new(0, 60, 0, 90)
	billboard.AlwaysOnTop = true
	billboard.Parent = markerAnchor

	local bang = Instance.new("TextLabel")
	bang.BackgroundTransparency = 1
	bang.Size = UDim2.new(1, 0, 1, 0)
	bang.Font = Enum.Font.FredokaOne
	bang.Text = "!"
	bang.TextColor3 = ACCENT
	bang.TextStrokeTransparency = 0.3
	bang.TextScaled = true
	bang.Parent = billboard

	-- Proximity prompt the client hooks to open the quest board.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QuestPrompt"
	prompt.ActionText = "Quests"
	prompt.ObjectText = "Sprig the Quartermaster"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = GameConfig.QUEST_GIVER_ZONE_RADIUS + 4
	prompt.Parent = post

	model.PrimaryPart = post
	pulse(zone)
	return model
end

local function spawnQuestGiver()
	local existing = Workspace:FindFirstChild("QuestGiver")
	if existing then
		existing:Destroy()
	end
	local model = buildKiosk()
	model.Parent = Workspace
end

function QuestGiverService.Init(_services: any) end

function QuestGiverService.Start()
	spawnQuestGiver()
	print("[QuestGiverService] Sprig the Quartermaster is ready.")
end

return QuestGiverService

--!strict
-- EffectsController: juicy client-side feedback.
--   TileCut          -> a burst of grass bits where a swing lands
--   ClippingCollected-> a floating "+N" popup when a dropped clipping is vacuumed up
--   GrassTooTough    -> a red "Too tough!" popup + small camera shake

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EffectsController = {}

local player = Players.LocalPlayer

local function grassColor(typeName: string): Color3
	local def = GameConfig.GRASS_TYPES[typeName] or GameConfig.GRASS_TYPES[GameConfig.DEFAULT_GRASS_TYPE]
	return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
end

-- Floating text that rises and fades.
local function floatingText(position: Vector3, text: string, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(big and 5 or 3.4, big and 2 or 1.4)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(30, 40, 25)
	stroke.Parent = label
	label.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame * CFrame.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()

	Debris:AddItem(anchor, 0.85)
end

-- A short-lived particle burst of grass bits.
local function grassBurst(position: Vector3, color: Color3)
	local emitter = Instance.new("Part")
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.Transparency = 1
	emitter.Size = Vector3.one
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = workspace

	local particle = Instance.new("ParticleEmitter")
	particle.Color = ColorSequence.new(color)
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Lifetime = NumberRange.new(0.3, 0.5)
	particle.Speed = NumberRange.new(6, 10)
	particle.SpreadAngle = Vector2.new(180, 180)
	particle.Rotation = NumberRange.new(0, 360)
	particle.Size = NumberSequence.new(0.5, 0)
	particle.Acceleration = Vector3.new(0, -20, 0)
	particle.Enabled = false
	particle.Parent = emitter
	particle:Emit(10)

	Debris:AddItem(emitter, 1)
end

local function cameraShake(intensity: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		if elapsed >= 0.25 then
			humanoid.CameraOffset = Vector3.zero
			conn:Disconnect()
			return
		end
		local falloff = intensity * (1 - elapsed / 0.25)
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * falloff,
			(math.random() - 0.5) * falloff,
			0
		)
	end)
end

function EffectsController.Init() end

function EffectsController.Start()
	Remotes.Get("TileCut").OnClientEvent:Connect(function(position: Vector3, grassType: string)
		grassBurst(position, grassColor(grassType))
	end)

	-- "+N clippings" pickup popups now render on the HUD in the upper half of the
	-- screen (see UIController). The world-space grass burst on each swing (TileCut)
	-- and the "Too tough!" popup below stay here.

	Remotes.Get("GrassTooTough").OnClientEvent:Connect(function(position: Vector3, _grassType: string)
		floatingText(position, "Too tough!", Color3.fromRGB(255, 110, 90), false)
		cameraShake(1.2)
	end)
end

return EffectsController

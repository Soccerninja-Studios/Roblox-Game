--!strict
-- CombatController: the combat HUD. Draws the player's health bar, floats damage
-- numbers over monsters you hit, flashes the screen when you take a hit, and shows
-- the "your clippings scattered" banner on death (plus a recovered confirmation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CombatController = {}

local player = Players.LocalPlayer

local gui: ScreenGui
local hpBarFill: Frame
local hpLabel: TextLabel
local flash: Frame
local banner: TextLabel

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Parent = player:WaitForChild("PlayerGui")

	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(200, 40, 30)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 2
	flash.Parent = gui

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -14)
	holder.Size = UDim2.fromOffset(240, 26)
	holder.BackgroundColor3 = Color3.fromRGB(40, 44, 40)
	holder.BackgroundTransparency = 0.15
	holder.ZIndex = 5
	holder.Parent = gui
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 13)
	hc.Parent = holder

	hpBarFill = Instance.new("Frame")
	hpBarFill.Position = UDim2.fromOffset(3, 3)
	hpBarFill.Size = UDim2.new(1, -6, 1, -6)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
	hpBarFill.BorderSizePixel = 0
	hpBarFill.ZIndex = 6
	hpBarFill.Parent = holder
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 11)
	fc.Parent = hpBarFill

	hpLabel = Instance.new("TextLabel")
	hpLabel.BackgroundTransparency = 1
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.Font = Enum.Font.FredokaOne
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextStrokeTransparency = 0.4
	hpLabel.TextSize = 16
	hpLabel.Text = ""
	hpLabel.ZIndex = 7
	hpLabel.Parent = holder

	banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 90)
	banner.Size = UDim2.fromOffset(560, 40)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.FredokaOne
	banner.TextColor3 = Color3.fromRGB(255, 235, 120)
	banner.TextStrokeTransparency = 0.3
	banner.TextSize = 22
	banner.Text = ""
	banner.TextTransparency = 1
	banner.ZIndex = 8
	banner.Parent = gui
end

local function updateHealth()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local frac = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
	TweenService:Create(hpBarFill, TweenInfo.new(0.15), { Size = UDim2.new(frac, -6, 1, -6) }):Play()
	hpBarFill.BackgroundColor3 = if frac > 0.5
		then Color3.fromRGB(90, 200, 90)
		elseif frac > 0.25 then Color3.fromRGB(235, 190, 70)
		else Color3.fromRGB(220, 70, 60)
	hpLabel.Text = math.ceil(hum.Health) .. " / " .. math.ceil(hum.MaxHealth)
end

local function hookCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	updateHealth()
	hum.HealthChanged:Connect(updateHealth)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
end

local function showBanner(text: string, color: Color3, hold: number)
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	task.delay(hold, function()
		TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	end)
end

local function floatDamage(worldPos: Vector3, amount: number, isKill: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = worldPos
	anchor.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(80, 40)
	bb.AlwaysOnTop = true
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = if isKill then Color3.fromRGB(255, 210, 90) else Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.35
	label.TextSize = if isKill then 26 else 20
	label.Text = "-" .. amount
	label.Parent = bb

	TweenService:Create(anchor, TweenInfo.new(0.7), { Position = worldPos + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

function CombatController.Init()
	buildGui()

	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)

	Remotes.Get("MonsterHit").OnClientEvent:Connect(function(worldPos, amount, isKill)
		floatDamage(worldPos, amount, isKill)
	end)

	Remotes.Get("PlayerHurt").OnClientEvent:Connect(function(_amount)
		flash.BackgroundTransparency = 0.5
		TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end)

	Remotes.Get("ClippingsScattered").OnClientEvent:Connect(function(amount)
		if amount and amount > 0 then
			showBanner("\u{1F4A5} Your clippings scattered! Run back to recover them.", Color3.fromRGB(255, 180, 90), 5)
		end
	end)

	Remotes.Get("ClippingsRecovered").OnClientEvent:Connect(function(amount)
		showBanner("\u{1F33F} Recovered " .. tostring(amount) .. " clippings!", Color3.fromRGB(150, 235, 120), 3)
	end)

	Remotes.Get("MonsterDefeated").OnClientEvent:Connect(function(name, gold)
		showBanner("\u{2694}\u{FE0F} Defeated " .. tostring(name) .. "  +" .. tostring(gold) .. "g", Color3.fromRGB(255, 235, 120), 2)
	end)
end

function CombatController.Start() end

return CombatController

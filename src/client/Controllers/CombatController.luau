--!strict
-- CombatController: player health, hit feedback, recoverable-clipping notices,
-- common-monster rewards, and the complete proximity-aware boss HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CombatController = {}

local player = Players.LocalPlayer

local gui: ScreenGui
local hpBarFill: Frame
local hpLabel: TextLabel
local flash: Frame
local banner: TextLabel
local bossHolder: Frame
local bossTitle: TextLabel
local bossPhase: TextLabel
local bossFill: Frame
local bossHealth: TextLabel

local bossStates: { [string]: any } = {}
local bannerToken = 0

local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function colorFromArray(rgb: any, fallback: Color3): Color3
	if type(rgb) == "table" and type(rgb[1]) == "number" and type(rgb[2]) == "number" and type(rgb[3]) == "number" then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return fallback
end

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

	-- Player health remains low and centered so it never competes with the boss bar.
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -14)
	holder.Size = UDim2.fromOffset(240, 26)
	holder.BackgroundColor3 = Color3.fromRGB(40, 44, 40)
	holder.BackgroundTransparency = 0.15
	holder.BorderSizePixel = 0
	holder.ZIndex = 5
	holder.Parent = gui
	corner(holder, 13)

	hpBarFill = Instance.new("Frame")
	hpBarFill.Position = UDim2.fromOffset(3, 3)
	hpBarFill.Size = UDim2.new(1, -6, 1, -6)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
	hpBarFill.BorderSizePixel = 0
	hpBarFill.ZIndex = 6
	hpBarFill.Parent = holder
	corner(hpBarFill, 11)

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

	-- Boss bar appears only for the closest active boss within the configured range.
	bossHolder = Instance.new("Frame")
	bossHolder.AnchorPoint = Vector2.new(0.5, 0)
	bossHolder.Position = UDim2.new(0.5, 0, 0, 52)
	bossHolder.Size = UDim2.fromOffset(520, 72)
	bossHolder.BackgroundColor3 = Color3.fromRGB(34, 32, 37)
	bossHolder.BackgroundTransparency = 0.08
	bossHolder.BorderSizePixel = 0
	bossHolder.Visible = false
	bossHolder.ZIndex = 20
	bossHolder.Parent = gui
	corner(bossHolder, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(244, 220, 142)
	stroke.Transparency = 0.2
	stroke.Thickness = 2
	stroke.Parent = bossHolder

	bossTitle = Instance.new("TextLabel")
	bossTitle.BackgroundTransparency = 1
	bossTitle.Position = UDim2.fromOffset(14, 5)
	bossTitle.Size = UDim2.new(0.64, -14, 0, 24)
	bossTitle.Font = Enum.Font.FredokaOne
	bossTitle.TextColor3 = Color3.fromRGB(255, 240, 180)
	bossTitle.TextSize = 20
	bossTitle.TextXAlignment = Enum.TextXAlignment.Left
	bossTitle.Text = ""
	bossTitle.ZIndex = 22
	bossTitle.Parent = bossHolder

	bossPhase = Instance.new("TextLabel")
	bossPhase.BackgroundTransparency = 1
	bossPhase.AnchorPoint = Vector2.new(1, 0)
	bossPhase.Position = UDim2.new(1, -14, 0, 8)
	bossPhase.Size = UDim2.new(0.36, -8, 0, 18)
	bossPhase.Font = Enum.Font.GothamBold
	bossPhase.TextColor3 = Color3.fromRGB(204, 210, 198)
	bossPhase.TextSize = 12
	bossPhase.TextXAlignment = Enum.TextXAlignment.Right
	bossPhase.TextTruncate = Enum.TextTruncate.AtEnd
	bossPhase.Text = ""
	bossPhase.ZIndex = 22
	bossPhase.Parent = bossHolder

	local bossBar = Instance.new("Frame")
	bossBar.Position = UDim2.fromOffset(14, 36)
	bossBar.Size = UDim2.new(1, -28, 0, 23)
	bossBar.BackgroundColor3 = Color3.fromRGB(58, 51, 58)
	bossBar.BorderSizePixel = 0
	bossBar.ClipsDescendants = true
	bossBar.ZIndex = 21
	bossBar.Parent = bossHolder
	corner(bossBar, 10)

	bossFill = Instance.new("Frame")
	bossFill.Size = UDim2.fromScale(1, 1)
	bossFill.BackgroundColor3 = Color3.fromRGB(218, 84, 76)
	bossFill.BorderSizePixel = 0
	bossFill.ZIndex = 22
	bossFill.Parent = bossBar
	corner(bossFill, 10)

	bossHealth = Instance.new("TextLabel")
	bossHealth.BackgroundTransparency = 1
	bossHealth.Size = UDim2.fromScale(1, 1)
	bossHealth.Font = Enum.Font.FredokaOne
	bossHealth.TextColor3 = Color3.fromRGB(255, 255, 255)
	bossHealth.TextStrokeTransparency = 0.35
	bossHealth.TextSize = 14
	bossHealth.Text = ""
	bossHealth.ZIndex = 23
	bossHealth.Parent = bossBar

	banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 140)
	banner.Size = UDim2.fromOffset(640, 44)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.FredokaOne
	banner.TextColor3 = Color3.fromRGB(255, 235, 120)
	banner.TextStrokeTransparency = 0.3
	banner.TextSize = 22
	banner.Text = ""
	banner.TextTransparency = 1
	banner.TextWrapped = true
	banner.ZIndex = 24
	banner.Parent = gui
end

local function updateHealth()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local frac = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
	TweenService:Create(hpBarFill, TweenInfo.new(0.15), { Size = UDim2.new(frac, -6 * frac, 1, -6) }):Play()
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
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	task.delay(hold, function()
		if token == bannerToken then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
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
	bb.Size = UDim2.fromOffset(90, 40)
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

local function closestBoss(): any
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local limit = (GameConfig.BOSS_SYSTEM and GameConfig.BOSS_SYSTEM.hudRange) or 260
	local best = nil
	local bestDistance = limit
	for key, state in bossStates do
		local model = state.model
		if model and model:IsA("Model") and model.Parent and model.PrimaryPart and not model:GetAttribute("Dead") then
			local distance = (model.PrimaryPart.Position - root.Position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				best = state
			end
		else
			bossStates[key] = nil
		end
	end
	return best
end

local function updateBossHud()
	local state = closestBoss()
	if not state then
		bossHolder.Visible = false
		return
	end
	local model = state.model :: Model
	local hp = model:GetAttribute("Health") or state.health or 0
	local maxHealth = model:GetAttribute("MaxHealth") or state.maxHealth or 1
	local fraction = math.clamp(hp / math.max(1, maxHealth), 0, 1)
	bossHolder.Visible = true
	bossTitle.Text = tostring(state.name) .. "  •  " .. tostring(state.zone)
	bossPhase.Text = tostring(model:GetAttribute("Phase") or state.phase or "Engaged")
	bossHealth.Text = string.format("%s / %s", tostring(math.ceil(hp)), tostring(math.ceil(maxHealth)))
	bossFill.BackgroundColor3 = colorFromArray(state.color, Color3.fromRGB(218, 84, 76))
	bossFill.Size = UDim2.fromScale(fraction, 1)
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
			showBanner("💥 Your clippings scattered! Run back to recover them.", Color3.fromRGB(255, 180, 90), 5)
		end
	end)

	Remotes.Get("ClippingsRecovered").OnClientEvent:Connect(function(amount)
		showBanner("🌿 Recovered " .. tostring(amount) .. " clippings!", Color3.fromRGB(150, 235, 120), 3)
	end)

	Remotes.Get("MonsterDefeated").OnClientEvent:Connect(function(name, gold, essenceName, essenceAmount)
		local rewards = {}
		if (gold or 0) > 0 then
			table.insert(rewards, "+" .. tostring(gold) .. "g")
		end
		if (essenceAmount or 0) > 0 and essenceName and essenceName ~= "" then
			table.insert(rewards, "+" .. tostring(essenceAmount) .. " " .. tostring(essenceName))
		end
		local suffix = if #rewards > 0 then "  " .. table.concat(rewards, "  ") else ""
		showBanner("⚔️ Defeated " .. tostring(name) .. suffix, Color3.fromRGB(255, 235, 120), 2.5)
	end)

	Remotes.Get("BossState").OnClientEvent:Connect(function(state)
		if type(state) ~= "table" or type(state.key) ~= "string" then
			return
		end
		if state.action == "defeated" then
			bossStates[state.key] = nil
			updateBossHud()
			return
		end
		local wasKnown = bossStates[state.key] ~= nil
		bossStates[state.key] = state
		if state.action == "spawn" and not wasKnown then
			showBanner("👑 " .. tostring(state.name) .. " has awakened!", Color3.fromRGB(255, 214, 108), 4)
		end
	end)

	Remotes.Get("BossDefeated").OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		local rewards = {}
		if (result.gold or 0) > 0 then
			table.insert(rewards, "+" .. tostring(result.gold) .. "g")
		end
		if (result.diamonds or 0) > 0 then
			table.insert(rewards, "+" .. tostring(result.diamonds) .. "💎")
		end
		if (result.essence or 0) > 0 and result.essenceName and result.essenceName ~= "" then
			table.insert(rewards, "+" .. tostring(result.essence) .. " " .. tostring(result.essenceName))
		end
		local first = if result.firstKill then "  First victory!" else ""
		showBanner("🏆 Defeated " .. tostring(result.name) .. "!  " .. table.concat(rewards, "  ") .. first, Color3.fromRGB(255, 225, 120), 6)
	end)

	RunService.RenderStepped:Connect(updateBossHud)
	Remotes.Get("RequestBossState"):FireServer()
end

function CombatController.Start() end

return CombatController

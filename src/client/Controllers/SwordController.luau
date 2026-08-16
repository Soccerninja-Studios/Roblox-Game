--!strict
-- SwordController: two jobs.
--   (1) COMBAT INPUT: while you HOLD a sword tool, click/hold to swing. The server
--       resolves every hit; this just gates the cadence and plays an arm swing.
--   (2) SWORDS SHOP TAB: draws the buy / equip / sharpen cards into the Market's
--       "Swords" tab (same Mount/Refresh contract BackpackController uses).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local SwordController = {}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)
local WHITE = Color3.fromRGB(255, 255, 255)

local swinging = false
local lastSwing = 0

local listFrame: Frame? = nil
local latest: any = nil
local wired = false

local function heldSword(): Tool?
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Sword") then
		return tool
	end
	return nil
end

-- Swing the equipped sword by tweening its own Motor6D joints -- the SAME approach
-- the mowing tools use (ToolController). The sword's "Pivot" joint lives inside
-- the Tool (built by SwordService) and carries RestC0 / SwungC0 pose attributes,
-- so the swing renders on any rig (R6 or R15) and is never overridden by the
-- default character animation -- which is why the old shoulder tween did nothing.
local function swingMotor(motor: Motor6D, from: CFrame, to: CFrame, downTime: number, upTime: number)
	local down = TweenService:Create(motor, TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = to })
	local up = TweenService:Create(motor, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = from })
	down.Completed:Connect(function()
		up:Play()
	end)
	down:Play()
end

-- Chop the blade down in front and bring it back up on every click.
local function playSwingAnim()
	local tool = heldSword()
	if not tool then
		return
	end
	for _, motor in tool:GetDescendants() do
		if motor:IsA("Motor6D") then
			local rest = motor:GetAttribute("RestC0")
			local swung = motor:GetAttribute("SwungC0")
			if typeof(rest) == "CFrame" and typeof(swung) == "CFrame" then
				swingMotor(motor, rest, swung, 0.09, 0.16)
			end
		end
	end
end

-- Confirmed-hit feedback: a bright blade flash the instant the SERVER says a
-- swing connected. No arm tween here -- the swing slam already owns the arm, and
-- a second shoulder tween firing at the same time would fight it.
-- Base blade look, captured once per flash burst so rapid confirmed hits can't
-- capture the flashed (white/Neon) state as the "original" and leave the blade
-- stuck neon white. The token makes sure only the LATEST scheduled restore runs.
local flashToken = 0
local flashBaseColor: Color3? = nil
local flashBaseMaterial: Enum.Material? = nil
local function playHitAnim()
	local tool = heldSword()
	local blade = tool and tool:FindFirstChild("Blade")
	if not (blade and blade:IsA("BasePart")) then
		return
	end
	-- Only snapshot the true base look when we are NOT already mid-flash.
	if flashToken == 0 then
		flashBaseColor = blade.Color
		flashBaseMaterial = blade.Material
	end
	flashToken += 1
	local myToken = flashToken
	blade.Color = Color3.fromRGB(255, 255, 255)
	blade.Material = Enum.Material.Neon
	task.delay(0.12, function()
		if myToken ~= flashToken then
			return -- a newer flash started; its restore will be the one that runs
		end
		flashToken = 0
		if blade and blade.Parent and flashBaseColor and flashBaseMaterial then
			blade.Color = flashBaseColor
			blade.Material = flashBaseMaterial
		end
	end)
end

local function trySwing()
	local tool = heldSword()
	if not tool then
		return
	end
	local key = tool:GetAttribute("SwordKey")
	local cd = StatCalculator.GetSwordCooldown(key, nil)
	local now = os.clock()
	if now - lastSwing < cd then
		return
	end
	lastSwing = now
	playSwingAnim()
	Remotes.Get("SwordSwing"):FireServer()
end

local function formatNumber(n: number): string
	local whole = tostring(math.floor(n))
	local out = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function corner(inst: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function zoneLabel(zone: string): string
	local def = GameConfig.GRASS_TYPES and GameConfig.GRASS_TYPES[zone]
	return if def and def.displayName then def.displayName else zone
end

-- Config-only snapshot painted before the server state arrives, so the tab is
-- never blank.
local function configSnapshot(): any
	local list = {}
	for _, def in ipairs(GameConfig.SWORDS) do
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
			damage = def.levels[1].damage,
			level = 1,
			maxLevel = #def.levels,
			owned = false,
			unlocked = false,
			equipped = false,
			bladeR = blade[1],
			bladeG = blade[2],
			bladeB = blade[3],
			pending = true,
		})
	end
	return { swords = list, gold = 0, diamonds = 0, essence = {} }
end

local function makeButton(parent: Instance, y: number): TextButton
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, y)
	btn.Size = UDim2.fromOffset(140, 34)
	btn.BackgroundColor3 = GREEN
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.FredokaOne
	btn.Text = ""
	btn.TextColor3 = WHITE
	btn.TextSize = 13
	btn.AutoButtonColor = true
	btn.ZIndex = 12
	corner(btn, 9)
	btn.Parent = parent
	return btn
end

local function purchasePriceText(sword: any): string
	local parts = {}
	if (sword.goldCost or 0) > 0 then
		table.insert(parts, formatNumber(sword.goldCost) .. "g")
	end
	if (sword.diamondCost or 0) > 0 then
		table.insert(parts, formatNumber(sword.diamondCost) .. "\u{1F48E}")
	end
	if (sword.essenceCost or 0) > 0 then
		table.insert(parts, formatNumber(sword.essenceCost) .. " " .. (sword.essenceName or "essence"))
	end
	return if #parts > 0 then table.concat(parts, " + ") else "Free"
end

local function buildCard(sword: any, order: number, currency: any)
	local card = Instance.new("Frame")
	card.Name = "Sword_" .. tostring(sword.key)
	card.Size = UDim2.new(1, 0, 0, 116)
	card.BackgroundColor3 = PANEL
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.ZIndex = 11
	corner(card, 12)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 8, 1, -20)
	swatch.Position = UDim2.fromOffset(10, 10)
	swatch.BackgroundColor3 = Color3.fromRGB(sword.bladeR, sword.bladeG, sword.bladeB)
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 12
	corner(swatch, 4)
	swatch.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(28, 10)
	name.Size = UDim2.new(1, -180, 0, 22)
	name.Font = Enum.Font.FredokaOne
	name.Text = sword.name
	name.TextColor3 = INK
	name.TextSize = 17
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 12
	name.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(28, 32)
	desc.Size = UDim2.new(1, -180, 0, 18)
	desc.Font = Enum.Font.GothamMedium
	desc.Text = sword.desc or ""
	desc.TextColor3 = SUBTLE
	desc.TextSize = 12
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.ZIndex = 12
	desc.Parent = card

	local dmgText = "\u{2694}\u{FE0F} " .. sword.damage .. " dmg"
	if sword.nextDamage then
		dmgText = dmgText .. "  \u{2192}  " .. sword.nextDamage
	end
	local dmg = Instance.new("TextLabel")
	dmg.BackgroundTransparency = 1
	dmg.Position = UDim2.fromOffset(28, 54)
	dmg.Size = UDim2.new(1, -180, 0, 18)
	dmg.Font = Enum.Font.GothamBold
	dmg.Text = dmgText
	dmg.TextColor3 = GREEN_DARK
	dmg.TextSize = 13
	dmg.TextXAlignment = Enum.TextXAlignment.Left
	dmg.ZIndex = 12
	dmg.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(28, 78)
	sub.Size = UDim2.new(1, -180, 0, 18)
	sub.Font = Enum.Font.GothamMedium
	sub.Text = if sword.owned
		then "Level " .. sword.level .. " / " .. sword.maxLevel
		else "Unlocks in " .. zoneLabel(sword.zone)
	sub.TextColor3 = SUBTLE
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 12
	sub.Parent = card

	local main = makeButton(card, 10)
	if sword.pending then
		main.BackgroundColor3 = LOCKED
		main.Text = "\u{2026}"
		main.AutoButtonColor = false
		main.Active = false
	elseif sword.equipped then
		main.BackgroundColor3 = GREEN_DARK
		main.Text = "Equipped \u{2713}"
		main.AutoButtonColor = false
		main.Active = false
	elseif sword.owned then
		main.BackgroundColor3 = GREEN
		main.Text = "Equip"
		main.Activated:Connect(function()
			Remotes.Get("EquipSword"):FireServer(sword.key)
		end)
	elseif not sword.unlocked then
		main.BackgroundColor3 = LOCKED
		main.Text = "Locked"
		main.AutoButtonColor = false
		main.Active = false
	else
		local essenceBalance = if sword.essenceKey then ((currency.essence and currency.essence[sword.essenceKey]) or 0) else 0
		local affordable = (currency.gold or 0) >= (sword.goldCost or 0)
			and (currency.diamonds or 0) >= (sword.diamondCost or 0)
			and essenceBalance >= (sword.essenceCost or 0)
		main.BackgroundColor3 = if affordable then GOLD else LOCKED
		main.TextColor3 = if affordable then INK else WHITE
		main.TextSize = if (sword.essenceCost or 0) > 0 then 10 else 13
		main.Text = purchasePriceText(sword)
		main.Activated:Connect(function()
			Remotes.Get("PurchaseSword"):FireServer(sword.key)
		end)
	end

	if sword.owned and not sword.pending then
		local up = makeButton(card, 50)
		if not sword.nextCost then
			up.BackgroundColor3 = LOCKED
			up.Text = "Max Sharpness"
			up.AutoButtonColor = false
			up.Active = false
		else
			local affordable = (currency.gold or 0) >= sword.nextCost
			up.BackgroundColor3 = if affordable then GOLD else LOCKED
			up.TextColor3 = if affordable then INK else WHITE
			up.Text = "Sharpen  " .. formatNumber(sword.nextCost) .. "g"
			up.Activated:Connect(function()
				Remotes.Get("UpgradeSword"):FireServer(sword.key)
			end)
		end
	end

	card.Parent = listFrame
end

local function essenceLine(): string
	if not latest or not latest.essence then
		return ""
	end
	local parts = {}
	for key, amount in latest.essence do
		local meta = GameConfig.ESSENCE and GameConfig.ESSENCE[key]
		local label = if meta and meta.name then meta.name else key
		table.insert(parts, label .. ": " .. amount)
	end
	return table.concat(parts, "   ")
end

local function notice(host: Instance, text: string)
	local label = Instance.new("TextLabel")
	label.Name = "Notice"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = SUBTLE
	label.TextSize = 13
	label.ZIndex = 11
	label.Parent = host
end

local function render()
	local host = listFrame
	if not host then
		return
	end
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local snapshot = if latest and latest.swords then latest else configSnapshot()
	local currency = { gold = snapshot.gold or 0, diamonds = snapshot.diamonds or 0, essence = snapshot.essence or {} }

	local ess = essenceLine()
	if ess ~= "" then
		notice(host, "\u{1F33C} " .. ess)
	end

	for i, sword in ipairs(snapshot.swords) do
		buildCard(sword, i + 1, currency)
	end

	if snapshot ~= latest then
		notice(host, "Syncing the armory\u{2026}")
	end
end

local function ensureWired()
	if wired then
		return
	end
	wired = true
	Remotes.Get("SwordState").OnClientEvent:Connect(function(state)
		latest = state
		render()
	end)
end

function SwordController.Refresh()
	Remotes.Get("RequestSwords"):FireServer()
end

function SwordController.Mount(host: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "SwordList"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = 1
	holder.ZIndex = 11
	holder.Parent = host

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	listFrame = holder
	render()

	task.spawn(function()
		ensureWired()
		for _ = 1, 12 do
			if latest then
				return
			end
			SwordController.Refresh()
			task.wait(1)
		end
	end)
end

function SwordController.Init()
	ensureWired()

	-- Play the hit reaction whenever the server confirms a swing connected.
	Remotes.Get("MonsterHit").OnClientEvent:Connect(function()
		playHitAnim()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			swinging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			swinging = false
		end
	end)
end

function SwordController.Start()
	while true do
		task.wait(0.05)
		if swinging then
			trySwing()
		end
	end
end

return SwordController

--!strict
-- PetRewardController: animated twelve-slot Golden Pet Wheel and pet-shard crate
-- interface. Results are displayed only after the server selects and grants them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PetRewardController = {}

local GREEN = Color3.fromRGB(72, 145, 76)
local GREEN_DARK = Color3.fromRGB(42, 91, 49)
local PANEL = Color3.fromRGB(244, 238, 214)
local PANEL_DARK = Color3.fromRGB(224, 215, 184)
local INK = Color3.fromRGB(46, 53, 42)
local SUBTLE = Color3.fromRGB(94, 101, 84)
local GOLD = Color3.fromRGB(239, 190, 55)
local PURPLE = Color3.fromRGB(143, 92, 188)
local WHITE = Color3.fromRGB(255, 255, 248)
local LOCKED = Color3.fromRGB(125, 130, 122)

local latest: any = nil
local stateReceivedAt = 0
local panel: Frame? = nil
local spinButton: TextButton? = nil
local crateButton: TextButton? = nil
local freeLabel: TextLabel? = nil
local wheelPityLabel: TextLabel? = nil
local cratePityLabel: TextLabel? = nil
local resultLabel: TextLabel? = nil
local pointer: Frame? = nil
local crateIcon: Frame? = nil
local slotLabels: { TextLabel } = {}
local lastResultId: string? = nil
local localBusy = false
local wired = false

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local item = Instance.new("UIStroke")
	item.Color = color
	item.Thickness = thickness
	item.Transparency = transparency or 0
	item.Parent = parent
end

local function button(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Position = position
	item.Size = size
	item.Font = Enum.Font.FredokaOne
	item.Text = text
	item.TextColor3 = WHITE
	item.TextSize = 15
	item.ZIndex = 24
	corner(item, 10)
	item.Parent = parent
	return item
end

local function setEnabled(item: TextButton?, enabled: boolean, enabledColor: Color3)
	if not item then
		return
	end
	item.Active = enabled
	item.AutoButtonColor = enabled
	item.BackgroundColor3 = if enabled then enabledColor else LOCKED
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%02d:%02d", minutes, secs)
end

local function remainingFree(): number
	if not latest then
		return 0
	end
	return math.max(0, (latest.freeSpinRemaining or 0) - math.floor(os.clock() - stateReceivedAt))
end

local function updateLabels()
	if not latest then
		return
	end
	local remaining = remainingFree()
	if freeLabel then
		freeLabel.Text = if remaining <= 0
			then "Daily spin ready!"
			else "Next free spin: " .. formatTime(remaining)
	end
	if spinButton then
		spinButton.Text = if localBusy
			then "Spinning\u{2026}"
			elseif remaining <= 0 then "FREE SPIN"
			else "SPIN  " .. tostring(latest.paidSpinDiamonds or 5) .. " \u{1F48E}"
		local affordable = remaining <= 0 or (latest.diamonds or 0) >= (latest.paidSpinDiamonds or 5)
		setEnabled(spinButton, not localBusy and affordable, GOLD)
		spinButton.TextColor3 = if not localBusy and affordable then INK else WHITE
	end
	if wheelPityLabel then
		local pity = latest.wheelPity or 0
		local limit = latest.wheelPitySpins or 20
		wheelPityLabel.Text = "Golden pity: " .. tostring(pity) .. " / " .. tostring(limit) .. "  \u{2022}  Guaranteed within " .. tostring(math.max(1, limit - pity)) .. " spins"
	end
	if crateButton then
		crateButton.Text = if localBusy then "Opening\u{2026}" else "OPEN CRATE  " .. tostring(latest.crateDiamonds or 4) .. " \u{1F48E}"
		local affordable = latest.canOpenCrate and (latest.diamonds or 0) >= (latest.crateDiamonds or 4)
		setEnabled(crateButton, not localBusy and affordable, PURPLE)
	end
	if cratePityLabel then
		if latest.canOpenCrate then
			local pity = latest.cratePity or 0
			local limit = latest.crateRarePity or 8
			cratePityLabel.Text = "Rare-bundle pity: " .. tostring(pity) .. " / " .. tostring(limit) .. "  \u{2022}  8 / 15 / 30 shards"
		else
			cratePityLabel.Text = "Recruit at least one pet to open shard crates."
		end
	end
end

local function animateWheel(result: any)
	if not pointer then
		return
	end
	localBusy = true
	updateLabels()
	if resultLabel then
		resultLabel.Text = "The wheel is spinning\u{2026}"
		resultLabel.TextColor3 = SUBTLE
	end
	local slotCount = math.max(1, #slotLabels)
	local angle = ((result.slot or 1) - 1) * (360 / slotCount)
	local start = pointer.Rotation % 360
	local target = start + 1800 + ((angle - start) % 360)
	local tween = TweenService:Create(pointer, TweenInfo.new(2.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = target })
	tween:Play()
	task.delay(2.45, function()
		localBusy = false
		if resultLabel then
			resultLabel.Text = "\u{2728} " .. tostring(result.label or "Wheel reward")
			resultLabel.TextColor3 = if result.kind == "golden" then GOLD else GREEN_DARK
		end
		updateLabels()
	end)
end

local function animateCrate(result: any)
	localBusy = true
	updateLabels()
	if resultLabel then
		resultLabel.Text = "Opening the companion crate\u{2026}"
		resultLabel.TextColor3 = SUBTLE
	end
	if crateIcon then
		local scale = crateIcon:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = crateIcon
		scale.Scale = 1
		TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 3, true), { Scale = 1.13 }):Play()
	end
	task.delay(1.2, function()
		localBusy = false
		if resultLabel then
			resultLabel.Text = "\u{1F4E6} " .. tostring(result.label or "Shard reward")
			resultLabel.TextColor3 = PURPLE
		end
		updateLabels()
	end)
end

local function applyState(state: any)
	latest = state
	stateReceivedAt = os.clock()
	for index, slot in ipairs(state.wheelSlots or {}) do
		if slotLabels[index] then
			slotLabels[index].Text = tostring(slot.label)
		end
	end
	local result = state.result
	if state.message and not result and resultLabel then
		resultLabel.Text = tostring(state.message)
		resultLabel.TextColor3 = SUBTLE
	end
	if result and result.id ~= lastResultId then
		lastResultId = result.id
		if result.action == "wheel" then
			animateWheel(result)
		elseif result.action == "crate" then
			animateCrate(result)
		elseif resultLabel then
			resultLabel.Text = "\u{2B50} " .. tostring(result.label or "Pet upgraded")
			resultLabel.TextColor3 = GREEN_DARK
		end
	end
	updateLabels()
end

local function requestState()
	Remotes.Get("RequestPetRewards"):FireServer()
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
		if open then
			requestState()
		end
	end
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("PetRewardsGui")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PetRewardsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 27
	gui.Parent = playerGui

	local open = button(gui, "\u{2728} REWARDS", UDim2.new(1, -130, 0.5, 122), UDim2.fromOffset(112, 44), PURPLE)
	open.Name = "RewardsButton"
	open.AnchorPoint = Vector2.new(0, 0.5)
	open.Activated:Connect(function()
		setOpen(not (panel and panel.Visible))
	end)

	local window = Instance.new("Frame")
	window.Name = "RewardsWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0.86, 0, 0.8, 0)
	window.BackgroundColor3 = Color3.fromRGB(234, 228, 202)
	window.BorderSizePixel = 0
	window.Visible = false
	window.ZIndex = 20
	corner(window, 16)
	stroke(window, PURPLE, 2, 0.15)
	window.Parent = gui
	panel = window
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(620, 430)
	constraint.MaxSize = Vector2.new(980, 650)
	constraint.Parent = window

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 12)
	title.Size = UDim2.new(1, -88, 0, 34)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Golden Pet Wheel & Shard Crates"
	title.TextColor3 = INK
	title.TextSize = 23
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 21
	title.Parent = window

	local close = button(window, "X", UDim2.new(1, -52, 0, 12), UDim2.fromOffset(36, 34), Color3.fromRGB(154, 73, 67))
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local wheelHost = Instance.new("Frame")
	wheelHost.BackgroundColor3 = PANEL
	wheelHost.BorderSizePixel = 0
	wheelHost.Position = UDim2.fromOffset(18, 56)
	wheelHost.Size = UDim2.new(0.58, -26, 1, -126)
	wheelHost.ZIndex = 21
	corner(wheelHost, 14)
	wheelHost.Parent = window

	local wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.new(0.5, 0, 0.47, 0)
	wheel.Size = UDim2.fromOffset(330, 330)
	wheel.BackgroundColor3 = Color3.fromRGB(226, 214, 176)
	wheel.BorderSizePixel = 0
	wheel.ZIndex = 22
	corner(wheel, 165)
	stroke(wheel, GOLD, 5, 0)
	wheel.Parent = wheelHost

	for index = 1, 12 do
		local angle = math.rad((index - 1) * 30 - 90)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(165 + math.cos(angle) * 126, 165 + math.sin(angle) * 126)
		label.Size = UDim2.fromOffset(76, 36)
		label.BackgroundColor3 = if index == 12 then GOLD else (if index % 2 == 0 then PANEL_DARK else WHITE)
		label.BackgroundTransparency = 0.05
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold
		label.Text = "Slot " .. tostring(index)
		label.TextColor3 = INK
		label.TextSize = 9
		label.TextWrapped = true
		label.ZIndex = 23
		corner(label, 8)
		label.Parent = wheel
		table.insert(slotLabels, label)
	end

	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.fromOffset(7, 112)
	needle.BackgroundColor3 = Color3.fromRGB(180, 57, 53)
	needle.BorderSizePixel = 0
	needle.ZIndex = 25
	corner(needle, 4)
	needle.Parent = wheel
	pointer = needle
	local arrow = Instance.new("TextLabel")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0, -4)
	arrow.Size = UDim2.fromOffset(28, 28)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "\u{25B2}"
	arrow.TextColor3 = Color3.fromRGB(180, 57, 53)
	arrow.TextSize = 25
	arrow.ZIndex = 26
	arrow.Parent = needle

	local free = Instance.new("TextLabel")
	free.BackgroundTransparency = 1
	free.Position = UDim2.new(0, 12, 1, -66)
	free.Size = UDim2.new(1, -24, 0, 18)
	free.Font = Enum.Font.GothamBold
	free.Text = "Daily spin ready!"
	free.TextColor3 = GREEN_DARK
	free.TextSize = 12
	free.TextXAlignment = Enum.TextXAlignment.Left
	free.ZIndex = 22
	free.Parent = wheelHost
	freeLabel = free

	local spin = button(wheelHost, "FREE SPIN", UDim2.new(1, -168, 1, -74), UDim2.fromOffset(150, 38), GOLD)
	spin.TextColor3 = INK
	spin.Activated:Connect(function()
		if not localBusy then
			localBusy = true
			updateLabels()
			Remotes.Get("SpinPetWheel"):FireServer()
			task.delay(3, function()
				if localBusy then
					localBusy = false
					updateLabels()
				end
			end)
		end
	end)
	spinButton = spin

	local right = Instance.new("Frame")
	right.BackgroundColor3 = PANEL
	right.BorderSizePixel = 0
	right.Position = UDim2.new(0.58, 0, 0, 56)
	right.Size = UDim2.new(0.42, -18, 1, -126)
	right.ZIndex = 21
	corner(right, 14)
	right.Parent = window

	local crateTitle = Instance.new("TextLabel")
	crateTitle.BackgroundTransparency = 1
	crateTitle.Position = UDim2.fromOffset(16, 14)
	crateTitle.Size = UDim2.new(1, -32, 0, 28)
	crateTitle.Font = Enum.Font.FredokaOne
	crateTitle.Text = "Companion Shard Crate"
	crateTitle.TextColor3 = PURPLE
	crateTitle.TextSize = 19
	crateTitle.ZIndex = 22
	crateTitle.Parent = right

	local crate = Instance.new("Frame")
	crate.AnchorPoint = Vector2.new(0.5, 0)
	crate.Position = UDim2.new(0.5, 0, 0, 60)
	crate.Size = UDim2.fromOffset(150, 122)
	crate.BackgroundColor3 = Color3.fromRGB(128, 82, 166)
	crate.BorderSizePixel = 0
	crate.ZIndex = 22
	corner(crate, 16)
	stroke(crate, GOLD, 5, 0.1)
	crate.Parent = right
	crateIcon = crate
	local crateText = Instance.new("TextLabel")
	crateText.BackgroundTransparency = 1
	crateText.Size = UDim2.fromScale(1, 1)
	crateText.Font = Enum.Font.FredokaOne
	crateText.Text = "\u{1F4E6}\nPET SHARDS"
	crateText.TextColor3 = WHITE
	crateText.TextSize = 20
	crateText.ZIndex = 23
	crateText.Parent = crate

	local cratePity = Instance.new("TextLabel")
	cratePity.BackgroundTransparency = 1
	cratePity.Position = UDim2.fromOffset(16, 196)
	cratePity.Size = UDim2.new(1, -32, 0, 44)
	cratePity.Font = Enum.Font.GothamMedium
	cratePity.Text = "Rare-bundle pity"
	cratePity.TextColor3 = SUBTLE
	cratePity.TextSize = 11
	cratePity.TextWrapped = true
	cratePity.ZIndex = 22
	cratePity.Parent = right
	cratePityLabel = cratePity

	local openCrate = button(right, "OPEN CRATE", UDim2.new(0, 16, 0, 248), UDim2.new(1, -32, 0, 40), PURPLE)
	openCrate.Activated:Connect(function()
		if not localBusy then
			localBusy = true
			updateLabels()
			Remotes.Get("OpenPetCrate"):FireServer()
			task.delay(1.6, function()
				if localBusy then
					localBusy = false
					updateLabels()
				end
			end)
		end
	end)
	crateButton = openCrate

	local odds = Instance.new("TextLabel")
	odds.BackgroundTransparency = 1
	odds.Position = UDim2.fromOffset(16, 300)
	odds.Size = UDim2.new(1, -32, 0, 64)
	odds.Font = Enum.Font.GothamMedium
	odds.Text = "Crates award shards for an owned pet. Spend shards in the Pets menu to raise ranks and permanently strengthen bonuses."
	odds.TextColor3 = SUBTLE
	odds.TextSize = 11
	odds.TextWrapped = true
	odds.TextYAlignment = Enum.TextYAlignment.Top
	odds.ZIndex = 22
	odds.Parent = right

	local wheelPity = Instance.new("TextLabel")
	wheelPity.BackgroundTransparency = 1
	wheelPity.Position = UDim2.fromOffset(20, -64)
	wheelPity.Size = UDim2.new(0.58, -30, 0, 22)
	wheelPity.Font = Enum.Font.GothamMedium
	wheelPity.Text = "Golden pity: 0 / 20"
	wheelPity.TextColor3 = SUBTLE
	wheelPity.TextSize = 11
	wheelPity.TextXAlignment = Enum.TextXAlignment.Left
	wheelPity.ZIndex = 21
	wheelPity.Parent = window
	wheelPityLabel = wheelPity

	local result = Instance.new("TextLabel")
	result.BackgroundColor3 = PANEL_DARK
	result.BorderSizePixel = 0
	result.Position = UDim2.new(0.58, 0, 1, -64)
	result.Size = UDim2.new(0.42, -18, 0, 46)
	result.Font = Enum.Font.GothamBold
	result.Text = "Spin or open a crate to earn companion rewards."
	result.TextColor3 = SUBTLE
	result.TextSize = 12
	result.TextWrapped = true
	result.ZIndex = 21
	corner(result, 10)
	result.Parent = window
	resultLabel = result
end

local function ensureWired()
	if wired then
		return
	end
	wired = true
	Remotes.Get("PetRewardState").OnClientEvent:Connect(applyState)
	Remotes.Get("OpenPhysicalPetWheel").OnClientEvent:Connect(function()
		setOpen(true)
	end)
end

function PetRewardController.Init()
	ensureWired()
	buildGui()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.L then
			setOpen(not (panel and panel.Visible))
		end
	end)
end

function PetRewardController.Start()
	for _ = 1, 12 do
		if latest then
			break
		end
		requestState()
		task.wait(1)
	end
	while true do
		task.wait(1)
		updateLabels()
	end
end

return PetRewardController

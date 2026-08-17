--!strict
-- PetController: self-contained collection UI for all fifteen pets. It renders
-- recruitment, the three equipped slots, levels, essence feeding, aggregate stat
-- bonuses, and server notices. The server remains authoritative for every action.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PetController = {}

local GREEN = Color3.fromRGB(86, 157, 73)
local GREEN_DARK = Color3.fromRGB(45, 100, 52)
local PANEL = Color3.fromRGB(244, 238, 214)
local PANEL_DARK = Color3.fromRGB(225, 216, 185)
local INK = Color3.fromRGB(45, 55, 42)
local SUBTLE = Color3.fromRGB(92, 102, 83)
local WHITE = Color3.fromRGB(255, 255, 248)
local GOLD = Color3.fromRGB(235, 190, 62)
local LOCKED = Color3.fromRGB(128, 133, 124)

local latest: any = nil
local gui: ScreenGui? = nil
local panel: Frame? = nil
local scroll: ScrollingFrame? = nil
local summaryLabel: TextLabel? = nil
local noticeLabel: TextLabel? = nil
local toggleButton: TextButton? = nil
local wired = false

local STAT_NAMES = {
	bagCapacity = "Bag",
	clippingValue = "Clipping value",
	cutPower = "Cut power",
	swordDamage = "Sword damage",
	attackSpeed = "Attack speed",
	maxHealth = "Max health",
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(126, 170, 116),
	Uncommon = Color3.fromRGB(78, 156, 190),
	Rare = Color3.fromRGB(168, 100, 204),
}

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

local function formatNumber(value: number): string
	local n = math.floor(value + 0.5)
	local text = tostring(n)
	while true do
		local changed
		text, changed = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		if changed == 0 then
			break
		end
	end
	return text
end

local function percent(value: number): string
	local amount = value * 100
	return if math.abs(amount - math.floor(amount + 0.5)) < 0.05
		then tostring(math.floor(amount + 0.5)) .. "%"
		else string.format("%.1f%%", amount)
end

local function bonusText(bonuses: any): string
	local parts = {}
	for stat, value in bonuses or {} do
		table.insert(parts, "+" .. percent(value) .. " " .. (STAT_NAMES[stat] or stat))
	end
	table.sort(parts)
	return table.concat(parts, "   ")
end

local function priceText(pet: any): string
	local parts = {}
	if (pet.goldCost or 0) > 0 then
		table.insert(parts, formatNumber(pet.goldCost) .. "g")
	end
	if (pet.diamondCost or 0) > 0 then
		table.insert(parts, formatNumber(pet.diamondCost) .. "\u{1F48E}")
	end
	if (pet.essenceCost or 0) > 0 then
		table.insert(parts, formatNumber(pet.essenceCost) .. " " .. tostring(pet.essenceName or "essence"))
	end
	return if #parts > 0 then table.concat(parts, " + ") else "Free"
end

local function actionButton(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Position = position
	button.Size = size
	button.Font = Enum.Font.FredokaOne
	button.Text = text
	button.TextColor3 = WHITE
	button.TextSize = 13
	button.AutoButtonColor = true
	button.ZIndex = 24
	corner(button, 8)
	button.Parent = parent
	return button
end

local function disabled(button: TextButton)
	button.BackgroundColor3 = LOCKED
	button.AutoButtonColor = false
	button.Active = false
end

local function fallbackState(): any
	local pets = {}
	for _, def in ipairs(GameConfig.PETS or {}) do
		local body = def.bodyColor
		local accent = def.accentColor
		table.insert(pets, {
			key = def.key, name = def.name, zone = def.zone, rarity = def.rarity,
			owned = false, equipped = false, unlocked = false, pending = true,
			level = 1, maxLevel = GameConfig.PET_SYSTEM.maxLevel or 25,
			xp = 0, nextFeed = GameConfig.PET_SYSTEM.feedBase or 8,
			goldCost = def.goldCost or 0, diamondCost = def.diamondCost or 0,
			essenceKey = def.essenceKey,
			essenceName = if def.essenceKey and GameConfig.ESSENCE[def.essenceKey] then GameConfig.ESSENCE[def.essenceKey].name else "Essence",
			essenceCost = def.essenceCost or 0,
			bonuses = def.bonuses,
			bodyR = body[1], bodyG = body[2], bodyB = body[3],
			accentR = accent[1], accentG = accent[2], accentB = accent[3],
		})
	end
	return { pets = pets, gold = 0, diamonds = 0, essence = {}, equippedCount = 0, maxEquipped = 3, aggregateBonuses = {} }
end

local function currencyAffordable(pet: any, state: any): boolean
	local essenceBalance = if pet.essenceKey then ((state.essence and state.essence[pet.essenceKey]) or 0) else 0
	return (state.gold or 0) >= (pet.goldCost or 0)
		and (state.diamonds or 0) >= (pet.diamondCost or 0)
		and essenceBalance >= (pet.essenceCost or 0)
end

local function buildPetCard(host: Instance, pet: any, state: any, order: number)
	local card = Instance.new("Frame")
	card.Name = "Pet_" .. tostring(pet.key)
	card.BackgroundColor3 = PANEL
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.ZIndex = 21
	corner(card, 12)
	stroke(card, RARITY_COLORS[pet.rarity] or PANEL_DARK, 1.5, 0.18)

	local stripe = Instance.new("Frame")
	stripe.BackgroundColor3 = Color3.fromRGB(pet.bodyR, pet.bodyG, pet.bodyB)
	stripe.BorderSizePixel = 0
	stripe.Position = UDim2.fromOffset(9, 10)
	stripe.Size = UDim2.new(0, 8, 1, -20)
	stripe.ZIndex = 22
	corner(stripe, 4)
	stripe.Parent = card

	local dot = Instance.new("Frame")
	dot.BackgroundColor3 = Color3.fromRGB(pet.accentR, pet.accentG, pet.accentB)
	dot.BorderSizePixel = 0
	dot.Position = UDim2.fromOffset(23, 14)
	dot.Size = UDim2.fromOffset(28, 28)
	dot.ZIndex = 22
	corner(dot, 14)
	dot.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(58, 8)
	name.Size = UDim2.new(1, -180, 0, 24)
	name.Font = Enum.Font.FredokaOne
	name.Text = (pet.golden and "\u{2728} " or "") .. tostring(pet.name)
	name.TextColor3 = INK
	name.TextSize = 17
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 22
	name.Parent = card

	local zone = Instance.new("TextLabel")
	zone.BackgroundTransparency = 1
	zone.Position = UDim2.fromOffset(58, 31)
	zone.Size = UDim2.new(1, -180, 0, 18)
	zone.Font = Enum.Font.GothamBold
	zone.Text = tostring(pet.zone) .. "  \u{2022}  " .. tostring(pet.rarity)
	zone.TextColor3 = RARITY_COLORS[pet.rarity] or SUBTLE
	zone.TextSize = 11
	zone.TextXAlignment = Enum.TextXAlignment.Left
	zone.ZIndex = 22
	zone.Parent = card

	local bonus = Instance.new("TextLabel")
	bonus.BackgroundTransparency = 1
	bonus.Position = UDim2.fromOffset(23, 55)
	bonus.Size = UDim2.new(1, -46, 0, 36)
	bonus.Font = Enum.Font.GothamMedium
	bonus.Text = bonusText(pet.bonuses)
	bonus.TextColor3 = GREEN_DARK
	bonus.TextSize = 12
	bonus.TextWrapped = true
	bonus.TextXAlignment = Enum.TextXAlignment.Left
	bonus.TextYAlignment = Enum.TextYAlignment.Top
	bonus.ZIndex = 22
	bonus.Parent = card

	local progress = Instance.new("TextLabel")
	progress.BackgroundTransparency = 1
	progress.Position = UDim2.fromOffset(23, 92)
	progress.Size = UDim2.new(1, -150, 0, 20)
	progress.Font = Enum.Font.GothamMedium
	if pet.pending then
		progress.Text = "Syncing collection\u{2026}"
	elseif pet.owned then
		progress.Text = if pet.nextFeed
			then "Level " .. tostring(pet.level) .. " / " .. tostring(pet.maxLevel) .. "   \u{2022}   Feed " .. tostring(pet.xp) .. " / " .. tostring(pet.nextFeed)
			else "Level " .. tostring(pet.level) .. " / " .. tostring(pet.maxLevel) .. "   \u{2022}   MAX"
	else
		progress.Text = if pet.unlocked then priceText(pet) else "Reach " .. tostring(pet.zone) .. " to unlock"
	end
	progress.TextColor3 = SUBTLE
	progress.TextSize = 11
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.ZIndex = 22
	progress.Parent = card

	local main = actionButton(card, "", UDim2.new(1, -132, 0, 10), UDim2.fromOffset(120, 34), GREEN)
	if pet.pending then
		main.Text = "\u{2026}"
		disabled(main)
	elseif pet.owned then
		main.Text = if pet.equipped then "Unequip" else "Equip"
		main.BackgroundColor3 = if pet.equipped then GREEN_DARK else GREEN
		main.Activated:Connect(function()
			Remotes.Get("EquipPet"):FireServer(pet.key)
		end)
	elseif not pet.unlocked then
		main.Text = "Locked"
		disabled(main)
	else
		main.Text = "Recruit"
		if currencyAffordable(pet, state) then
			main.BackgroundColor3 = GOLD
			main.TextColor3 = INK
		else
			disabled(main)
		end
		main.Activated:Connect(function()
			Remotes.Get("RecruitPet"):FireServer(pet.key)
		end)
	end

	if pet.owned and pet.nextFeed and not pet.pending then
		local feedTitle = Instance.new("TextLabel")
		feedTitle.BackgroundTransparency = 1
		feedTitle.Position = UDim2.fromOffset(23, 118)
		feedTitle.Size = UDim2.new(1, -46, 0, 18)
		feedTitle.Font = Enum.Font.GothamBold
		feedTitle.Text = "Feed " .. tostring(pet.essenceName) .. ":"
		feedTitle.TextColor3 = SUBTLE
		feedTitle.TextSize = 11
		feedTitle.TextXAlignment = Enum.TextXAlignment.Left
		feedTitle.ZIndex = 22
		feedTitle.Parent = card
		local balance = (state.essence and state.essence[pet.essenceKey]) or 0
		for index, amount in ipairs({ 1, 5, 25 }) do
			local feed = actionButton(card, "+" .. tostring(amount), UDim2.fromOffset(23 + (index - 1) * 72, 143), UDim2.fromOffset(64, 30), GREEN)
			feed.TextSize = 12
			if balance < amount then
				disabled(feed)
			end
			feed.Activated:Connect(function()
				Remotes.Get("FeedPet"):FireServer(pet.key, amount)
			end)
		end
	else
		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.Position = UDim2.fromOffset(23, 126)
		hint.Size = UDim2.new(1, -46, 0, 38)
		hint.Font = Enum.Font.GothamMedium
		hint.Text = if pet.owned then "Maximum level reached." else "Recruit companions to unlock permanent, level-scaled bonuses."
		hint.TextColor3 = SUBTLE
		hint.TextSize = 11
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.ZIndex = 22
		hint.Parent = card
	end

	card.Parent = host
end

local function updateSummary(state: any)
	if summaryLabel then
		local aggregate = bonusText(state.aggregateBonuses)
		if aggregate == "" then
			aggregate = "Equip pets to activate their bonuses."
		end
		summaryLabel.Text = "Equipped " .. tostring(state.equippedCount or 0) .. " / " .. tostring(state.maxEquipped or 3) .. "     " .. aggregate
	end
	if noticeLabel then
		noticeLabel.Text = tostring(state.message or "")
		noticeLabel.Visible = state.message ~= nil and state.message ~= ""
	end
end

local function render()
	local host = scroll
	if not host then
		return
	end
	for _, child in host:GetChildren() do
		child:Destroy()
	end
	local state = latest or fallbackState()
	updateSummary(state)
	local grid = Instance.new("UIGridLayout")
	grid.Name = "Grid"
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.CellSize = if host.AbsoluteSize.X < 650 then UDim2.new(1, -6, 0, 184) else UDim2.new(0.5, -7, 0, 184)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = host
	grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		host.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 10)
	end)
	for index, pet in ipairs(state.pets or {}) do
		buildPetCard(host, pet, state, index)
	end
end

local function requestState()
	Remotes.Get("RequestPets"):FireServer()
end

local function setOpen(open: boolean)
	if not panel then
		return
	end
	panel.Visible = open
	if open then
		requestState()
	end
end

local function ensureWired()
	if wired then
		return
	end
	wired = true
	Remotes.Get("PetState").OnClientEvent:Connect(function(state)
		latest = state
		render()
	end)
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("PetCollectionGui")
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "PetCollectionGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 26
	screen.Parent = playerGui
	gui = screen

	local openButton = Instance.new("TextButton")
	openButton.Name = "PetsButton"
	openButton.AnchorPoint = Vector2.new(1, 0.5)
	openButton.Position = UDim2.new(1, -18, 0.5, 92)
	openButton.Size = UDim2.fromOffset(112, 44)
	openButton.BackgroundColor3 = GREEN
	openButton.BorderSizePixel = 0
	openButton.Font = Enum.Font.FredokaOne
	openButton.Text = "\u{1F43E}  PETS"
	openButton.TextColor3 = WHITE
	openButton.TextSize = 16
	openButton.ZIndex = 10
	corner(openButton, 12)
	stroke(openButton, GREEN_DARK, 2, 0.25)
	openButton.Parent = screen
	toggleButton = openButton

	local window = Instance.new("Frame")
	window.Name = "PetWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(0.84, 0, 0.82, 0)
	window.BackgroundColor3 = Color3.fromRGB(234, 228, 202)
	window.BorderSizePixel = 0
	window.Visible = false
	window.ZIndex = 20
	corner(window, 16)
	stroke(window, GREEN_DARK, 2, 0.2)
	window.Parent = screen
	panel = window
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 390)
	constraint.MaxSize = Vector2.new(980, 720)
	constraint.Parent = window

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 12)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Companion Collection"
	title.TextColor3 = INK
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 21
	title.Parent = window

	local close = actionButton(window, "X", UDim2.new(1, -52, 0, 12), UDim2.fromOffset(36, 34), Color3.fromRGB(156, 78, 68))
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local summary = Instance.new("TextLabel")
	summary.BackgroundColor3 = PANEL_DARK
	summary.BorderSizePixel = 0
	summary.Position = UDim2.fromOffset(18, 52)
	summary.Size = UDim2.new(1, -36, 0, 42)
	summary.Font = Enum.Font.GothamBold
	summary.TextColor3 = GREEN_DARK
	summary.TextSize = 12
	summary.TextWrapped = true
	summary.ZIndex = 21
	corner(summary, 10)
	summary.Parent = window
	summaryLabel = summary

	local notice = Instance.new("TextLabel")
	notice.BackgroundColor3 = Color3.fromRGB(255, 243, 180)
	notice.BorderSizePixel = 0
	notice.Position = UDim2.fromOffset(18, 100)
	notice.Size = UDim2.new(1, -36, 0, 28)
	notice.Font = Enum.Font.GothamBold
	notice.TextColor3 = INK
	notice.TextSize = 12
	notice.Visible = false
	notice.ZIndex = 21
	corner(notice, 8)
	notice.Parent = window
	noticeLabel = notice

	local collection = Instance.new("ScrollingFrame")
	collection.Name = "Collection"
	collection.BackgroundTransparency = 1
	collection.BorderSizePixel = 0
	collection.Position = UDim2.fromOffset(18, 134)
	collection.Size = UDim2.new(1, -36, 1, -150)
	collection.ScrollBarThickness = 7
	collection.ScrollBarImageColor3 = GREEN_DARK
	collection.CanvasSize = UDim2.fromOffset(0, 0)
	collection.ZIndex = 21
	collection.Parent = window
	scroll = collection

	openButton.Activated:Connect(function()
		setOpen(not window.Visible)
	end)
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
	render()
end

function PetController.Refresh()
	requestState()
end

function PetController.Init()
	ensureWired()
	buildGui()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			setOpen(not (panel and panel.Visible))
		end
	end)
end

function PetController.Start()
	for _ = 1, 12 do
		if latest then
			return
		end
		requestState()
		task.wait(1)
	end
end

return PetController

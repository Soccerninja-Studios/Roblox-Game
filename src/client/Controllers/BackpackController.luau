--!strict
-- BackpackController: draws the Shop's "Packs" tab -- the five per-zone backpacks,
-- each with its own capacity ladder and its own auto-deposit unlock.
--
-- Mount(host) draws the list into a container the Shop owns, the same arrangement
-- AutoMowerController uses, so every purchase in the game lives in one window.
--
-- ZINDEX MATTERS HERE: the Shop's ScreenGui uses ZIndexBehavior.Global, so a child
-- is NOT automatically drawn above its parent -- everything is sorted by its raw
-- ZIndex across the whole GUI. The modal sits at 10 behind an opaque background, so
-- anything left at the default 1 is invisible behind it. These values mirror
-- UIController's helpers: 11 for cards, 12 for their contents, 13 for overlays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BackpackController = {}

local CREAM = Color3.fromRGB(247, 244, 234)
local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)

local listFrame: Frame? = nil
local latest: any = nil

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

-- Grass display name for the zone gate, so a locked card reads "reach Thicket"
-- rather than the internal key "Thicket".
local function zoneLabel(zone: string): string
	local def = GameConfig.GRASS_TYPES[zone]
	return if def and def.displayName then def.displayName else zone
end

-- The packs straight from config, so the tab can paint BEFORE, or entirely WITHOUT,
-- any server reply. Ownership is unknowable client-side, so these render in a
-- neutral "pending" state and the real snapshot replaces them on arrival.
local function configSnapshot(): any
	local list = {}
	for _, def in ipairs(GameConfig.BACKPACKS) do
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			desc = def.desc,
			goldCost = def.goldCost,
			diamondCost = def.diamondCost,
			colorR = def.color[1],
			colorG = def.color[2],
			colorB = def.color[3],
			owned = false,
			unlocked = false,
			equipped = false,
			level = 1,
			maxLevel = #def.levels,
			capacity = def.levels[1].capacity,
			autoDeposit = false,
			autoDepositCost = def.autoDepositCost,
			autoDepositDiamondCost = def.autoDepositDiamondCost,
			pending = true,
		})
	end
	return { packs = list, gold = 0, diamonds = 0 }
end

-- A price like "3,000g" or "22,000g + 20" with a diamond.
local function priceText(gold: number, diamonds: number): string
	if diamonds and diamonds > 0 then
		return formatNumber(gold) .. "g\n+ " .. formatNumber(diamonds) .. " \u{1F48E}"
	end
	return formatNumber(gold) .. "g"
end

local function makeButton(parent: Instance, y: number, text: string): TextButton
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, y)
	btn.Size = UDim2.fromOffset(136, 34)
	btn.BackgroundColor3 = GREEN
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.FredokaOne
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.AutoButtonColor = true
	btn.ZIndex = 12
	corner(btn, 9)
	btn.Parent = parent
	return btn
end

-- Card builder ---------------------------------------------------------------

local function buildCard(pack: any, order: number, currency: { gold: number, diamonds: number })
	local card = Instance.new("Frame")
	card.Name = "Pack_" .. tostring(pack.key)
	card.Size = UDim2.new(1, 0, 0, 132)
	card.BackgroundColor3 = PANEL
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.ZIndex = 11
	corner(card, 12)

	-- Colour strip down the left edge, so each pack is identifiable at a glance.
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 8, 1, -20)
	swatch.Position = UDim2.fromOffset(10, 10)
	swatch.BackgroundColor3 = Color3.fromRGB(pack.colorR, pack.colorG, pack.colorB)
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 12
	corner(swatch, 4)
	swatch.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(28, 10)
	name.Size = UDim2.new(1, -180, 0, 22)
	name.Font = Enum.Font.FredokaOne
	name.Text = pack.name
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
	desc.Text = pack.desc or ""
	desc.TextColor3 = SUBTLE
	desc.TextSize = 12
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.ZIndex = 12
	desc.Parent = card

	-- Capacity now, and what the next level would make it.
	local capText = "Holds " .. formatNumber(pack.capacity) .. " clippings"
	if pack.nextCapacity then
		capText = capText .. "  \u{2192}  " .. formatNumber(pack.nextCapacity)
	end
	local cap = Instance.new("TextLabel")
	cap.BackgroundTransparency = 1
	cap.Position = UDim2.fromOffset(28, 54)
	cap.Size = UDim2.new(1, -180, 0, 18)
	cap.Font = Enum.Font.GothamBold
	cap.Text = capText
	cap.TextColor3 = GREEN_DARK
	cap.TextSize = 13
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.ZIndex = 12
	cap.Parent = card

	-- Level pips: a filled segment per bought level, so progress along this pack's
	-- own ladder is readable without counting numbers.
	local pipHost = Instance.new("Frame")
	pipHost.BackgroundTransparency = 1
	pipHost.Position = UDim2.fromOffset(28, 80)
	pipHost.Size = UDim2.new(1, -190, 0, 10)
	pipHost.ZIndex = 12
	pipHost.Parent = card

	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.Padding = UDim.new(0, 4)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pipHost

	local maxLevel = math.max(1, pack.maxLevel or 1)
	for i = 1, maxLevel do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(1 / maxLevel, -4, 1, 0)
		pip.BackgroundColor3 = if pack.owned and i <= pack.level then GREEN else Color3.fromRGB(226, 222, 208)
		pip.BorderSizePixel = 0
		pip.LayoutOrder = i
		pip.ZIndex = 13
		corner(pip, 3)
		pip.Parent = pipHost
	end

	local levelText = Instance.new("TextLabel")
	levelText.BackgroundTransparency = 1
	levelText.Position = UDim2.fromOffset(28, 96)
	levelText.Size = UDim2.new(1, -190, 0, 18)
	levelText.Font = Enum.Font.GothamMedium
	levelText.Text = if pack.owned
		then "Level " .. pack.level .. " / " .. maxLevel
		else "Unlocks in " .. zoneLabel(pack.zone)
	levelText.TextColor3 = SUBTLE
	levelText.TextSize = 12
	levelText.TextXAlignment = Enum.TextXAlignment.Left
	levelText.ZIndex = 12
	levelText.Parent = card

	-- Buttons: wear/buy on top, then this pack's two upgrade tracks.
	local main = makeButton(card, 10, "")
	if pack.pending then
		-- Config-only card: ownership is still unknown, so show the price but promise
		-- nothing and stay unclickable.
		main.BackgroundColor3 = LOCKED
		main.Text = "\u{2026}"
		main.AutoButtonColor = false
		main.Active = false
	elseif pack.equipped then
		main.BackgroundColor3 = GREEN_DARK
		main.Text = "Worn \u{2713}"
		main.AutoButtonColor = false
		main.Active = false
	elseif pack.owned then
		main.BackgroundColor3 = GREEN
		main.Text = "Wear"
		main.Activated:Connect(function()
			Remotes.Get("EquipBackpack"):FireServer(pack.key)
		end)
	elseif not pack.unlocked then
		main.BackgroundColor3 = LOCKED
		main.Text = "Locked"
		main.AutoButtonColor = false
		main.Active = false
	else
		local affordable = currency.gold >= (pack.goldCost or 0)
			and currency.diamonds >= (pack.diamondCost or 0)
		main.BackgroundColor3 = if affordable then GOLD else LOCKED
		main.TextColor3 = if affordable then INK else Color3.fromRGB(255, 255, 255)
		main.Text = priceText(pack.goldCost or 0, pack.diamondCost or 0)
		main.Activated:Connect(function()
			Remotes.Get("PurchaseBackpack"):FireServer(pack.key)
		end)
	end

	-- Upgrades only make sense once the pack is actually yours.
	if pack.owned and not pack.pending then
		local up = makeButton(card, 50, "")
		if not pack.nextCost then
			up.BackgroundColor3 = LOCKED
			up.Text = "Max Size"
			up.AutoButtonColor = false
			up.Active = false
		else
			local affordable = currency.gold >= pack.nextCost
			up.BackgroundColor3 = if affordable then GOLD else LOCKED
			up.TextColor3 = if affordable then INK else Color3.fromRGB(255, 255, 255)
			up.Text = "Bigger  " .. formatNumber(pack.nextCost) .. "g"
			up.Activated:Connect(function()
				Remotes.Get("UpgradeBackpack"):FireServer(pack.key)
			end)
		end

		local auto = makeButton(card, 90, "")
		if pack.autoDeposit then
			auto.BackgroundColor3 = GREEN_DARK
			auto.Text = "Auto-Bank \u{2713}"
			auto.AutoButtonColor = false
			auto.Active = false
		else
			local affordable = currency.gold >= (pack.autoDepositCost or 0)
				and currency.diamonds >= (pack.autoDepositDiamondCost or 0)
			auto.BackgroundColor3 = if affordable then GOLD else LOCKED
			auto.TextColor3 = if affordable then INK else Color3.fromRGB(255, 255, 255)
			auto.Text = "Auto-Bank  " .. priceText(pack.autoDepositCost or 0, pack.autoDepositDiamondCost or 0)
			auto.TextSize = 12
			auto.Activated:Connect(function()
				Remotes.Get("UpgradeBackpack"):FireServer(pack.key, "autoDeposit")
			end)
		end
	end

	card.Parent = listFrame
end

-- Shown above the cards while we are still waiting on the server's first snapshot.
local function notice(host: Frame, text: string)
	local label = Instance.new("TextLabel")
	label.Name = "Notice"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
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
		return -- not mounted into the Shop yet; Mount() paints as soon as it is
	end

	-- Clear every GuiObject, not just Frames, so the waiting notice cannot survive
	-- underneath the cards. The UIListLayout is not a GuiObject and is kept.
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Fall back to config so the tab is NEVER blank, even if the server never
	-- answers at all. A real snapshot swaps these cards out the moment it lands.
	local snapshot = if latest and latest.packs then latest else configSnapshot()
	local currency = { gold = snapshot.gold or 0, diamonds = snapshot.diamonds or 0 }
	for i, pack in ipairs(snapshot.packs) do
		buildCard(pack, i, currency)
	end

	if snapshot ~= latest then
		notice(host, "Syncing your packs\u{2026}")
	end
end

-- Wiring, done once. Deliberately NOT called before the first paint: Remotes.Get
-- uses WaitForChild, which yields, and Mount runs inside UIController.Init().
local wired = false
local function ensureWired()
	if wired then
		return
	end
	wired = true
	Remotes.Get("BackpackState").OnClientEvent:Connect(function(state)
		latest = state
		render()
	end)
end

function BackpackController.Refresh()
	Remotes.Get("RequestBackpacks"):FireServer()
end

function BackpackController.Mount(host: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "PackList"
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

	-- Paint FIRST, straight from config. Nothing that can yield runs before this.
	render()

	task.spawn(function()
		ensureWired() -- connect before asking, so the reply cannot be missed
		for _ = 1, 12 do
			if latest then
				return
			end
			BackpackController.Refresh()
			task.wait(1)
		end
		if not latest then
			warn("[BackpackController] no pack state after 12 requests - is BackpackService running?")
		end
	end)
end

function BackpackController.Init()
	ensureWired()
end

return BackpackController

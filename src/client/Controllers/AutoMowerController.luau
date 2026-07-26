--!strict
-- AutoMowerController: the client-side Auto-Mowers list. It no longer owns a
-- window or a corner button -- UIController hands it the Shop modal's "Mowers"
-- tab and it draws the 5 cards straight into it, so the Shop is the single place
-- to buy anything. Each card lets you BUY a mower (gold + diamonds) once its ring
-- is unlocked, then DEPLOY / RECALL it. Deployed mowers show a live storage bar
-- that fills until the server auto-banks it to gold, and a toast pops when it does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AutoMowerController = {}

local player = Players.LocalPlayer

-- Palette (matches the HUD / Quest Board) ------------------------------------
local CREAM = Color3.fromRGB(247, 244, 234)
local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)
local DIAMOND = Color3.fromRGB(96, 196, 224)
local HEADER = Color3.fromRGB(70, 96, 60)
local RED = Color3.fromRGB(226, 92, 84)

-- State -----------------------------------------------------------------------
local gui: ScreenGui
local toastHolder: Frame
-- The card list lives inside the Shop modal now, so UIController hands us a host
-- frame to draw into. nil until it does, which render() treats as "not ready".
local listFrame: Frame? = nil
local latest: any = nil

-- Helpers ---------------------------------------------------------------------
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, thickness: number, col: Color3, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = col
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function formatNumber(n: number): string
	local rounded = math.floor(n + 0.5)
	local s = tostring(rounded)
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = string.sub(s, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return out
end

local function build()
	-- Toast-only ScreenGui. There is no button and no board any more: the list is
	-- rendered into the Shop by Mount().
	gui = Instance.new("ScreenGui")
	gui.Name = "AutoMowerToasts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 19
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 1)
	toastHolder.Position = UDim2.new(0.5, 0, 1, -80)
	toastHolder.Size = UDim2.new(0, 360, 0, 0)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Parent = toastHolder
end

-- Zone keys like "Moss" are internal bookkeeping; players know the grass by its
-- display name, so lock messages use that instead.
local function zoneLabel(zone: string): string
	local def = GameConfig.GRASS_TYPES[zone]
	if def and def.displayName then
		return def.displayName
	end
	return zone
end

-- The 5 mowers straight from config. This lets the tab paint BEFORE, or entirely
-- WITHOUT, any server reply. Ownership is unknowable client-side, so these render
-- in a neutral "pending" state and the real snapshot replaces them on arrival.
local function configSnapshot(): any
	local list = {}
	for _, def in ipairs(GameConfig.AUTO_MOWERS) do
		table.insert(list, {
			key = def.key,
			name = def.name,
			zone = def.zone,
			desc = def.desc,
			ratePerSec = def.ratePerSec,
			storageCap = def.storageCap,
			goldCost = def.goldCost,
			diamondCost = def.diamondCost,
			bodyColorR = def.bodyColor[1],
			bodyColorG = def.bodyColor[2],
			bodyColorB = def.bodyColor[3],
			owned = false,
			deployed = false,
			unlocked = false,
			storage = 0,
			pending = true,
		})
	end
	return { mowers = list, gold = 0, diamonds = 0 }
end

-- Card builder ----------------------------------------------------------------
local function buildCard(mower: any, order: number, currency: { gold: number, diamonds: number })
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 116)
	card.BackgroundColor3 = PANEL
	card.LayoutOrder = order
	corner(card, 14)
	stroke(card, 2, Color3.fromRGB(226, 220, 202))

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 8, 1, -20)
	swatch.Position = UDim2.new(0, 12, 0, 10)
	swatch.BackgroundColor3 = Color3.fromRGB(mower.bodyColorR or 120, mower.bodyColorG or 196, mower.bodyColorB or 92)
	swatch.BorderSizePixel = 0
	corner(swatch, 4)
	swatch.ZIndex = 12
	swatch.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 30, 0, 10)
	name.Size = UDim2.new(1, -140, 0, 24)
	name.Font = Enum.Font.FredokaOne
	name.Text = mower.name
	name.TextColor3 = INK
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.ZIndex = 12
	name.Parent = card

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.new(0, 30, 0, 36)
	info.Size = UDim2.new(1, -140, 0, 18)
	info.Font = Enum.Font.Gotham
	info.Text = mower.desc .. "  \u{00B7}  +" .. formatNumber(mower.ratePerSec) .. "/s"
	info.TextColor3 = SUBTLE
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextScaled = true
	info.ZIndex = 12
	info.Parent = card

	-- Storage bar (only meaningful when deployed).
	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 30, 0, 62)
	barBg.Size = UDim2.new(1, -170, 0, 14)
	barBg.BackgroundColor3 = Color3.fromRGB(232, 230, 220)
	barBg.BorderSizePixel = 0
	corner(barBg, 7)
	barBg.ZIndex = 12
	barBg.Parent = card

	local pct = math.clamp(mower.storage / math.max(1, mower.storageCap), 0, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	corner(fill, 7)
	fill.ZIndex = 13
	fill.Parent = barBg

	local barText = Instance.new("TextLabel")
	barText.BackgroundTransparency = 1
	barText.Position = UDim2.new(0, 30, 0, 80)
	barText.Size = UDim2.new(1, -170, 0, 18)
	barText.Font = Enum.Font.GothamMedium
	barText.TextXAlignment = Enum.TextXAlignment.Left
	barText.TextScaled = true
	barText.TextColor3 = SUBTLE
	if mower.deployed then
		barText.Text = "Storage " .. formatNumber(mower.storage) .. " / " .. formatNumber(mower.storageCap) .. " \u{2192} auto-banks to gold"
	else
		barBg.Visible = false
		barText.Text = "Not deployed"
	end
	barText.ZIndex = 13
	barText.Parent = card

	-- Action button (Buy / Deploy / Recall / Locked).
	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -14, 0.5, 0)
	action.Size = UDim2.new(0, 118, 0, 74)
	action.Font = Enum.Font.FredokaOne
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.TextScaled = true
	action.AutoButtonColor = true
	corner(action, 12)
	action.ZIndex = 12
	action.Parent = card

	local actionPad = Instance.new("UIPadding")
	actionPad.PaddingLeft = UDim.new(0, 8)
	actionPad.PaddingRight = UDim.new(0, 8)
	actionPad.PaddingTop = UDim.new(0, 8)
	actionPad.PaddingBottom = UDim.new(0, 8)
	actionPad.Parent = action

	if mower.pending then
		-- Config-only card: ownership and unlock state are still unknown, so show the
		-- price but promise nothing and stay unclickable.
		action.BackgroundColor3 = LOCKED
		action.Text = formatNumber(mower.goldCost) .. "g\n\u{2026}"
		action.AutoButtonColor = false
		action.Active = false
	elseif not mower.unlocked then
		action.BackgroundColor3 = LOCKED
		action.Text = "Locked\n(reach " .. zoneLabel(mower.zone) .. ")"
		action.AutoButtonColor = false
		action.Active = false
	elseif not mower.owned then
		local canAfford = currency.gold >= mower.goldCost and currency.diamonds >= mower.diamondCost
		action.BackgroundColor3 = if canAfford then GOLD else LOCKED
		action.TextColor3 = if canAfford then INK else Color3.fromRGB(240, 240, 236)
		action.Text = formatNumber(mower.goldCost) .. "g\n+ " .. formatNumber(mower.diamondCost) .. " \u{1F48E}"
		action.Activated:Connect(function()
			Remotes.Get("PurchaseAutoMower"):FireServer(mower.key)
		end)
	elseif mower.deployed then
		action.BackgroundColor3 = RED
		action.Text = "Recall"
		action.Activated:Connect(function()
			Remotes.Get("ToggleAutoMower"):FireServer(mower.key)
		end)
	else
		action.BackgroundColor3 = GREEN
		action.Text = "Deploy"
		action.Activated:Connect(function()
			Remotes.Get("ToggleAutoMower"):FireServer(mower.key)
		end)
	end

	card.ZIndex = 11
	card.Parent = listFrame
end

-- Shown instead of an empty page while we wait for the server's first snapshot.
local function notice(host: Frame, text: string)
	local label = Instance.new("TextLabel")
	label.Name = "Notice"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 60)
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = SUBTLE
	label.TextSize = 15
	label.TextWrapped = true
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
	local snapshot = if latest and latest.mowers then latest else configSnapshot()
	local currency = { gold = snapshot.gold or 0, diamonds = snapshot.diamonds or 0 }
	for i, mower in ipairs(snapshot.mowers) do
		buildCard(mower, i, currency)
	end

	if snapshot ~= latest then
		notice(host, "Syncing your mowers\u{2026}")
	end
end

-- Toast when a mower banks -----------------------------------------------------
local function showToast(text: string)
	if not toastHolder then
		return -- build() has not run yet; a missed toast is better than an error
	end
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, 40)
	toast.BackgroundColor3 = GREEN_DARK
	corner(toast, 10)
	toast.Parent = toastHolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = toast

	task.delay(3, function()
		toast:Destroy()
	end)
end

-- Public API ------------------------------------------------------------------
-- Remote wiring, done once. This used to live in Init(), which created a race: the
-- Shop modal is built during UIController.Init(), so its first request could be
-- sent BEFORE this controller's Init() had connected AutoMowerState. The reply was
-- then dropped and nothing ever repainted the tab. Mount() now wires up first.
local wired = false
local function ensureWired()
	if wired then
		return
	end
	wired = true

	Remotes.Get("AutoMowerState").OnClientEvent:Connect(function(state)
		latest = state
		render() -- no-op until the Shop tab is mounted
	end)

	Remotes.Get("AutoMowerBanked").OnClientEvent:Connect(function(payload)
		showToast("\u{1F69C} " .. tostring(payload.name) .. " banked +" .. formatNumber(payload.gold or 0) .. "g")
	end)
end

-- Ask the server for a fresh snapshot. UIController calls this whenever the Shop
-- opens on the Mowers tab, so prices and storage bars are never stale.
function AutoMowerController.Refresh()
	Remotes.Get("RequestAutoMowers"):FireServer()
end

-- Called once by UIController with the Shop modal's Mowers page. We draw the
-- cards into a holder inside it instead of opening a window of our own.
-- NOTE ON ZINDEX: the Shop's ScreenGui uses ZIndexBehavior.Global, so a child is
-- NOT automatically drawn above its parent -- every element is sorted by its raw
-- ZIndex across the whole GUI. The modal sits at 10 behind an opaque background,
-- so anything left at the default 1 is hidden by it. These values mirror
-- UIController's helpers: 11 for cards, 12 for their contents, 13 for overlays.
function AutoMowerController.Mount(host: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "MowerList"
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

	-- Paint FIRST, straight from config. Remotes.Get uses WaitForChild, which
	-- YIELDS, and Mount runs inside UIController.Init() -- so touching a remote
	-- before painting can stall the first paint and leave the tab empty. Nothing
	-- below this line is allowed to block the cards.
	render()

	-- Wiring and requesting both happen off the Init thread. The server makes us
	-- wait while it loads the profile (up to 10s on a cold join) and only answers a
	-- request -- it never broadcasts to a player with nothing deployed -- so keep
	-- asking until a snapshot lands rather than trusting a single attempt.
	task.spawn(function()
		ensureWired() -- connect before asking, so the reply cannot be missed
		for _ = 1, 12 do
			if latest then
				return
			end
			AutoMowerController.Refresh()
			task.wait(1)
		end
		if not latest then
			warn("[AutoMowerController] no mower state after 12 requests - is AutoMowerService running?")
		end
	end)
end

function AutoMowerController.Init()
	build()
	ensureWired() -- harmless if Mount() already did it
end

function AutoMowerController.Start()
	-- Ask once so deployed mowers respawn on rejoin even before the panel opens.
	task.wait(1)
	Remotes.Get("RequestAutoMowers"):FireServer()
end

return AutoMowerController

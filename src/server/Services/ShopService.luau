--!strict
-- ShopService: builds a physical shop stall the player can walk into. Standing in
-- the zone opens the upgrade menu on the client (client-side proximity check reads
-- the ShopZone part built here). The menu can also be opened any time via an
-- on-screen button, so the stall is a convenience, not a requirement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	return part
end

local function buildShop()
	local center = GameConfig.SHOP_POSITION
	local wood = Color3.fromRGB(120, 82, 48)
	local darkWood = Color3.fromRGB(86, 58, 34)
	local cloth = Color3.fromRGB(196, 70, 70)

	local shop = Instance.new("Model")
	shop.Name = "Shop"

	-- Floor pad
	local floor = makePart("Floor", Vector3.new(14, 1, 12), CFrame.new(center + Vector3.new(0, 0.5, 0)), darkWood, Enum.Material.WoodPlanks)
	floor.Parent = shop

	-- Four corner posts
	local postSize = Vector3.new(0.8, 9, 0.8)
	local offsets = {
		Vector3.new(-6, 5, -5),
		Vector3.new(6, 5, -5),
		Vector3.new(-6, 5, 5),
		Vector3.new(6, 5, 5),
	}
	for i, off in offsets do
		local post = makePart("Post" .. i, postSize, CFrame.new(center + off), wood, Enum.Material.Wood)
		post.Parent = shop
	end

	-- Counter the shopkeeper stands behind
	local counter = makePart("Counter", Vector3.new(11, 3, 1.6), CFrame.new(center + Vector3.new(0, 2, 4.2)), wood, Enum.Material.WoodPlanks)
	counter.Parent = shop

	-- Striped awning / roof (two angled slabs)
	local roofLeft = makePart("RoofLeft", Vector3.new(8, 0.5, 13), CFrame.new(center + Vector3.new(-3.2, 9.6, 0)) * CFrame.Angles(0, 0, math.rad(22)), cloth, Enum.Material.Fabric)
	roofLeft.Parent = shop
	local roofRight = makePart("RoofRight", Vector3.new(8, 0.5, 13), CFrame.new(center + Vector3.new(3.2, 9.6, 0)) * CFrame.Angles(0, 0, math.rad(-22)), Color3.fromRGB(238, 232, 210), Enum.Material.Fabric)
	roofRight.Parent = shop

	-- Floating "SHOP" sign
	local signPost = makePart("SignPost", Vector3.new(0.4, 4, 0.4), CFrame.new(center + Vector3.new(0, 12, 0)), darkWood, Enum.Material.Wood)
	signPost.Parent = shop
	local sign = makePart("Sign", Vector3.new(7, 2.4, 0.4), CFrame.new(center + Vector3.new(0, 13.6, 0)), Color3.fromRGB(60, 40, 24), Enum.Material.WoodPlanks)
	sign.Parent = shop

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SignGui"
	billboard.Size = UDim2.fromOffset(220, 80)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0.3)
	billboard.AlwaysOnTop = false
	billboard.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.BackgroundTransparency = 1
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.Text = "\u{1F6D2} SHOP"
	signLabel.TextColor3 = Color3.fromRGB(255, 236, 170)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Parent = billboard

	-- Invisible trigger the client uses for proximity detection
	local zone = Instance.new("Part")
	zone.Name = "ShopZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Size = Vector3.new(GameConfig.SHOP_ZONE_RADIUS * 2, 12, GameConfig.SHOP_ZONE_RADIUS * 2)
	zone.CFrame = CFrame.new(center + Vector3.new(0, 6, 0))
	zone.Parent = shop
	shop.PrimaryPart = zone

	shop.Parent = Workspace
end

function ShopService.Start()
	buildShop()
	print("[ShopService] Shop stall built")
end

return ShopService

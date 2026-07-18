--!strict
-- ClippingsService: clippings dropped by mowing land on the ground as physical
-- pickups. The player collects them by walking near them; the collect radius is
-- grown by the Clipping Magnet skill, which is what gives that upgrade a purpose.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local StatCalculator = require(Shared.StatCalculator)
local Remotes = require(Shared.Remotes)

local ClippingsService = {}

local PlayerDataService
local pickupFolder: Folder
local collecting: { [BasePart]: boolean } = {}

local NORMAL_COLOR = Color3.fromRGB(150, 224, 92)
local CRIT_COLOR = Color3.fromRGB(255, 205, 54)

local function makePickup(restPos: Vector3, isCrit: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = "Clipping"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.75, 0.75, 0.75)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = isCrit and CRIT_COLOR or NORMAL_COLOR
	p.CFrame = CFrame.new(restPos)

	local light = Instance.new("PointLight")
	light.Brightness = 1.5
	light.Range = 6
	light.Color = p.Color
	light.Parent = p
	return p
end

-- Spawn a clipping pickup that tosses from `fromPos` and settles on the ground.
function ClippingsService.Drop(owner: Player, fromPos: Vector3, value: number, isCrit: boolean)
	-- Find the ground beneath the drop point, ignoring grass + other pickups.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { pickupFolder }
	local kingdom = Workspace:FindFirstChild("Kingdom")
	if kingdom then
		table.insert(ignore, kingdom)
	end
	rayParams.FilterDescendantsInstances = ignore

	local scatter = Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)
	local result = Workspace:Raycast(fromPos, Vector3.new(0, -300, 0), rayParams)
	local restPos = (result and (result.Position + Vector3.new(0, 0.8, 0)) or (fromPos - Vector3.new(0, 2, 0)))
		+ scatter

	local pickup = makePickup(fromPos, isCrit)
	pickup:SetAttribute("Owner", owner.UserId)
	pickup:SetAttribute("Value", value)
	pickup:SetAttribute("Crit", isCrit)
	pickup.Parent = pickupFolder

	-- Little toss arc onto the ground.
	TweenService
		:Create(pickup, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(restPos) })
		:Play()

	Debris:AddItem(pickup, GameConfig.PICKUP_LIFETIME)
end

local function collect(pickup: BasePart, player: Player, root: BasePart)
	collecting[pickup] = true
	local value = pickup:GetAttribute("Value") or 0
	local isCrit = pickup:GetAttribute("Crit") or false

	local tween = TweenService:Create(
		pickup,
		TweenInfo.new(GameConfig.PICKUP_MAGNET_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = root.CFrame, Size = Vector3.new(0.1, 0.1, 0.1) }
	)
	tween.Completed:Connect(function()
		if pickup.Parent then
			PlayerDataService.AddClippings(player, value)
			Remotes.Get("ClippingCollected"):FireClient(player, root.Position, value, isCrit)
			pickup:Destroy()
		end
		collecting[pickup] = nil
	end)
	tween:Play()
end

function ClippingsService.Init(services)
	PlayerDataService = services.PlayerDataService

	pickupFolder = Workspace:FindFirstChild("Clippings") :: Folder
	if not pickupFolder then
		pickupFolder = Instance.new("Folder")
		pickupFolder.Name = "Clippings"
		pickupFolder.Parent = Workspace
	end
end

function ClippingsService.Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		-- Throttle collection checks to ~15Hz; per-frame is wasteful.
		accumulator += dt
		if accumulator < 1 / 15 then
			return
		end
		accumulator = 0

		-- Cache each player's collect range + root for this pass.
		local rangeSq: { [number]: number } = {}
		local roots: { [number]: BasePart } = {}
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local profile = PlayerDataService.Get(player)
			if root and profile then
				local range = StatCalculator.GetCollectRange(profile.skills)
				rangeSq[player.UserId] = range * range
				roots[player.UserId] = root
			end
		end

		for _, pickup in pickupFolder:GetChildren() do
			if not pickup:IsA("BasePart") or collecting[pickup] then
				continue
			end
			local ownerId = pickup:GetAttribute("Owner")
			local root = ownerId and roots[ownerId]
			if not root then
				continue
			end
			if (root.Position - pickup.Position).Magnitude <= 0 then
				continue
			end
			if (root.Position - pickup.Position):Dot(root.Position - pickup.Position) <= rangeSq[ownerId] then
				local player = Players:GetPlayerByUserId(ownerId)
				if player then
					collect(pickup, player, root)
				end
			end
		end
	end)

	print("[ClippingsService] Clipping pickups ready.")
end

return ClippingsService

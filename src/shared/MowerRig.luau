--!strict
-- MowerRig: turns an arbitrary toolbox model into a safe, drivable auto-mower.
--
-- The mower models are free-model imports, and they arrive in wildly different
-- shapes: one is a full A-Chassis vehicle with 16 LocalScripts, remotes and two
-- ScreenGuis; one is a humanoid rig with Motor6Ds; one is ~200 unanchored
-- sub-stud parts around a Seat. Dropped into the world as-is they would run
-- their own scripts, seat players, fall apart, or throw the LoadUnownedAsset
-- error we already hit with the Gardener's bundled TextureConfiguration scripts.
--
-- So nothing here trusts the model's internals. We work purely by class:
--   Strip      remove every script, remote, GUI, joint and animation
--   Rigidify   weld every part to ONE anchored driver part
--   Prepare     strip + scale to a sane size + rigidify
--
-- The result is a single rigid assembly whose PrimaryPart can be tweened around,
-- which is exactly what AutoMowerService needs. This is name-agnostic on purpose:
-- it works on the two models never fully inspected, and on any mower added later.

local MowerRig = {}

-- Classes that must never survive into a spawned mower.
local JUNK_CLASSES = {
	"LuaSourceContainer", -- Script / LocalScript / ModuleScript
	"RemoteEvent",
	"RemoteFunction",
	"BindableEvent",
	"BindableFunction",
	"ScreenGui",
	"SurfaceGui",
	"BillboardGui",
	"ProximityPrompt",
	"ClickDetector",
	"KeyframeSequence",
	"Animation",
	"Animator",
	"Humanoid",
	"Tool",
}

-- Anything that could re-pose or physically drive the assembly. We re-weld from
-- scratch, so every existing joint and constraint goes.
local MOTION_CLASSES = {
	"JointInstance", -- Motor6D, Weld, ManualWeld, Snap, Rotate, Motor, Glue
	"Constraint", -- HingeConstraint, WeldConstraint is separate, etc.
	"WeldConstraint",
	"NoCollisionConstraint",
	"BodyMover", -- BodyVelocity, BodyPosition, ...
	"Attachment",
}

local function isAnyClass(inst: Instance, classes: { string }): boolean
	for _, className in classes do
		if inst:IsA(className) then
			return true
		end
	end
	return false
end

-- Remove scripts, remotes, GUIs, joints and animations. Returns how many
-- instances were destroyed (handy for a one-line sanity log).
function MowerRig.Strip(model: Model): number
	local removed = 0
	-- Snapshot first: we are mutating the tree while walking it.
	for _, inst in model:GetDescendants() do
		if inst.Parent ~= nil then
			if isAnyClass(inst, JUNK_CLASSES) or isAnyClass(inst, MOTION_CLASSES) then
				inst:Destroy()
				removed += 1
			end
		end
	end

	-- Seats are BaseParts, so they carry geometry we want to keep -- but a player
	-- must never be able to sit on a working mower and ride it around.
	for _, inst in model:GetDescendants() do
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
			pcall(function()
				(inst :: any).Disabled = true
			end)
		end
	end

	return removed
end

-- Pick the part that will drive the whole assembly: the model's own PrimaryPart
-- if it still has a valid one, otherwise the largest part by volume (for these
-- models that reliably lands on the chassis/body rather than a bolt or a wheel).
local function chooseDriver(model: Model): BasePart?
	local existing = model.PrimaryPart
	if existing and existing:IsDescendantOf(model) then
		return existing
	end

	local best: BasePart? = nil
	local bestVolume = -1
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			local size = inst.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				bestVolume = volume
				best = inst
			end
		end
	end
	return best
end

-- Weld every part rigidly to one anchored driver part.
--
-- Only the driver is anchored: tweening an anchored part moves it authoritatively
-- with no physics fighting us, and the unanchored welded parts ride along. If we
-- anchored everything instead, the welds would be pointless and the model would
-- tear apart the moment the driver moved.
function MowerRig.Rigidify(model: Model): BasePart?
	local driver = chooseDriver(model)
	if not driver then
		return nil
	end

	model.PrimaryPart = driver
	driver.Anchored = true
	driver.CanCollide = false
	driver.CanQuery = false
	driver.CanTouch = false

	local driverCF = driver.CFrame
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst ~= driver then
			inst.Anchored = false
			inst.Massless = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false

			local weld = Instance.new("Weld")
			weld.Name = "MowerWeld"
			weld.Part0 = driver
			weld.Part1 = inst
			-- C0 is the part's pose expressed relative to the driver, so the model
			-- keeps the exact shape it was built in.
			weld.C0 = driverCF:Inverse() * inst.CFrame
			weld.Parent = driver
		end
	end

	return driver
end

-- Scale the model so its longest horizontal axis is roughly `targetLength` studs.
-- The source models range from a ~2-stud bot to a full-size drivable vehicle, and
-- an unscaled Reel Mower would dwarf the player.
function MowerRig.ScaleToLength(model: Model, targetLength: number)
	if targetLength <= 0 then
		return
	end
	local ok, extents = pcall(function()
		return model:GetExtentsSize()
	end)
	if not ok or typeof(extents) ~= "Vector3" then
		return
	end

	local longest = math.max(extents.X, extents.Z)
	if longest <= 0.01 then
		return
	end

	local factor = targetLength / longest
	-- Don't bother with trivial rescales, and never invert the model.
	if factor <= 0 or math.abs(factor - 1) < 0.02 then
		return
	end
	pcall(function()
		model:ScaleTo(factor)
	end)
end

-- How high the driver part's origin sits above the model's lowest point.
--
-- The driver is whichever part is largest, and its origin is nowhere near the
-- bottom of the assembly, so placing the driver AT ground level leaves the model
-- floating (or buried). Positioning the driver at groundY + this offset seats the
-- model exactly on the ground instead.
function MowerRig.GroundOffset(model: Model, driver: BasePart): number
	local ok, boxCF, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or typeof(boxCF) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then
		return 0
	end
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	return math.max(0, driver.Position.Y - bottomY)
end

-- Which way is "forwards" for this model?
--
-- CFrame.lookAt aims a part's -Z axis at its target, but each of these models was
-- built facing whatever direction its author felt like -- which is why the Push
-- Mower drove sideways. We measure the assembly in the DRIVER's own axes: a mower
-- is longer front-to-back than side-to-side, so if the model turns out to be
-- longer along local X than local Z, its forward axis is X and it needs a
-- 90-degree correction.
function MowerRig.DriveYaw(model: Model, driver: BasePart): number
	local inverse = driver.CFrame:Inverse()
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			local half = inst.Size * 0.5
			-- All 8 corners, so a rotated part still measures correctly.
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = inst.CFrame
							* CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)
						local rel = (inverse * corner).Position
						minX = math.min(minX, rel.X)
						maxX = math.max(maxX, rel.X)
						minZ = math.min(minZ, rel.Z)
						maxZ = math.max(maxZ, rel.Z)
					end
				end
			end
		end
	end

	if minX == math.huge then
		return 0
	end

	local spanX = maxX - minX
	local spanZ = maxZ - minZ
	-- The 1.15 margin stops near-square models (the humanoid bot) from flip-flopping
	-- between orientations on tiny measurement differences.
	if spanX > spanZ * 1.15 then
		return 90
	end
	return 0
end

-- Full pipeline. Returns the driver part, or nil if the model had no parts at all
-- (in which case the caller should fall back to a built-from-scratch mower).
function MowerRig.Prepare(model: Model, targetLength: number?): BasePart?
	MowerRig.Strip(model)
	-- Only rescale when explicitly asked to. 0 or nil means "keep the size the model
	-- was authored at in ReplicatedStorage", which is the default: forcing every
	-- mower to one uniform length made the humanoid bot tiny and the harvester huge.
	if targetLength and targetLength > 0 then
		MowerRig.ScaleToLength(model, targetLength)
	end

	local driver = MowerRig.Rigidify(model)
	if driver then
		-- Cached as attributes so the mower brain can read them every tick without
		-- re-measuring a 200-part model.
		model:SetAttribute("GroundOffset", MowerRig.GroundOffset(model, driver))
		model:SetAttribute("DriveYaw", MowerRig.DriveYaw(model, driver))
	end
	return driver
end

return MowerRig

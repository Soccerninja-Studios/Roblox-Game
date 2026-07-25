--!strict
-- AdminService: lets whitelisted testers grant themselves gold/diamonds in-game
-- via the Admin panel, so you don't have to grind resources to test a feature.
--
-- The whitelist lives in GameConfig.ADMINS (a list of Roblox usernames). The
-- server re-validates EVERY request against it, so a non-admin firing the remote
-- is simply ignored. Grants go through PlayerDataService.GrantCurrency, which
-- pushes a fresh state snapshot to the client so the HUD updates instantly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AdminService = {}

local PlayerDataService: any

-- Clamp any single grant so a fat-fingered amount can't overflow the economy.
local MAX_GRANT = 1_000_000_000

local function isAdmin(player: Player): boolean
	for _, name in GameConfig.ADMINS do
		if name == player.Name then
			return true
		end
	end
	return false
end

local function onGrant(player: Player, gold: any, diamonds: any)
	if not isAdmin(player) then
		return -- silently ignore anyone not on the whitelist
	end
	local g = math.clamp(math.floor(tonumber(gold) or 0), 0, MAX_GRANT)
	local d = math.clamp(math.floor(tonumber(diamonds) or 0), 0, MAX_GRANT)
	if g == 0 and d == 0 then
		return
	end
	if PlayerDataService then
		PlayerDataService.GrantCurrency(player, g, d)
		print(string.format("[AdminService] %s granted +%d gold, +%d diamonds", player.Name, g, d))
	end
end

function AdminService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	Remotes.Get("AdminGrantCurrency").OnServerEvent:Connect(onGrant)
end

function AdminService.Start() end

return AdminService

--!strict
-- Server entry point: loads, initializes, and starts every service in Services/.
-- Each service is a ModuleScript that may expose Init() and Start().
--
-- Every phase is wrapped so a single broken service can't take down the whole
-- server. Any failure is reported in the Output with the service's name, so a bad
-- module is easy to spot instead of silently killing everything.

local servicesFolder = script:WaitForChild("Services")

local services: { [string]: any } = {}

-- Load all service modules.
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			services[child.Name] = result
		else
			warn(`[Server] FAILED to load {child.Name}: {result}`)
		end
	end
end

-- Init phase: set up state and connections (services may reference each other here).
for name, service in services do
	if type(service.Init) == "function" then
		local ok, err = pcall(service.Init, services)
		if ok then
			print(`[Server] Initialized {name}`)
		else
			warn(`[Server] {name}.Init errored: {err}`)
		end
	end
end

-- Start phase: begin running logic.
for name, service in services do
	if type(service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(service.Start)
			if not ok then
				warn(`[Server] {name}.Start errored: {err}`)
			end
		end)
		print(`[Server] Started {name}`)
	end
end

print("[Server] Mow the Kingdom server is running!")

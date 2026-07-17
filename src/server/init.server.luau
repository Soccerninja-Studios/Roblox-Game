--!strict
-- Server entry point: loads, initializes, and starts every service in Services/.
-- Each service is a ModuleScript that may expose Init() and Start().

local servicesFolder = script:WaitForChild("Services")

local services: { [string]: any } = {}

-- Load all service modules
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		services[child.Name] = require(child)
	end
end

-- Init phase: set up state and connections (services may reference each other here)
for name, service in services do
	if type(service.Init) == "function" then
		service.Init(services)
		print(`[Server] Initialized {name}`)
	end
end

-- Start phase: begin running logic
for name, service in services do
	if type(service.Start) == "function" then
		task.spawn(service.Start)
		print(`[Server] Started {name}`)
	end
end

print("[Server] Mow the Kingdom server is running!")

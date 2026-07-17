--!strict
-- Client entry point: loads, initializes, and starts every controller in Controllers/.

local controllersFolder = script:WaitForChild("Controllers")

local controllers: { [string]: any } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		controllers[child.Name] = require(child)
	end
end

for name, controller in controllers do
	if type(controller.Init) == "function" then
		controller.Init(controllers)
		print(`[Client] Initialized {name}`)
	end
end

for name, controller in controllers do
	if type(controller.Start) == "function" then
		task.spawn(controller.Start)
		print(`[Client] Started {name}`)
	end
end

print("[Client] Mow the Kingdom client loaded!")

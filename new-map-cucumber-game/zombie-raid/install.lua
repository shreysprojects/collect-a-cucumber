-- install.lua: ONE execute_luau (edit mode). Pulls every zombie-raid file from the loopback server
-- (pets-remake/serve.ps1 -Port 8771 -Root new-map-cucumber-game/zombie-raid), compile-checks it, writes
-- ReplicatedStorage.Modules.ZombieCatalog, ServerScriptService.ZombieRaidService / DefenceService,
-- StarterPlayerScripts.ZombieRaidClient, runs build_zombies.lua (ServerStorage.Assets.Zombies) and
-- build_bat.lua (StarterPack.Bat with BatServer inside), and sets DayNightCycle.NightDurationSeconds.
-- 2026-09-12: ServerScriptService.BuildHealthService (build-mode/BuildHealthService.server.lua) must ALSO be installed
-- (serve build-mode/ on its own port: serve.ps1 serves one folder); Bash routes build damage through its BuildAPI.
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8771/"
local function fetch(name)
	local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
	assert(ok, "fetch " .. name .. ": " .. tostring(body))
	return (body:gsub("\r\n", "\n"))
end
local function compiled(name, src)
	local fn, err = loadstring(src)
	assert(fn, name .. ": " .. tostring(err))
	return fn
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local sources = {}
for _, name in ipairs({"ZombieCatalog.lua", "ZombieRaidService.server.lua", "DefenceService.server.lua", "ZombieRaidClient.client.lua", "BatServer.server.lua", "build_zombies.lua", "build_bat.lua"}) do
	local src = fetch(name)
	compiled(name, src)
	sources[name] = src
end

local function ensure(parent, name, className)
	local inst = parent:FindFirstChild(name)
	if not inst or inst.ClassName ~= className then
		if inst then inst:Destroy() end
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

local catalog = ensure(ReplicatedStorage:WaitForChild("Modules"), "ZombieCatalog", "ModuleScript")
catalog.Source = sources["ZombieCatalog.lua"]
local raid = ensure(ServerScriptService, "ZombieRaidService", "Script")
raid.Source = sources["ZombieRaidService.server.lua"]
local defence = ensure(ServerScriptService, "DefenceService", "Script")
defence.Source = sources["DefenceService.server.lua"]
local client = ensure(StarterPlayer:WaitForChild("StarterPlayerScripts"), "ZombieRaidClient", "LocalScript")
client.Source = sources["ZombieRaidClient.client.lua"]

local zombieReport = compiled("build_zombies.lua", sources["build_zombies.lua"])()
local batReport = compiled("build_bat.lua", sources["build_bat.lua"])(sources["BatServer.server.lua"])

local dayNight = ServerScriptService:FindFirstChild("DayNightCycle")
local nightBefore = dayNight and dayNight:GetAttribute("NightDurationSeconds")
if dayNight then dayNight:SetAttribute("NightDurationSeconds", 90) end

print(("[install] ZombieCatalog %d, ZombieRaidService %d, DefenceService %d, ZombieRaidClient %d | %s | %s | night %s -> 90"):format(
	#catalog.Source, #raid.Source, #defence.Source, #client.Source, tostring(zombieReport), tostring(batReport), tostring(nightBefore)))

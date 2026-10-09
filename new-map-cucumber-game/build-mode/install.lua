-- install.lua: ONE execute_luau (edit mode). Pulls every build-mode file from the loopback server
-- (pets-remake/serve.ps1 -Port 8770 -Root new-map-cucumber-game/build-mode), compile-checks it, sets
-- the script sources (ReplicatedStorage.Modules.BuildCatalog, ServerScriptService.BuildService) and
-- runs build_buildmenu.lua, which rebuilds StarterGui.BuildMenu with BuildMenuClient inside.
-- ServerStorage.Builds must already be sorted into category subfolders (organize step, 2026-09-10).
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8770/"
local function fetch(name)
	local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
	assert(ok, "fetch " .. name .. ": " .. tostring(body))
	body = body:gsub("\r\n", "\n")
	return body
end
local function compiled(name, src)
	local fn, err = loadstring(src)
	assert(fn, name .. ": " .. tostring(err))
	return fn
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

local sources = {}
for _, name in ipairs({"BuildCatalog.lua", "BuildService.server.lua", "BuildMenuClient.client.lua", "build_buildmenu.lua"}) do
	local src = fetch(name)
	compiled(name, src)
	sources[name] = src
end

local modules = ReplicatedStorage:WaitForChild("Modules")
local catalog = modules:FindFirstChild("BuildCatalog")
if not catalog then
	catalog = Instance.new("ModuleScript")
	catalog.Name = "BuildCatalog"
	catalog.Parent = modules
end
catalog.Source = sources["BuildCatalog.lua"]

local service = ServerScriptService:FindFirstChild("BuildService")
if not service then
	service = Instance.new("Script")
	service.Name = "BuildService"
	service.Parent = ServerScriptService
end
service.Source = sources["BuildService.server.lua"]

compiled("build_buildmenu.lua", sources["build_buildmenu.lua"])(sources["BuildMenuClient.client.lua"])

local menu = StarterGui:FindFirstChild("BuildMenu")
print(("[install] done: BuildCatalog %d, BuildService %d, BuildMenu %s (client %d)"):format(#catalog.Source, #service.Source,
	tostring(menu ~= nil), menu and #menu.BuildMenuClient.Source or 0))

-- install.lua: ONE execute_luau (edit mode). Pulls every file from the loopback server
-- (pets-remake/serve.ps1 -Port 8769 -Root new-map-cucumber-game/hud-shop), compile-checks it, sets the
-- script sources and runs the two builders.
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8769/"
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
local StarterGui = game:GetService("StarterGui")
local SSS = game:GetService("ServerScriptService")
local menus = StarterGui:WaitForChild("CucumberMenus")

local sources = {}
for _, name in ipairs({"MenuController.lua", "MenuClient.client.lua", "ShopController.lua", "ShopProductsServer.server.lua", "HUDClient.client.lua", "build_shop.lua", "build_hud.lua"}) do
	local src = fetch(name)
	compiled(name, src)
	sources[name] = src
end

menus.MenuController.Source = sources["MenuController.lua"]
menus.MenuClient.Source = sources["MenuClient.client.lua"]
local shopController = menus:FindFirstChild("ShopController")
if not shopController then
	shopController = Instance.new("ModuleScript")
	shopController.Name = "ShopController"
	shopController.Parent = menus
end
shopController.Source = sources["ShopController.lua"]
local server = SSS:FindFirstChild("ShopProductsServer")
if not server then
	server = Instance.new("Script")
	server.Name = "ShopProductsServer"
	server.Parent = SSS
end
server.Source = sources["ShopProductsServer.server.lua"]

compiled("build_shop.lua", sources["build_shop.lua"])()
compiled("build_hud.lua", sources["build_hud.lua"])(sources["HUDClient.client.lua"])
print("[install] done: MenuController", #menus.MenuController.Source, "ShopController", #shopController.Source, "ShopProductsServer", #server.Source)

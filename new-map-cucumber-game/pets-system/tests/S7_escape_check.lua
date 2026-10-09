--[[
	S7_escape_check.lua  (S7 integration, 2026-09-22) - read-only for the DataModel.
	The playtest cannot press Escape: simulate_keyboard_input refuses it ("key is permanently bound to a
	CoreGUI core action"). This chunk runs the LIVE-pushed MenuController source (patched loopback :8794)
	against UNPARENTED clones of the live StarterGui.CucumberMenus / CucumberHUDDesign (which now hold the
	built PetsPanel and paw), with a fake UserInputService whose InputBegan the test fires, and checks the
	Escape rule for every panel: Escape closes Pets / Shop / Index, a processed Escape (a TextBox had
	focus) and other keys do not.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/S7_escape_check.lua"))()
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local realGame = game

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or ""))
	end
end

local handlers = {}
local fakeUIS = {
	InputBegan = {Connect = function(_, fn)
		table.insert(handlers, fn)
		return {Disconnect = function() local i = table.find(handlers, fn) if i then table.remove(handlers, i) end end}
	end},
}
local fakeGame = setmetatable({GetService = function(_, name)
	if name == "UserInputService" then return fakeUIS end
	return realGame:GetService(name)
end}, {__index = function(_, k) return realGame[k] end})
local function press(keyCode, processed)
	for _, fn in ipairs(handlers) do fn({KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard}, processed) end
end

local chunk = assert(loadstring(HttpService:GetAsync("http://127.0.0.1:8794/StarterGui.CucumberMenus.MenuController.lua")))
setfenv(chunk, setmetatable({game = fakeGame}, {__index = getfenv()}))
local MenuController = chunk()

local menus = StarterGui.CucumberMenus:Clone()
local hud = StarterGui.CucumberHUDDesign:Clone()
local api
local ok, err = pcall(function()
	check("live StarterGui has the built PetsPanel", menus:FindFirstChild("PetsPanel") ~= nil and hud.LeftMenu:FindFirstChild("Pets") ~= nil)
	api = MenuController.Start(menus, hud)
	check("InputBegan hooked once", #handlers == 1, #handlers)
	for _, name in ipairs({"Pets", "Shop", "Index"}) do
		api.Open(name)
		check(name .. " open", menus:GetAttribute("OpenPanel") == name)
		press(Enum.KeyCode.P, false)
		check(name .. " stays open on another key", menus:GetAttribute("OpenPanel") == name)
		press(Enum.KeyCode.Escape, true)
		check(name .. " stays open on a processed Escape", menus:GetAttribute("OpenPanel") == name)
		press(Enum.KeyCode.Escape, false)
		check(name .. " closes on Escape", menus:GetAttribute("OpenPanel") == "" and api.GetOpenPanel() == nil)
	end
	press(Enum.KeyCode.Escape, false)
	check("Escape with nothing open is a no-op", menus:GetAttribute("OpenPanel") == "")
end)
if api then api.Destroy() end
menus:Destroy()
hud:Destroy()
if not ok then fail += 1 table.insert(failures, "error: " .. tostring(err)) end
return ("S7 escape check: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")

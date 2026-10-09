--[[
	WP-MENU_patches.lua  (2026-09-22) - behaviour test of the patched MenuController and BaseHUDController.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_patches.lua"))()
	Both patched sources come from the patched loopback (:8794); they run against UNPARENTED clones of
	StarterGui.CucumberMenus / CucumberHUDDesign (clones' scripts never run) with the pets builder applied
	to the clones (module mode). BaseHUDController runs under setfenv with a fake Players.LocalPlayer (no
	character) and is driven through its BaseDev / BuildMode attributes. MenuClient is checked statically
	(it can only run as a LocalScript). Nothing enters the DataModel. 2026-09-22 (review): also a paw that
	is parented after BaseHUDController.Start (late replication) is picked up and takes the current mode.
	Returns "WP-MENU patches: PASS n / FAIL m: <first failures>".
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
		if #failures < 14 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function fetch(port, file) return HttpService:GetAsync(("http://127.0.0.1:%d/%s"):format(port, file)) end

local Builder = loadstring(loadstring(fetch(8795, "WP-MENU_builder_embed.lua"))())({Mode = "module"})
local MenuController = loadstring(fetch(8794, "StarterGui.CucumberMenus.MenuController.lua"))()

local function Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(handlers, fn)
		return {Disconnect = function() local i = table.find(handlers, fn) if i then table.remove(handlers, i) end end}
	end
	return signal
end
local fakePlayer = {UserId = -1, Character = nil, CharacterRemoving = Signal(), CharacterAdded = Signal()}
local fakeGame = {GetService = function(_, name)
	if name == "Players" then return {LocalPlayer = fakePlayer} end
	return realGame:GetService(name)
end}
local hudChunk = assert(loadstring(fetch(8794, "StarterGui.CucumberHUDDesign.BaseHUDController.lua")))
setfenv(hudChunk, setmetatable({game = fakeGame}, {__index = getfenv()}))
local BaseHUDController = hudChunk()

local menus = StarterGui.CucumberMenus:Clone()
local hud = StarterGui.CucumberHUDDesign:Clone()
local plainHud = StarterGui.CucumberHUDDesign:Clone()
local plainMenus = StarterGui.CucumberMenus:Clone()
local lateHud = StarterGui.CucumberHUDDesign:Clone() -- 2026-09-22 (review): the paw replicates after Start
-- 2026-09-22 (S7 integration): the live StarterGui now holds the built PetsPanel and paw, so the "before the
-- builder" fixtures strip them from their clones
do
	local panel = plainMenus:FindFirstChild("PetsPanel")
	if panel then panel:Destroy() end
	for _, clone in ipairs({plainHud, lateHud}) do
		local paw = clone.LeftMenu:FindFirstChild("Pets")
		if paw then paw:Destroy() end
	end
end
local apis = {}
local ok, err = pcall(function()
	Builder.BuildPanel(menus, menus.IndexPanel.Content)
	Builder.BuildOpener(hud)

	--..MenuController..--
	local api = MenuController.Start(menus, hud)
	table.insert(apis, api)
	task.wait(0.15)
	local pets = hud.LeftMenu.Pets
	check("paw wired (HoverScale on LeftMenu.Pets)", pets:FindFirstChild("HoverScale") ~= nil)
	check("Shop / Index still wired", hud.LeftMenu.Shop:FindFirstChild("HoverScale") ~= nil and hud.LeftMenu.Index:FindFirstChild("HoverScale") ~= nil)
	api.Open("Pets")
	check("Pets opens", menus:GetAttribute("OpenPanel") == "Pets" and menus.PetsPanel.Content.Visible == true and api.GetOpenPanel() == "Pets")
	hud:SetAttribute("BaseMode", true)
	task.wait(0.05)
	check("BaseMode keeps Pets open", menus:GetAttribute("OpenPanel") == "Pets")
	hud:SetAttribute("BaseMode", false)
	api.Open("Shop")
	check("Shop opens", menus:GetAttribute("OpenPanel") == "Shop")
	hud:SetAttribute("BaseMode", true)
	task.wait(0.05)
	check("BaseMode still closes Shop", menus:GetAttribute("OpenPanel") == "" and api.GetOpenPanel() == nil)
	hud:SetAttribute("BaseMode", false)
	api.Open("Index")
	hud:SetAttribute("BaseMode", true)
	task.wait(0.05)
	check("BaseMode still closes Index", menus:GetAttribute("OpenPanel") == "")
	hud:SetAttribute("BaseMode", false)
	api.Open("Pets")
	hud:SetAttribute("BuildMode", true)
	task.wait(0.05)
	check("BuildMode closes Pets", menus:GetAttribute("OpenPanel") == "")
	hud:SetAttribute("BuildMode", false)
	menus:SetAttribute("OpenRequest", "Pets:Reserve#1")
	task.wait(0.1)
	check("OpenRequest opens Pets", menus:GetAttribute("OpenPanel") == "Pets" and menus.PetsPanel:GetAttribute("RequestedTab") == "Reserve")
	api.Toggle("Pets")
	check("Toggle closes Pets", menus:GetAttribute("OpenPanel") == "")
	api.Toggle("Pets")
	api.Open("Index")
	task.wait(0.3)
	check("switching hides Pets", menus.PetsPanel.Content.Visible == false and menus.IndexPanel.Content.Visible == true)
	check("fit covers Pets", menus.PetsPanel.ResponsiveScale.Scale >= 0.25)
	api.Close()

	-- no PetsPanel / no paw: Start does not stall and Shop / Index work as before
	local started = os.clock()
	local plainApi = MenuController.Start(plainMenus, plainHud)
	table.insert(apis, plainApi)
	check("start without pets is immediate", os.clock() - started < 0.5, os.clock() - started)
	plainApi.Open("Pets")
	check("unregistered Pets ignored", plainMenus:GetAttribute("OpenPanel") ~= "Pets")
	plainApi.Open("Shop")
	check("plain Shop opens", plainMenus:GetAttribute("OpenPanel") == "Shop")
	plainApi.Close()

	-- panel present but paw missing: the optional opener waits in its own thread
	local noPawMenus = StarterGui.CucumberMenus:Clone()
	Builder.BuildPanel(noPawMenus, noPawMenus.IndexPanel.Content)
	started = os.clock()
	local noPawApi = MenuController.Start(noPawMenus, plainHud)
	table.insert(apis, noPawApi)
	check("missing paw does not stall Start", os.clock() - started < 0.5)
	noPawApi.Open("Pets")
	check("Pets opens without its paw", noPawMenus:GetAttribute("OpenPanel") == "Pets")
	noPawApi.Destroy() -- the waiting thread then returns without wiring
	noPawMenus:Destroy()

	--..BaseHUDController..--
	local controller = BaseHUDController.Start(hud)
	table.insert(apis, controller)
	task.wait(0.05)
	check("paw shown outside", pets.Visible == true and hud.LeftMenu.Shop.Visible == true and hud:GetAttribute("BaseMode") == false)
	local restSize = pets.Size
	hud:SetAttribute("BaseDev", "bench")
	task.wait(0.6)
	check("paw tucks on the bench", pets.Visible == false, pets.Visible)
	check("hover reset on tuck", pets.HoverScale.Scale == 1)
	hud:SetAttribute("BaseDev", "inside")
	task.wait(0.8)
	check("paw back inside the base", pets.Visible == true and pets.Size == restSize, tostring(pets.Size))
	check("base pair shown", hud.LeftMenu.Build.Visible == true and hud.LeftMenu.Shop.Visible == false)
	hud:SetAttribute("BuildMode", true)
	task.wait(0.6)
	check("paw tucks in build mode", pets.Visible == false)
	hud:SetAttribute("BuildMode", false)
	hud:SetAttribute("BaseDev", "outside")
	task.wait(0.8)
	check("paw back outside", pets.Visible == true and pets.Position == UDim2.new(1.07, 0, 0, 0), tostring(pets.Position))

	local plainController = BaseHUDController.Start(plainHud)
	table.insert(apis, plainController)
	task.wait(0.05)
	check("HUD without paw still works", plainHud.LeftMenu.Shop.Visible == true and plainHud:GetAttribute("BaseMode") == false)

	-- 2026-09-22 (review): a paw that arrives after Start is picked up late and takes the current mode at once
	lateHud:SetAttribute("BaseDev", "inside")
	lateHud:SetAttribute("BuildMode", true)
	started = os.clock()
	local lateController = BaseHUDController.Start(lateHud)
	table.insert(apis, lateController)
	check("late paw: Start does not wait for it", os.clock() - started < 0.5, os.clock() - started)
	task.wait(0.1)
	Builder.BuildOpener(lateHud)
	task.wait(0.2)
	local latePaw = lateHud.LeftMenu:FindFirstChild("Pets")
	check("late paw tucked at once in build mode", latePaw ~= nil and latePaw.Visible == false, latePaw and tostring(latePaw.Visible))
	check("late paw: the others kept their mode", lateHud.LeftMenu.Build.Visible == false and lateHud.LeftMenu.Shop.Visible == false)
	lateHud:SetAttribute("BuildMode", false)
	task.wait(0.8)
	check("late paw comes back when build mode ends", latePaw ~= nil and latePaw.Visible == true
		and latePaw.Size == UDim2.new(1, 0, 0.455, 0) and latePaw.Position == UDim2.new(1.07, 0, 0, 0), latePaw and tostring(latePaw.Position))
	check("late paw: base pair back", lateHud.LeftMenu.Build.Visible == true)

	--..MenuClient (static)..--
	local client = fetch(8794, "StarterGui.CucumberMenus.MenuClient.client.lua")
	check("MenuClient compiles", loadstring(client) ~= nil)
	check("MenuClient guarded PetController start", client:find("pcall(function() return require(script.Parent.PetController).Start(script.Parent,menus) end)", 1, true) ~= nil)
	check("MenuClient destroys pets first", client:find("if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy()", 1, true) ~= nil)
	local startLine = client:find("PetController", 1, true)
	local shopLine = client:find("ShopController", 1, true)
	check("PetController starts last", startLine and shopLine and startLine > shopLine)
end)
if not ok then
	fail += 1
	table.insert(failures, 1, "ERROR " .. tostring(err))
end
for _, api in ipairs(apis) do pcall(api.Destroy) end
menus:Destroy()
hud:Destroy()
plainHud:Destroy()
plainMenus:Destroy()
lateHud:Destroy()
return ("WP-MENU patches: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")

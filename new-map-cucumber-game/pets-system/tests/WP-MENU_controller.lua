--[[
	WP-MENU_controller.lua  (2026-09-22) - PetController.Start flow test with injected fakes.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_controller.lua"))()
	PetController and PetView are loaded from the src loopback and run under setfenv environments whose
	`game:GetService` hands out fakes for ContextActionService (no real binding), GuiService,
	UserInputService and ReplicatedStorage.Remotes (fake PetState / PetRequest), and whose `require`
	swaps Notify and ButtonFX for silent fakes (no sounds, no toasts). The panel is built by the builder
	(module mode) into an UNPARENTED ScreenGui, so nothing enters the DataModel.
	Covers: GetState on start, P toggles (and is ignored while CucumberMenus is disabled), Full -> cards +
	Studio mirror attributes, PetsDev select / equip, one pending request at a time, the reply clears it
	and shows the friendly error, gap -> GetState again (<= 1/s), Totals message -> footer only, combat
	lock -> banner + roster actions refused locally, new Generation -> loading, Notice -> Notify.Info once,
	Destroy unbinds and disconnects. 2026-09-22 (review): a refused (not-ready) Full is not state (loading /
	MigrationFailed line, buttons disabled, nothing sent), and the unsolicited hatch InventoryFull Delta is
	one Notify.Error toast while the panel is closed. 2026-09-22 (checker): after a Totals fast path, a
	switch to the compact layout and back keeps the newer totals in the footer (the switch re-draws the held
	view model without its older footer). Returns "WP-MENU controller: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local realGame = game
local realRequire = require
local RealReplicatedStorage = game:GetService("ReplicatedStorage")

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		if #failures < 14 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

--..Fakes..--
local function Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(handlers, fn)
		return {Disconnect = function()
			local i = table.find(handlers, fn)
			if i then table.remove(handlers, i) end
		end}
	end
	function signal:Fire(...) for _, fn in ipairs(table.clone(handlers)) do fn(...) end end
	function signal:Count() return #handlers end
	return signal
end
local fired = {}
local stateRemote = {OnClientEvent = Signal()}
local requestRemote = {FireServer = function(_, request) table.insert(fired, request) end}
local fakeRemotes = {
	WaitForChild = function(_, name) if name == "PetState" then return stateRemote elseif name == "PetRequest" then return requestRemote end return nil end,
	FindFirstChild = function(self, name) return self:WaitForChild(name) end,
}
local fakeReplicatedStorage = {
	FindFirstChild = function(_, name) if name == "Remotes" then return fakeRemotes end return RealReplicatedStorage:FindFirstChild(name) end,
	WaitForChild = function(_, name, timeout) if name == "Remotes" then return fakeRemotes end return RealReplicatedStorage:WaitForChild(name, timeout) end,
}
local bound = {}
local fakeActions = {
	BindAction = function(_, name, fn, _, ...) bound[name] = {Fn = fn, Keys = {...}} end,
	UnbindAction = function(_, name) bound[name] = nil end,
}
local fakeGuiService = {SelectedObject = nil}
local fakeInput = {GamepadEnabled = false, GetFocusedTextBox = function() return nil end}
local fakeGame = {GetService = function(_, name)
	if name == "ContextActionService" then return fakeActions end
	if name == "GuiService" then return fakeGuiService end
	if name == "UserInputService" then return fakeInput end
	if name == "ReplicatedStorage" then return fakeReplicatedStorage end
	return realGame:GetService(name)
end}
local notices = {}
local errors = {}
local fakeNotify = {Info = function(text) table.insert(notices, text) end, Error = function(text) table.insert(errors, text) end}
local fakeButtonFX = {
	PRESS_SOUND = {"Button Pop", 0.3}, FAIL_SOUND = {"Error", 1.2},
	Sound = function() end, Flash = function() end,
	Animate = function(duration, style, direction, fn) fn(1) return true end,
}

local function Load(port, file, extraEnv)
	local chunk = assert(loadstring(HttpService:GetAsync(("http://127.0.0.1:%d/%s"):format(port, file))))
	local env = setmetatable(extraEnv, {__index = getfenv()})
	setfenv(chunk, env)
	return chunk()
end
local function fakeRequire(module)
	if type(module) == "table" and module.Fake then return module.Fake end
	if typeof(module) == "Instance" then
		if module.Name == "Notify" then return fakeNotify end
		if module.Name == "ButtonFX" then return fakeButtonFX end
	end
	return realRequire(module)
end
local RealView = Load(8793, "StarterGui.CucumberMenus.PetView.lua", {game = fakeGame, require = fakeRequire})
-- 2026-09-22 (review #7): count full renders / footer-only writes
local renders, footers = 0, 0
local View = {Start = function(gui)
	local v = RealView.Start(gui)
	local render, setFooter = v.Render, v.SetFooter
	v.Render = function(vm) renders += 1 return render(vm) end
	v.SetFooter = function(footer) footers += 1 return setFooter(footer) end
	return v
end}
local fakeScript = {Parent = {FindFirstChild = function(_, name) if name == "PetView" then return {Fake = View} end return nil end}}
local PetController = Load(8793, "StarterGui.CucumberMenus.PetController.lua", {game = fakeGame, require = fakeRequire, script = fakeScript})
local builderSource = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-MENU_builder_embed.lua"))()
local Builder = loadstring(builderSource)({Mode = "module"})

local gui = Instance.new("ScreenGui") -- never parented
gui.Name = "CucumberMenus"
local controller = nil
local ok, err = pcall(function()
	local panel = Builder.BuildPanel(gui, StarterGui.CucumberMenus.IndexPanel.Content)
	local content = panel.Content
	local menus = {
		Toggle = function(name) gui:SetAttribute("OpenPanel", gui:GetAttribute("OpenPanel") == name and "" or name) end,
		Open = function(name) gui:SetAttribute("OpenPanel", name) end,
		Close = function() gui:SetAttribute("OpenPanel", "") end,
	}
	gui:SetAttribute("OpenPanel", "")
	controller = PetController.Start(gui, menus)
	check("start returns api", type(controller) == "table" and type(controller.Destroy) == "function")
	task.wait(0.2)
	check("GetState on start", fired[1] and fired[1].Action == "GetState" and type(fired[1].RequestId) == "string")
	check("state listener connected", stateRemote.OnClientEvent:Count() == 1)
	local binding = bound.PetsPanel
	check("P / ButtonL3 bound", binding and table.find(binding.Keys, Enum.KeyCode.P) and table.find(binding.Keys, Enum.KeyCode.ButtonL3))

	gui.Enabled = false
	local result = binding.Fn("PetsPanel", Enum.UserInputState.Begin)
	check("key ignored while menus disabled", result == Enum.ContextActionResult.Pass and gui:GetAttribute("OpenPanel") == "")
	gui.Enabled = true
	result = binding.Fn("PetsPanel", Enum.UserInputState.Begin)
	check("P opens", result == Enum.ContextActionResult.Sink and gui:GetAttribute("OpenPanel") == "Pets")
	task.wait(0.1)
	check("loading status", content.Status.Visible and content.Status.Text == "Loading pets...", content.Status.Text)

	-- 2026-09-22 (review): PetService answers GetState with an empty Full + Result.Ok == false until the pets load
	local function refusal(revision, code)
		return {Kind = "Full", Revision = revision, Generation = 0, RequestId = fired[1].RequestId, Slots = 6, EquippedIds = {}, Pets = {},
			Totals = {Pet = 0, Cucumber = 0, CucumberBase = 0, Total = 0}, CombatLocked = false, ServerTime = workspace:GetServerTimeNow(),
			Result = {Ok = false, Action = "GetState", Error = code}}
	end
	local function bestDisabled()
		return content.Toolbar.BestIncome.Gradient.Color.Keypoints[1].Value == Color3.fromRGB(149, 172, 180)
	end
	stateRemote.OnClientEvent:Fire(refusal(1, "NotLoaded"))
	task.wait(0.1)
	check("NotLoaded Full: still no state", panel:GetAttribute("PetsRevision") == -1 and panel:GetAttribute("PetsOwned") == 0)
	check("NotLoaded Full: still loading", content.Status.Visible and content.Status.Text == PetController.Core.LOADING_TEXT, content.Status.Text)
	check("NotLoaded Full: no empty-roster text", content.PetGrid.Empty.Visible == false)
	check("NotLoaded Full: Best buttons disabled", bestDisabled())
	stateRemote.OnClientEvent:Fire(refusal(2, "MigrationFailed"))
	task.wait(0.1)
	check("MigrationFailed Full: shows the refusal", content.Status.Visible and content.Status.Text == PetController.Core.ERROR_TEXT.MigrationFailed, content.Status.Text)
	check("MigrationFailed Full: no state, buttons disabled", panel:GetAttribute("PetsRevision") == -1 and bestDisabled())
	local sentBefore = #fired
	panel:SetAttribute("PetsDev", "best:Income")
	task.wait(0.1)
	check("MigrationFailed Full: roster action not sent", #fired == sentBefore)

	local function pet(id, income, extra)
		local v = {Id = id, Pet = "Cat", DisplayName = "Pet " .. id, Rarity = "Common", Material = "", Mutations = {}, AcquiredAt = 0,
			Equipped = false, Status = "Reserve", AbilityRemaining = 60,
			Stats = {Income = income, ShotDamage = 3, ShotInterval = 2.5, DPS = 1.2, Range = 26, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90}}
		for k, value in pairs(extra or {}) do v[k] = value end
		return v
	end
	stateRemote.OnClientEvent:Fire({Kind = "Full", Revision = 1, Generation = 1, Slots = 6, ServerTime = workspace:GetServerTimeNow(),
		RequestId = fired[1].RequestId, EquippedIds = {"a"}, Notice = "You can now choose six active pets.",
		Pets = {pet("a", 1, {Equipped = true, Status = "Active"}), pet("b", 5), pet("c", 3)},
		Totals = {Pet = 1, Cucumber = 100, CucumberBase = 100, Total = 101}, CombatLocked = false})
	task.wait(0.1)
	check("full rendered", panel:GetAttribute("PetsRevision") == 1 and panel:GetAttribute("PetsOwned") == 3 and panel:GetAttribute("PetsEquipped") == 1)
	check("status cleared", content.Status.Visible == false)
	check("notice once", #notices == 1 and notices[1] == "You can now choose six active pets.")
	check("default selection = top card", panel:GetAttribute("PetsSelected") == "b", panel:GetAttribute("PetsSelected"))
	check("cards present", content.PetGrid:FindFirstChild("Pet_a") and content.PetGrid:FindFirstChild("Pet_b") and content.PetGrid:FindFirstChild("Pet_c"))

	panel:SetAttribute("PetsDev", "select:2")
	task.wait(0.1)
	check("dev select", panel:GetAttribute("PetsSelected") == "c" and panel:GetAttribute("PetsDev") == nil, panel:GetAttribute("PetsSelected"))
	local before = #fired
	panel:SetAttribute("PetsDev", "equip")
	task.wait(0.1)
	local sent = fired[#fired]
	check("dev equip sends Equip", #fired == before + 1 and sent.Action == "Equip" and sent.PetId == "c", sent and sent.Action)
	check("pending mirrored", panel:GetAttribute("PetsPending") == true)
	check("buttons disabled while pending", content.Details.EquipButton.Gradient.Color.Keypoints[1].Value == Color3.fromRGB(149, 172, 180))
	panel:SetAttribute("PetsDev", "best:Income")
	task.wait(0.1)
	check("one pending request at a time", #fired == before + 1)

	stateRemote.OnClientEvent:Fire({Kind = "Delta", Revision = 2, BaseRevision = 1, Generation = 1, RequestId = sent.RequestId,
		Result = {Ok = false, Error = "SlotsFull", Action = "Equip"}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("reply clears pending", panel:GetAttribute("PetsPending") == false and panel:GetAttribute("PetsRevision") == 2)
	check("friendly error shown", content.Status.Visible and content.Status.Text == PetController.Core.ERROR_TEXT.SlotsFull, content.Status.Text)

	panel:SetAttribute("PetsDev", "best:Combat")
	task.wait(0.1)
	local best = fired[#fired]
	check("EquipBest sent", best.Action == "EquipBest" and best.SortMode == "Combat")
	stateRemote.OnClientEvent:Fire({Kind = "Delta", Revision = 3, BaseRevision = 2, Generation = 1, RequestId = best.RequestId,
		Result = {Ok = true, Action = "EquipBest"}, EquippedIds = {"b", "c", "a"},
		Upserts = {pet("b", 5, {Equipped = true, Status = "Active"}), pet("c", 3, {Equipped = true, Status = "Active"})}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("roster delta applied", panel:GetAttribute("PetsEquipped") == 3 and content.Header.Subtitle.Text == "3 / 6 ACTIVE", content.Header.Subtitle.Text)
	check("slot order follows roster", content.SlotRow.Slot1.PetName.Text == "Pet b" and content.SlotRow.Slot3.PetName.Text == "Pet a")

	local rendersBefore, footersBefore = renders, footers
	stateRemote.OnClientEvent:Fire({Kind = "Totals", Totals = {Pet = 9, Cucumber = 100, CucumberBase = 100, Total = 109}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("totals message -> footer", content.Footer.PetCash.Text:find("$9/s", 1, true) ~= nil and panel:GetAttribute("PetsRevision") == 3, content.Footer.PetCash.Text)
	check("totals message: footer only, no full render", renders == rendersBefore and footers == footersBefore + 1, ("renders +%d, footers +%d"):format(renders - rendersBefore, footers - footersBefore))
	-- closed panel: a Totals message does nothing now; the next open renders the new totals
	gui:SetAttribute("OpenPanel", "")
	task.wait(0.05)
	rendersBefore, footersBefore = renders, footers
	stateRemote.OnClientEvent:Fire({Kind = "Totals", Totals = {Pet = 7, Cucumber = 100, CucumberBase = 100, Total = 107}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("totals while closed: no work", renders == rendersBefore and footers == footersBefore, ("renders +%d, footers +%d"):format(renders - rendersBefore, footers - footersBefore))
	gui:SetAttribute("OpenPanel", "Pets")
	task.wait(0.1)
	check("totals while closed: shown on open", content.Footer.PetCash.Text:find("$7/s", 1, true) ~= nil, content.Footer.PetCash.Text)

	-- 2026-09-22 (checker): a Totals fast path, then a layout switch: the switch re-draws the held view model
	-- (whose footer still says $107/s) but must keep the newer totals on screen
	stateRemote.OnClientEvent:Fire({Kind = "Totals", Totals = {Pet = 5, Cucumber = 500, CucumberBase = 500, Total = 505}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("totals fast path before the switch", content.Footer.TotalCash.Text:find("$505/s", 1, true) ~= nil, content.Footer.TotalCash.Text)

	-- 2026-09-22 (review #2): phone scale -> compact; the dev select opens the Details page like a tap, back closes it
	panel.ResponsiveScale.Scale = 0.37
	task.wait(0.05)
	check("phone scale -> compact", panel:GetAttribute("Compact") == true and content.SlotRow.Visible == false and content.Details.Visible == false)
	check("compact switch keeps the newer totals", content.Footer.TotalCash.Text:find("$505/s", 1, true) ~= nil
		and content.Footer.PetCash.Text:find("$5/s", 1, true) ~= nil, content.Footer.TotalCash.Text)
	panel:SetAttribute("PetsDev", "select:1")
	task.wait(0.1)
	check("compact dev select opens the page", content.Details.Visible == true and content.PetGrid.Visible == false and content.Details.PetName.Text ~= "")
	panel:SetAttribute("PetsDev", "back")
	task.wait(0.05)
	check("compact dev back closes the page", content.Details.Visible == false and content.PetGrid.Visible == true)
	panel.ResponsiveScale.Scale = 0.86
	task.wait(0.05)
	check("desktop scale -> wide", panel:GetAttribute("Compact") == false and content.SlotRow.Visible and content.Details.Visible)
	-- (the dev select above re-rendered from the state, which holds the same newer totals)
	check("wide switch keeps the newer totals", content.Footer.TotalCash.Text:find("$505/s", 1, true) ~= nil, content.Footer.TotalCash.Text)
	stateRemote.OnClientEvent:Fire({Kind = "Totals", Totals = {Pet = 6, Cucumber = 600, CucumberBase = 600, Total = 606}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	panel.ResponsiveScale.Scale = 0.37
	task.wait(0.05)
	panel.ResponsiveScale.Scale = 0.86
	task.wait(0.05)
	check("fast path, then compact + wide switches: newest totals kept", content.Footer.TotalCash.Text:find("$606/s", 1, true) ~= nil, content.Footer.TotalCash.Text)

	-- 2026-09-22 (review): the unsolicited hatch refusal is a toast even while the panel is closed
	gui:SetAttribute("OpenPanel", "")
	task.wait(0.05)
	stateRemote.OnClientEvent:Fire({Kind = "Delta", Revision = 4, BaseRevision = 3, Generation = 1,
		Result = {Ok = false, Action = "Hatch", Error = "InventoryFull"}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	local toast = errors[1]
	check("InventoryFull -> one Notify.Error while closed", #errors == 1 and type(toast) == "string"
		and (toast == PetController.Core.DEFAULT_TEXT.InventoryFull or toast:lower():find("full", 1, true) ~= nil), tostring(#errors) .. " " .. tostring(toast))
	check("InventoryFull delta advances the revision only", panel:GetAttribute("PetsRevision") == 4 and panel:GetAttribute("PetsOwned") == 3)
	gui:SetAttribute("OpenPanel", "Pets")
	task.wait(0.1)
	check("InventoryFull is not a panel error", content.Status.Text ~= toast, content.Status.Text)

	local asks = 0
	for _, request in ipairs(fired) do if request.Action == "GetState" then asks += 1 end end
	stateRemote.OnClientEvent:Fire({Kind = "Delta", Revision = 9, BaseRevision = 8, Generation = 1, Upserts = {pet("z", 1)}, ServerTime = workspace:GetServerTimeNow()})
	task.wait(1.3)
	local asksAfter = 0
	for _, request in ipairs(fired) do if request.Action == "GetState" then asksAfter += 1 end end
	check("gap asks for a Full", asksAfter == asks + 1, asksAfter - asks)
	check("gap keeps the held state", panel:GetAttribute("PetsRevision") == 4 and panel:GetAttribute("PetsOwned") == 3)

	stateRemote.OnClientEvent:Fire({Kind = "Full", Revision = 10, Generation = 1, Slots = 6, ServerTime = workspace:GetServerTimeNow(),
		EquippedIds = {"a"}, Pets = {pet("a", 1, {Equipped = true, Status = "Active"}), pet("b", 5)}, Notice = "again",
		Totals = {Pet = 1, Cucumber = 1, CucumberBase = 1, Total = 2}, CombatLocked = true})
	task.wait(0.1)
	check("full after gap", panel:GetAttribute("PetsRevision") == 10 and panel:GetAttribute("PetsOwned") == 2)
	check("notice not repeated", #notices == 1)
	check("lock banner", content.LockBanner.Visible == true)
	local count = #fired
	panel:SetAttribute("PetsDev", "best:Income")
	task.wait(0.1)
	check("locked: roster action refused locally", #fired == count and content.Status.Visible and content.Status.Text == PetController.Core.DEFAULT_TEXT.LockBanner, content.Status.Text)

	stateRemote.OnClientEvent:Fire({Kind = "Delta", Revision = 11, BaseRevision = 10, Generation = 2, CombatLocked = false, ServerTime = workspace:GetServerTimeNow()})
	task.wait(0.1)
	check("new generation drops state", panel:GetAttribute("PetsRevision") == -1 and panel:GetAttribute("PetsOwned") == 0)

	panel:SetAttribute("PetsDev", "close")
	task.wait(0.05)
	check("dev close", gui:GetAttribute("OpenPanel") == "")
	controller.Destroy()
	controller = nil
	check("destroy unbinds", bound.PetsPanel == nil)
	check("destroy disconnects", stateRemote.OnClientEvent:Count() == 0)
end)
if not ok then
	fail += 1
	table.insert(failures, 1, "ERROR " .. tostring(err))
end
if controller then pcall(controller.Destroy) end
gui:Destroy()
return ("WP-MENU controller: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")

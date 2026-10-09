--[[
	ManageController  (ModuleScript, StarterGui.CucumberMenus)  2026-09-23
	Wires the designed MANAGE panel (StarterGui.CucumberMenus.ManagePanel - "Everything in your base,
	in one place") to ServerScriptService.ManageService through Remotes.ManageRequest. MenuController
	opens / closes it (the left menu's Manage button inside the base, Esc, the close X, the dimmer,
	leaving the base) exactly like Shop / Index / Pets; this module only fills it and sells.

	  Tabs      PetsTab / CucumbersTab / ZombiesTab (attribute Page) -> Pages.<Page>; the selected tab
	            gets the Index panel's bright cyan gradient + its InnerRim, the others the grey one.
	  Pets      "Pets  N / cap", the ACTIVE roster as PetRow clones (Templates.PetRow): viewport preview
	            (PetsCatalog model + CucumberMutations.ApplyLook), display name, "<Rarity> - traits - $X/s",
	            SELL $value (two taps: the first turns it into "SURE?" for CONFIRM_SECONDS).
	  Cucumbers "Cucumbers  N / cap", every placed cucumber as CucumberRow clones (CucumberIndexPreviews
	            model, zone line, SELL $value), best value first.
	  Zombies   threat level, days survived at that level, the OFFLINE EARNINGS card in its Locked /
	            Unlocked state with the "d / N DAY" progress bar.
	  Refresh   on open, every POLL_SECONDS while open, after every sale, on Remotes.ManageState
	            {Kind = "Refresh"} nudges from the server (raid results, offline pay) and when the plot's
	            Placed / Pets folders change (debounced). GetState replies carry OfflineToast once after a
	            paid join -> Notify.Success.
	  Studio hook: ManagePanel attribute ManageDev = "open" | "close" | "tab:<Page>" | "refresh" |
	            "sell:<n>" (sells row n of the open tab, no confirm) - edge-triggered, cleared after it runs.
	The designer's preview rows (attribute PreviewOnly) are removed at start; a ClickShield (like the
	Pets panel's) keeps clicks on the body from reaching the dimmer.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ManageConfig = require(Modules:WaitForChild("ManageConfig"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local Notify = require(Modules:WaitForChild("Notify"))
local okCatalog, PetsCatalog = pcall(function() return require(Modules:WaitForChild("PetsCatalog", 5)) end)
if not okCatalog then PetsCatalog = nil end
local okMut, CucumberMutations = pcall(function() return require(Modules:WaitForChild("CucumberMutations", 5)) end)
if not okMut then CucumberMutations = nil end
local okSound, SoundController = pcall(function() return require(Modules:WaitForChild("SoundController", 5)) end)
if not okSound then SoundController = nil end

local player = Players.LocalPlayer
local C = Color3.fromRGB

local POLL_SECONDS = 4
local CONFIRM_SECONDS = 3
local PLOT_DEBOUNCE = 0.4
local REMOTE_WAIT = 60
local PREVIEW_FOV = 32
local PREVIEW_DIRECTION = Vector3.new(0.363, 0.2, 0.909).Unit -- the designer's preview camera
local PREVIEW_YAW = math.rad(-18)
local TAB_ON = {Top = C(15, 224, 255), Bottom = C(0, 170, 240), Rim = C(128, 245, 255)} -- IndexView's active biome tab
local TAB_OFF = {Top = C(146, 177, 207), Bottom = C(74, 113, 148), Rim = C(184, 213, 238)}
local PAGES = {"Pets", "Cucumbers", "Zombies"}
local CUCUMBER_FALLBACK = {Cucumber = "Spawn Cucumber", ["Giant Cucumber"] = "Spawn Cucumber", ["Sliced Cucumber"] = "Spawn Sliced Cucumber", ["Cucumber Tree"] = "Cucumber Tree"}

local Controller = {}
Controller.Core = {}
local Core = Controller.Core

--..Pure helpers (tests)..--
function Core.Money(n) return ManageConfig.FormatMoney(n) end

function Core.Rate(n) return "$" .. NumberAbbrev.Abbrev(tonumber(n) or 0) .. "/s" end

local function Escape(s)
	return (tostring(s):gsub("[<>&]", {["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;"}))
end

local function Hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

--.. "<Rarity> - Golden NEON - $3.75/s" (rich text: the rarity in its glow colour)
function Core.PetDetail(item, glow)
	local parts = {}
	local rarity = tostring(item.Rarity or "Common")
	local color = glow and glow[rarity]
	table.insert(parts, color and string.format('<font color="%s">%s</font>', Hex(color), Escape(rarity)) or Escape(rarity))
	local traits = {}
	if type(item.Material) == "string" and item.Material ~= "" then table.insert(traits, item.Material) end
	for _, word in ipairs(type(item.Mutations) == "table" and item.Mutations or {}) do table.insert(traits, tostring(word)) end
	if #traits > 0 then table.insert(parts, Escape(table.concat(traits, " "))) end
	table.insert(parts, Core.Rate(item.Income))
	return table.concat(parts, "  -  ")
end

--.. "Desert - Golden HUGE - $2.1/s"
function Core.CucumberDetail(item)
	local parts = {Escape(item.Zone or "Spawn")}
	local traits = {}
	local material = item.Material
	if (material == nil or material == "") and item.Golden then material = "Golden" end
	if type(material) == "string" and material ~= "" then table.insert(traits, material) end
	if type(item.Mutations) == "string" and item.Mutations ~= "" then table.insert(traits, (item.Mutations:gsub(",", " "))) end
	if type(item.SizeTier) == "string" and item.SizeTier ~= "" then table.insert(traits, item.SizeTier) end
	if #traits > 0 then table.insert(parts, Escape(table.concat(traits, " "))) end
	table.insert(parts, Core.Rate(item.Rate))
	return table.concat(parts, "  -  ")
end

function Core.CapacityText(kind, count, capacity, plotLevel)
	if count > capacity then
		return string.format("Your base is over %s capacity: they stay, new ones wait for room.", kind)
	elseif (tonumber(plotLevel) or 0) >= ManageConfig.PLOT_MAX_LEVEL then
		return string.format("Your base is fully upgraded: %d %s max.", capacity, kind)
	end
	return string.format("Base upgrades increase your %s capacity.", kind)
end

function Core.ZombiesTexts(z)
	local level = tonumber(z and z.Level) or 1
	local days = tonumber(z and z.Days) or 0
	local required = math.max(1, tonumber(z and z.RequiredDays) or 1)
	local unlocked = z ~= nil and z.Unlocked == true
	local rate = tonumber(z and z.OfflineRate) or 0
	local mult = tonumber(z and z.Multiplier) or 0.5
	local maxSeconds = tonumber(z and z.MaxSeconds) or 8 * 3600
	return {
		Level = tostring(level), Days = tostring(days), Context = string.format("At Threat Level %d", level),
		Unlocked = unlocked,
		Requirement = unlocked and string.format("Offline earnings unlocked at Threat Level %d.", level)
			or string.format("Survive %d day%s at Threat Level %d to unlock.", required, required == 1 and "" or "s", level),
		Progress = string.format("%d / %d DAY%s", math.min(days, required), required, required == 1 and "" or "S"),
		Fill = math.clamp(days / required, 0, 1),
		Description = unlocked and string.format("Earning %s while away (%d%% of your cucumber income, up to %s).", Core.Rate(rate * mult), math.floor(mult * 100 + 0.5), ManageConfig.FormatDuration(maxSeconds))
			or "Survive at this threat level to earn while you are away.",
	}
end

--..Previews..--
local function ClearPreview(viewport)
	for _, child in ipairs(viewport:GetChildren()) do
		if child.Name == "PreviewModel" or child.Name == "PreviewCamera" or child.Name == "PreviewWorld" then child:Destroy() end
	end
	viewport.CurrentCamera = nil
end

local function ShowModel(viewport, source, material, mutations)
	ClearPreview(viewport)
	if not (source and source:IsA("Model")) then return end
	local model = source:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then d:Destroy() end
	end
	model:SetAttribute("PrismaticLoop", true) -- ApplyLook must not start a colour loop on a preview
	if CucumberMutations and ((material and material ~= "") or (mutations and mutations ~= "")) then
		pcall(CucumberMutations.ApplyLook, model, material ~= "" and material or nil, mutations)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then d:Destroy() end
	end
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(CFrame.Angles(0, PREVIEW_YAW, 0))
	model.Name = "PreviewModel"
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = PREVIEW_FOV
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	camera.CFrame = CFrame.lookAt(PREVIEW_DIRECTION * (radius * 0.9 / math.tan(math.rad(PREVIEW_FOV * 0.5))), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
end

local function PetPreview(viewport, item)
	local source = PetsCatalog and type(item.Pet) == "string" and PetsCatalog.ModelOf(item.Pet) or nil
	ShowModel(viewport, source, item.Material, table.concat(type(item.Mutations) == "table" and item.Mutations or {}, ","))
end

local function CucumberPreview(viewport, item)
	local previews = ReplicatedStorage:FindFirstChild("CucumberIndexPreviews")
	local zone, typeName = tostring(item.Zone or "Spawn"), tostring(item.TypeName or "")
	local source = previews and (previews:FindFirstChild(zone .. " " .. typeName) or previews:FindFirstChild(typeName) or previews:FindFirstChild(CUCUMBER_FALLBACK[typeName] or ""))
	local material = item.Material
	if (material == nil or material == "") and item.Golden then material = "Golden" end
	ShowModel(viewport, source, material, item.Mutations)
end

--..Start..--
function Controller.Start(gui, menus)
	local api = {}
	local connections = {}
	local destroyed = false
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end

	local panel = gui:FindFirstChild("ManagePanel")
	local content = panel and panel:FindFirstChild("Content")
	local templates = panel and panel:FindFirstChild("Templates")
	if not (content and templates and content:FindFirstChild("Pages") and content:FindFirstChild("Tabs")) then
		warn("[ManageController] ManagePanel is missing or incomplete - the Manage panel is unavailable")
		function api.Destroy() end
		return api
	end
	local pages, tabs = content.Pages, content.Tabs
	local rowTemplates = {Pets = templates:FindFirstChild("PetRow"), Cucumbers = templates:FindFirstChild("CucumberRow")}

	--.. the designer's preview rows go; a ClickShield keeps body clicks off the dimmer
	for _, name in ipairs({"Pets", "Cucumbers"}) do
		local list = pages:FindFirstChild(name) and pages[name]:FindFirstChild("ActiveList")
		if list then
			for _, row in ipairs(list:GetChildren()) do
				if row:IsA("GuiObject") and row:GetAttribute("PreviewOnly") then row:Destroy() end
			end
		end
	end
	if not content:FindFirstChild("ClickShield") and content:FindFirstChild("Body") then
		local body = content.Body
		local shield = Instance.new("TextButton")
		shield.Name = "ClickShield"
		shield.Text = ""
		shield.BackgroundTransparency = 1
		shield.AutoButtonColor = false
		shield.Selectable = false
		shield.Position = body.Position
		shield.Size = body.Size
		shield.AnchorPoint = body.AnchorPoint
		shield.ZIndex = 1
		shield.Parent = content
	end

	--.. hover / press pops on their own UIScale (never MenuController's HoverScale)
	local tweens = {}
	local function scaleTo(target, scale, seconds)
		local s = target:FindFirstChild("ManageScale")
		if not s then
			s = Instance.new("UIScale")
			s.Name = "ManageScale"
			s.Parent = target
		end
		if tweens[s] then tweens[s]:Cancel() end
		local t = TweenService:Create(s, TweenInfo.new(seconds or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = scale})
		tweens[s] = t
		t:Play()
	end
	local function isPointer(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	local function hover(button, target)
		target = target or button
		connect(button.MouseEnter, function() scaleTo(target, 1.035) end)
		connect(button.MouseLeave, function() scaleTo(target, 1) end)
		connect(button.InputBegan, function(input) if isPointer(input) then scaleTo(target, 0.97, 0.08) end end)
		connect(button.InputEnded, function(input) if isPointer(input) then scaleTo(target, 1, 0.1) end end)
	end

	--..State..--
	local state = nil
	local currentPage = panel:GetAttribute("DefaultTab")
	if not table.find(PAGES, currentPage) then currentPage = "Pets" end
	local rows = {Pets = {}, Cucumbers = {}} -- [id] = {Frame, Item, Conns}
	local confirm = {} -- [id] = os.clock() of the first tap
	local selling = {} -- [id] = true while the request is out
	local remote, stateRemote = nil, nil
	local requestSeq = 0
	local lastRequest = 0
	local refreshDue = false
	local glow = PetsCatalog and PetsCatalog.RARITY_GLOW or nil

	local function isOpen()
		return gui:GetAttribute("OpenPanel") == "Manage"
	end

	--..Tabs..--
	local function paintTab(tab, on)
		local look = on and TAB_ON or TAB_OFF
		local gradient = tab:FindFirstChild("Gradient")
		if gradient then gradient.Color = ColorSequence.new(look.Top, look.Bottom) end
		tab.BackgroundColor3 = Color3.new(1, 1, 1)
		local rim = tab:FindFirstChild("InnerRim")
		if rim then
			rim.Visible = on
			local border = rim:FindFirstChild("Border")
			if border then border.Color = look.Rim end
		end
		tab:SetAttribute("Selected", on)
	end
	local function selectPage(name)
		if not table.find(PAGES, name) then return end
		currentPage = name
		for _, page in ipairs(pages:GetChildren()) do
			if page:IsA("GuiObject") then page.Visible = page.Name == name end
		end
		for _, tab in ipairs(tabs:GetChildren()) do
			if tab:IsA("GuiButton") then paintTab(tab, tab:GetAttribute("Page") == name) end
		end
	end
	for _, tab in ipairs(tabs:GetChildren()) do
		if tab:IsA("GuiButton") and tab:GetAttribute("Page") then
			connect(tab.Activated, function() selectPage(tab:GetAttribute("Page")) end)
			hover(tab)
		end
	end

	--..Rows..--
	local function setSellLook(row, item, id)
		local button = row:FindFirstChild("SellButton")
		if not button then return end
		local action, value = button:FindFirstChild("Action"), button:FindFirstChild("SellValue")
		if value then value.Text = Core.Money(item.SellValue) end
		local busy = selling[id] == true
		if action then
			if busy then action.Text = "..."
			elseif item.Busy then action.Text = "HELD"
			elseif confirm[id] and os.clock() - confirm[id] < CONFIRM_SECONDS then action.Text = "SURE?"
			else action.Text = "SELL" end
		end
		button.Active = not busy and not item.Busy
		button.AutoButtonColor = false
	end

	local sell -- forward
	local function newRow(kind, id, order)
		local template = rowTemplates[kind]
		local row = template:Clone()
		row.Name = kind .. "Row_" .. tostring(order)
		row:SetAttribute("PreviewOnly", nil)
		row:SetAttribute("PreviewCollected", nil)
		row:SetAttribute("CucumberName", nil)
		row:SetAttribute("ItemId", id)
		row.Visible = true
		local entry = {Frame = row, Id = id, Conns = {}}
		local button = row:FindFirstChild("SellButton")
		if button then
			table.insert(entry.Conns, button.Activated:Connect(function() sell(kind, id) end))
			table.insert(entry.Conns, button.MouseEnter:Connect(function() scaleTo(button, 1.035) end))
			table.insert(entry.Conns, button.MouseLeave:Connect(function() scaleTo(button, 1) end))
			table.insert(entry.Conns, button.InputBegan:Connect(function(input) if isPointer(input) then scaleTo(button, 0.97, 0.08) end end))
			table.insert(entry.Conns, button.InputEnded:Connect(function(input) if isPointer(input) then scaleTo(button, 1, 0.1) end end))
		end
		return entry
	end
	local function dropRow(kind, id)
		local entry = rows[kind][id]
		if not entry then return end
		for _, c in ipairs(entry.Conns) do c:Disconnect() end
		entry.Frame:Destroy()
		rows[kind][id] = nil
		confirm[id] = nil
	end
	local function fillRow(kind, entry, item, order)
		local row = entry.Frame
		row.LayoutOrder = order
		local name, detail = row:FindFirstChild("ItemName"), row:FindFirstChild("ItemDetail")
		if kind == "Pets" then
			if name then name.Text = tostring(item.DisplayName or item.Pet or "Pet") end
			if detail then detail.RichText = true detail.Text = Core.PetDetail(item, glow) end
		else
			if name then name.Text = tostring(item.Name or item.TypeName or "Cucumber") end
			if detail then detail.RichText = true detail.Text = Core.CucumberDetail(item) end
		end
		local look = table.concat({tostring(item.Pet or item.TypeName), tostring(item.Zone), tostring(item.Material), tostring(item.Golden), tostring(item.Mutations and (type(item.Mutations) == "table" and table.concat(item.Mutations, ",") or item.Mutations))}, "|")
		if entry.Look ~= look then
			entry.Look = look
			local viewport = row:FindFirstChild("Preview")
			if viewport then
				if kind == "Pets" then PetPreview(viewport, item) else CucumberPreview(viewport, item) end
			end
		end
		entry.Item = item
		setSellLook(row, item, entry.Id)
	end

	local function renderList(kind, section, plotLevel)
		local page = pages:FindFirstChild(kind)
		if not page then return end
		local list = page:FindFirstChild("ActiveList")
		local items = type(section) == "table" and type(section.Items) == "table" and section.Items or {}
		local count = type(section) == "table" and tonumber(section.Count) or #items
		local capacity = type(section) == "table" and tonumber(section.Capacity) or 0
		local title, description, empty, notice = page:FindFirstChild("Title"), page:FindFirstChild("Description"), page:FindFirstChild("EmptyState"), page:FindFirstChild("CapacityNotice")
		if title then title.Text = string.format("%s  %d / %d", kind, count, capacity) end
		if description then description.Text = "Active in your base" end
		if empty then
			empty.Visible = #items == 0
			empty.Text = kind == "Pets" and "No pets in your base yet." or "No cucumbers in your base yet."
		end
		if notice and notice:FindFirstChild("Text") then notice.Text.Text = Core.CapacityText(kind == "Pets" and "pet" or "cucumber", count, capacity, plotLevel) end
		if not list then return end
		local seen = {}
		for order, item in ipairs(items) do
			local id = tostring(item.Id or ("row" .. order))
			seen[id] = true
			local entry = rows[kind][id]
			if not entry then
				entry = newRow(kind, id, order)
				rows[kind][id] = entry
				entry.Frame.Parent = list
			end
			fillRow(kind, entry, item, order)
		end
		for id in pairs(rows[kind]) do
			if not seen[id] then dropRow(kind, id) end
		end
	end

	local function renderZombies(z)
		local page = pages:FindFirstChild("Zombies")
		if not page then return end
		local t = Core.ZombiesTexts(z)
		local threat, survival, offline = page:FindFirstChild("ThreatCard"), page:FindFirstChild("SurvivalCard"), page:FindFirstChild("OfflineEarnings")
		if threat and threat:FindFirstChild("Value") then threat.Value.Text = t.Level end
		if survival then
			if survival:FindFirstChild("Value") then survival.Value.Text = t.Days end
			if survival:FindFirstChild("ThreatContext") then survival.ThreatContext.Text = t.Context end
		end
		if page:FindFirstChild("Description") then page.Description.Text = t.Description end
		if offline then
			local unlockedState, lockedState = offline:FindFirstChild("UnlockedState"), offline:FindFirstChild("LockedState")
			if unlockedState then unlockedState.Visible = t.Unlocked end
			if lockedState then lockedState.Visible = not t.Unlocked end
			local shown = t.Unlocked and unlockedState or lockedState
			if shown then
				if shown:FindFirstChild("Requirement") then shown.Requirement.Text = t.Requirement end
				if shown:FindFirstChild("ProgressText") then shown.ProgressText.Text = t.Progress end
				local bar = shown:FindFirstChild("SurvivalProgress")
				local fill = bar and bar:FindFirstChild("Fill")
				if fill then
					fill.Size = UDim2.fromScale(t.Fill, 1)
					fill.Visible = t.Fill > 0
				end
			end
		end
	end

	local function render()
		if destroyed then return end
		if not state then
			for _, kind in ipairs({"Pets", "Cucumbers"}) do
				local page = pages:FindFirstChild(kind)
				local empty = page and page:FindFirstChild("EmptyState")
				if empty then empty.Visible = true empty.Text = "Loading..." end
			end
			return
		end
		renderList("Pets", state.Pets, state.PlotLevel)
		renderList("Cucumbers", state.Cucumbers, state.PlotLevel)
		renderZombies(state.Zombies)
	end

	--..Server..--
	local function request(payload)
		if not remote then return nil, "Unavailable" end
		local ok, reply = pcall(remote.InvokeServer, remote, payload)
		if not ok then return nil, "Unavailable" end
		if type(reply) ~= "table" then return nil, "Unavailable" end
		return reply
	end

	local function showToast(toast)
		if type(toast) ~= "table" then return end
		Notify.Success(string.format("Offline earnings: +%s while you were away (%s at Threat Level %d)", Core.Money(toast.Cash), ManageConfig.FormatDuration(toast.Seconds), tonumber(toast.Level) or 1), 4)
	end

	local function refresh(force)
		if destroyed or not remote then return end
		local now = os.clock()
		if not force and now - lastRequest < 0.5 then
			refreshDue = true
			return
		end
		lastRequest = now
		refreshDue = false
		requestSeq += 1
		local seq = requestSeq
		task.spawn(function()
			local reply = request({Action = "GetState"})
			if destroyed or seq ~= requestSeq then return end
			if reply and reply.Ok then
				state = reply
				render()
				if reply.OfflineToast then showToast(reply.OfflineToast) end
			end
		end)
	end

	sell = function(kind, id)
		if destroyed or selling[id] then return end
		local entry = rows[kind][id]
		if not entry or not entry.Item or entry.Item.Busy then return end
		local now = os.clock()
		local armed = confirm[id] and now - confirm[id] < CONFIRM_SECONDS
		if not armed then
			confirm[id] = now
			setSellLook(entry.Frame, entry.Item, id)
			task.delay(CONFIRM_SECONDS, function()
				if not destroyed and confirm[id] == now then
					confirm[id] = nil
					local e = rows[kind][id]
					if e and e.Item then setSellLook(e.Frame, e.Item, id) end
				end
			end)
			return
		end
		confirm[id] = nil
		selling[id] = true
		setSellLook(entry.Frame, entry.Item, id)
		task.spawn(function()
			local reply, err = request({Action = kind == "Pets" and "SellPet" or "SellCucumber", Id = id})
			selling[id] = nil
			if destroyed then return end
			if reply and reply.Ok then
				Notify.Success(string.format("Sold %s for %s", tostring(reply.Name or "it"), Core.Money(reply.Cash)), 2.5)
				if SoundController and type(SoundController.PlayFX) == "function" then pcall(SoundController.PlayFX, "Sell Sound", {Volume = 0.8}) end
				dropRow(kind, id)
			else
				local code = reply and reply.Error or err or "Unavailable"
				Notify.Error(ManageConfig.ERRORS[code] or "Could not sell that.", 2.5)
				local e = rows[kind][id]
				if e and e.Item then setSellLook(e.Frame, e.Item, id) end
			end
			refresh(true)
		end)
	end

	--..Open / close, polling, plot signals..--
	local plotConns = {}
	local plotDebounce = 0
	local function watchPlot()
		for _, c in ipairs(plotConns) do c:Disconnect() end
		table.clear(plotConns)
		local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Lobby") and workspace.Map.Lobby:FindFirstChild("Plots")
		if not plots then return end
		local mine
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then mine = plot break end
		end
		if not mine then return end
		local function nudge()
			if not isOpen() then return end
			plotDebounce += 1
			local token = plotDebounce
			task.delay(PLOT_DEBOUNCE, function()
				if not destroyed and token == plotDebounce and isOpen() then refresh(false) end
			end)
		end
		for _, folderName in ipairs({"Placed", "Pets"}) do
			local folder = mine:FindFirstChild(folderName)
			if folder then
				table.insert(plotConns, folder.ChildAdded:Connect(nudge))
				table.insert(plotConns, folder.ChildRemoved:Connect(nudge))
			end
		end
	end

	local function onOpen()
		selectPage(currentPage)
		render()
		watchPlot()
		refresh(true)
		if UserInputService.GamepadEnabled then
			local first = tabs:FindFirstChild(currentPage .. "Tab")
			if first then GuiService.SelectedObject = first end
		end
	end
	local function onClose()
		for _, c in ipairs(plotConns) do c:Disconnect() end
		table.clear(plotConns)
		table.clear(confirm)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then GuiService.SelectedObject = nil end
	end
	connect(gui:GetAttributeChangedSignal("OpenPanel"), function()
		if isOpen() then onOpen() else onClose() end
	end)

	task.spawn(function()
		while not destroyed do
			task.wait(POLL_SECONDS)
			if destroyed then break end
			if isOpen() then refresh(refreshDue) end
		end
	end)

	--.. the remotes may arrive after this client (ManageService creates them at server start)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
		local r = remotes and remotes:WaitForChild(ManageConfig.REMOTE, REMOTE_WAIT)
		if destroyed then return end
		if not (r and r:IsA("RemoteFunction")) then
			warn("[ManageController] Remotes." .. ManageConfig.REMOTE .. " not found - the Manage panel shows nothing")
			return
		end
		remote = r
		local s = remotes:FindFirstChild(ManageConfig.STATE_REMOTE) or remotes:WaitForChild(ManageConfig.STATE_REMOTE, 10)
		if s and s:IsA("RemoteEvent") then
			stateRemote = s
			connect(s.OnClientEvent, function(payload)
				if type(payload) ~= "table" then return end
				if payload.Kind == "Refresh" then
					if isOpen() then refresh(false) else refresh(true) end -- closed: still fetch (an offline toast may be waiting)
				end
			end)
		end
		refresh(true) -- warms the state and collects the offline toast of a paid join
		if isOpen() then onOpen() end
	end)

	--..Studio hook..--
	connect(panel:GetAttributeChangedSignal("ManageDev"), function()
		local cmd = panel:GetAttribute("ManageDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		panel:SetAttribute("ManageDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		if kind == "open" then menus.Open("Manage")
		elseif kind == "close" then menus.Close()
		elseif kind == "tab" then selectPage(arg)
		elseif kind == "refresh" then refresh(true)
		elseif kind == "sell" then
			local n = tonumber(arg) or 1
			local kindName = currentPage == "Cucumbers" and "Cucumbers" or "Pets"
			local section = state and state[kindName]
			local item = section and section.Items and section.Items[n]
			if item then
				confirm[tostring(item.Id)] = os.clock() -- pre-armed: one call sells
				sell(kindName, tostring(item.Id))
			end
		end
	end)

	selectPage(currentPage)
	render()

	function api.Refresh() refresh(true) end
	function api.GetState() return state end
	function api.Destroy()
		destroyed = true
		for _, c in ipairs(connections) do c:Disconnect() end
		for _, c in ipairs(plotConns) do c:Disconnect() end
		for _, kind in ipairs({"Pets", "Cucumbers"}) do
			for id in pairs(rows[kind]) do dropRow(kind, id) end
		end
		for _, t in pairs(tweens) do t:Cancel() end
	end
	return api
end

return Controller

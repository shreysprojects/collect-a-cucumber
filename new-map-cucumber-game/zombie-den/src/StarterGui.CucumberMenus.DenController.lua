--[[
	DenController  (ModuleScript, StarterGui.CucumberMenus)  2026-09-24
	The client half of the ZOMBIE DEN: opens StarterGui.CucumberMenus.DenPanel (built by
	zombie-den/build_denpanel.lua in the Manage / Index look) when the player walks up to
	Map.Lobby.Stations."Zombie Den ", fills it from ServerScriptService.ZombieDenService through
	Remotes.DenRequest and trades deals in. MenuController owns the open / close motion, the close X,
	the dimmer and Escape exactly like Shop / Index / Manage; this module only decides WHEN to open
	(proximity) and what the rows say.

	  Proximity  every DenConfig.PROXIMITY_STEP s: within OPEN_RADIUS (flat) of the den's light ring, with
	             no panel open and not in build mode -> menus.Open("Den"); past CLOSE_RADIUS -> closes it.
	             Closing it by hand (X / Esc / dimmer) keeps it shut until the player walks away and back.
	  Rows       one DenRow (Templates.DenRow) per live deal, newest first: the LOST cucumber's preview
	             (CucumberIndexPreviews model + CucumberMutations.ApplyLook), "Get back: <name>", its zone /
	             traits / $rate line, "They want 3 x <kind> (<biome>)", the WANTED kind's preview with an x3
	             badge and "<have> / 3 on your base", "Deal ends in 11h 32m" (ticks every second, red under an
	             hour), TRADE IN (two taps: "SURE?" for TRADE_CONFIRM_SECONDS) - grey while short, "BY DAY" at night.
	  Refresh    on open, every POLL_SECONDS while open, after a trade, on Remotes.DenState nudges and when the
	             plot's Placed folder changes (debounced). "Offer" nudges toast the new deal even while closed;
	             "Traded" toasts the hand-back.
	  Studio hook: DenPanel attribute DenDev = "open" | "close" | "refresh" | "trade:<n>" (row n, no confirm)
	             - edge-triggered, cleared after it runs.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DenConfig = require(Modules:WaitForChild("DenConfig"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local Notify = require(Modules:WaitForChild("Notify"))
local okMut, CucumberMutations = pcall(function() return require(Modules:WaitForChild("CucumberMutations", 5)) end)
if not okMut then CucumberMutations = nil end
local okSound, SoundController = pcall(function() return require(Modules:WaitForChild("SoundController", 5)) end)
if not okSound then SoundController = nil end

local player = Players.LocalPlayer
local C = Color3.fromRGB

local POLL_SECONDS = 4
local TICK_SECONDS = 1
local PLOT_DEBOUNCE = 0.4
local REMOTE_WAIT = 60
local PREVIEW_FOV = 32
local PREVIEW_DIRECTION = Vector3.new(0.363, 0.2, 0.909).Unit -- the designer's preview camera (Manage rows)
local PREVIEW_YAW = math.rad(-18)
local URGENT_SECONDS = 3600 -- the countdown turns red under this
local BUTTON_ON = {Top = C(155, 255, 51), Bottom = C(66, 214, 5), Rim = C(222, 255, 176), Border = C(36, 72, 12)} -- the SELL look
local BUTTON_OFF = {Top = C(190, 190, 200), Bottom = C(120, 120, 135), Rim = C(225, 225, 235), Border = C(60, 60, 70)}
local COUNTDOWN_COLOR = C(255, 255, 255)
local COUNTDOWN_URGENT = C(255, 120, 120)
local CUCUMBER_FALLBACK = {Cucumber = "Spawn Cucumber", ["Giant Cucumber"] = "Spawn Cucumber", ["Sliced Cucumber"] = "Spawn Sliced Cucumber", ["Cucumber Tree"] = "Cucumber Tree"}

local Controller = {}
Controller.Core = {}
local Core = Controller.Core

--..Pure helpers (tests)..--
function Core.Rate(n) return "$" .. NumberAbbrev.Abbrev(tonumber(n) or 0) .. "/s" end

local function Escape(s)
	return (tostring(s):gsub("[<>&]", {["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;"}))
end

--.. "Desert - Golden HUGE - $2.1/s"
function Core.Detail(offer)
	local parts = {Escape(offer.Zone or "Spawn")}
	local traits = {}
	local material = offer.Material
	if (material == nil or material == "") and offer.Golden then material = "Golden" end
	if type(material) == "string" and material ~= "" then table.insert(traits, material) end
	if type(offer.Mutations) == "string" and offer.Mutations ~= "" then table.insert(traits, (offer.Mutations:gsub(",", " "))) end
	if type(offer.SizeTier) == "string" and offer.SizeTier ~= "" then table.insert(traits, offer.SizeTier) end
	if #traits > 0 then table.insert(parts, Escape(table.concat(traits, " "))) end
	table.insert(parts, Core.Rate(offer.Rate))
	return table.concat(parts, "  -  ")
end

--.. "They want 3 x Prickly Cucumber (Desert)"
function Core.WantLine(offer)
	local want = type(offer.Want) == "table" and offer.Want or {}
	return string.format("They want %s (%s)", DenConfig.WantText(want, offer.Need), tostring(want.Zone or "?"))
end

function Core.HaveText(offer)
	return string.format("%d / %d on your base", math.max(0, tonumber(offer.Have) or 0), tonumber(offer.Need) or DenConfig.NEED)
end

function Core.CountdownText(secondsLeft)
	return "Deal ends in " .. DenConfig.Countdown(secondsLeft)
end

--.. what the TRADE IN button shows: action text, progress text, enabled
function Core.ButtonTexts(offer, night, armed, busy)
	local have, need = math.max(0, tonumber(offer.Have) or 0), tonumber(offer.Need) or DenConfig.NEED
	if busy then return "...", "", false end
	if night then return "TRADE IN", "BY DAY", false end
	if have >= need then return armed and "SURE?" or "TRADE IN", "READY!", true end
	return "TRADE IN", string.format("%d / %d", have, need), false
end

function Core.TitleText(count)
	return string.format("Stolen from you  %d", math.max(0, tonumber(count) or 0))
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

local function PreviewSource(zone, typeName)
	local previews = ReplicatedStorage:FindFirstChild("CucumberIndexPreviews")
	if not previews then return nil end
	zone, typeName = tostring(zone or "Spawn"), tostring(typeName or "")
	return previews:FindFirstChild(DenConfig.PreviewName(zone, typeName)) or previews:FindFirstChild(typeName) or previews:FindFirstChild(CUCUMBER_FALLBACK[typeName] or "")
end

local function LostPreview(viewport, offer)
	local material = offer.Material
	if (material == nil or material == "") and offer.Golden then material = "Golden" end
	ShowModel(viewport, PreviewSource(offer.Zone, offer.Type), material, offer.Mutations)
end

local function WantPreview(viewport, offer)
	local want = type(offer.Want) == "table" and offer.Want or {}
	ShowModel(viewport, PreviewSource(want.Zone, want.Type), nil, nil)
end

--..The den's spot in the world..--
local denCenter = nil
local function DenCenter()
	if denCenter then return denCenter end
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local stations = lobby and lobby:FindFirstChild("Stations")
	local den = stations and stations:FindFirstChild(DenConfig.DEN_STATION)
	if not den then return nil end
	local ring
	local light = den:FindFirstChild("Circle Light")
	if light then
		for _, p in ipairs(light:GetChildren()) do
			if p:IsA("BasePart") and p.Size.X > 6 and (not ring or p.Size.Y > ring.Size.Y) then ring = p end -- the 9.5-stud disc
		end
	end
	denCenter = ring and ring.Position or den:GetPivot().Position
	return denCenter
end

--..Start..--
function Controller.Start(gui, menus)
	local api = {}
	local connections = {}
	local destroyed = false
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end

	local panel = gui:FindFirstChild("DenPanel")
	local content = panel and panel:FindFirstChild("Content")
	local templates = panel and panel:FindFirstChild("Templates")
	local rowTemplate = templates and templates:FindFirstChild("DenRow")
	local list = content and content:FindFirstChild("OfferList")
	if not (content and rowTemplate and list) then
		warn("[DenController] DenPanel is missing or incomplete - the Zombie Den panel is unavailable")
		function api.Destroy() end
		return api
	end
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("CucumberHUDDesign")

	--.. a ClickShield keeps body clicks off the dimmer (the Manage panel's trick)
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
		local s = target:FindFirstChild("DenScale")
		if not s then
			s = Instance.new("UIScale")
			s.Name = "DenScale"
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

	--..State..--
	local state = nil
	local rows = {} -- [id] = {Frame, Offer, Conns, Look, Expired}
	local confirm = {} -- [id] = os.clock() of the first tap
	local trading = {} -- [id] = true while the request is out
	local remote, stateRemote = nil, nil
	local requestSeq = 0
	local lastRequest = 0
	local refreshDue = false

	local function isOpen()
		return gui:GetAttribute("OpenPanel") == "Den"
	end
	local function isNight()
		if state and state.Night ~= nil then return state.Night == true end
		return workspace:GetAttribute("CyclePhase") == "Night"
	end

	--..Rows..--
	local function paintButton(button, on)
		local look = on and BUTTON_ON or BUTTON_OFF
		local gradient = button:FindFirstChild("Gradient")
		if gradient then gradient.Color = ColorSequence.new(look.Top, look.Bottom) end
		local stroke = button:FindFirstChild("UIStroke")
		if stroke then stroke.Color = look.Border end
		local rim = button:FindFirstChild("InnerRim")
		local border = rim and rim:FindFirstChild("Border")
		if border then border.Color = look.Rim end
	end

	local function setButtonLook(row, offer, id)
		local button = row:FindFirstChild("TradeButton")
		if not button then return end
		local armed = confirm[id] ~= nil and os.clock() - confirm[id] < DenConfig.TRADE_CONFIRM_SECONDS
		local action, progress, enabled = Core.ButtonTexts(offer, isNight(), armed, trading[id] == true)
		local actionLabel, progressLabel = button:FindFirstChild("Action"), button:FindFirstChild("Progress")
		if actionLabel then actionLabel.Text = action end
		if progressLabel then progressLabel.Text = progress end
		paintButton(button, enabled)
		button.Active = enabled
		button.AutoButtonColor = false
	end

	local function setCountdown(row, entry)
		local label = row:FindFirstChild("Expires")
		if not label then return end
		local left = (tonumber(entry.Offer.ExpiresAt) or 0) - workspace:GetServerTimeNow()
		label.Text = Core.CountdownText(left)
		label.TextColor3 = left < URGENT_SECONDS and COUNTDOWN_URGENT or COUNTDOWN_COLOR
		return left
	end

	local trade -- forward
	local function newRow(id, order)
		local row = rowTemplate:Clone()
		row.Name = "DenRow_" .. tostring(order)
		row:SetAttribute("PreviewOnly", nil)
		row:SetAttribute("PreviewCollected", nil)
		row:SetAttribute("CucumberName", nil)
		row:SetAttribute("OfferId", id)
		row.Visible = true
		local entry = {Frame = row, Id = id, Conns = {}}
		local button = row:FindFirstChild("TradeButton")
		if button then
			table.insert(entry.Conns, button.Activated:Connect(function() trade(id) end))
			table.insert(entry.Conns, button.MouseEnter:Connect(function() scaleTo(button, 1.035) end))
			table.insert(entry.Conns, button.MouseLeave:Connect(function() scaleTo(button, 1) end))
			table.insert(entry.Conns, button.InputBegan:Connect(function(input) if isPointer(input) then scaleTo(button, 0.97, 0.08) end end))
			table.insert(entry.Conns, button.InputEnded:Connect(function(input) if isPointer(input) then scaleTo(button, 1, 0.1) end end))
		end
		return entry
	end
	local function dropRow(id)
		local entry = rows[id]
		if not entry then return end
		for _, c in ipairs(entry.Conns) do c:Disconnect() end
		entry.Frame:Destroy()
		rows[id] = nil
		confirm[id] = nil
	end
	local function fillRow(entry, offer, order)
		local row = entry.Frame
		row.LayoutOrder = order
		local name, detail, wantLine, have = row:FindFirstChild("ItemName"), row:FindFirstChild("ItemDetail"), row:FindFirstChild("WantLine"), row:FindFirstChild("HaveLabel")
		if name then name.Text = "Get back: " .. tostring(offer.Name or offer.Type or "cucumber") end
		if detail then
			detail.RichText = true
			detail.Text = Core.Detail(offer)
		end
		if wantLine then wantLine.Text = Core.WantLine(offer) end
		if have then have.Text = Core.HaveText(offer) end
		local want = type(offer.Want) == "table" and offer.Want or {}
		local look = table.concat({tostring(offer.Type), tostring(offer.Zone), tostring(offer.Material), tostring(offer.Golden), tostring(offer.Mutations), tostring(want.Zone), tostring(want.Type)}, "|")
		if entry.Look ~= look then
			entry.Look = look
			local lostView, wantView = row:FindFirstChild("LostPreview"), row:FindFirstChild("WantPreview")
			if lostView then LostPreview(lostView, offer) end
			if wantView then WantPreview(wantView, offer) end
		end
		entry.Offer = offer
		entry.Expired = false
		setButtonLook(row, offer, entry.Id)
		setCountdown(row, entry)
	end

	local function render()
		if destroyed then return end
		local title, description, empty, notice = content:FindFirstChild("ListTitle"), content:FindFirstChild("ListDescription"), content:FindFirstChild("EmptyState"), content:FindFirstChild("Notice")
		if not state then
			if empty then
				empty.Visible = true
				empty.Text = "Loading..."
			end
			return
		end
		local offers = type(state.Offers) == "table" and state.Offers or {}
		if title then title.Text = Core.TitleText(#offers) end
		if description then description.Text = string.format("Each deal lasts %s. Bring %d of what the zombies want and yours comes back.", DenConfig.Countdown(DenConfig.OFFER_SECONDS), tonumber(state.Need) or DenConfig.NEED) end
		if empty then
			empty.Visible = #offers == 0
			empty.Text = "The zombies have nothing of yours."
		end
		if notice and notice:FindFirstChild("Text") then
			notice.Text.Text = isNight() and "The den trades by daylight only. Come back in the morning."
				or "Place the wanted cucumbers on your base, then TRADE IN here. Daytime only."
		end
		local seen = {}
		for order, offer in ipairs(offers) do
			local id = tostring(offer.Id or ("row" .. order))
			seen[id] = true
			local entry = rows[id]
			if not entry then
				entry = newRow(id, order)
				rows[id] = entry
				entry.Frame.Parent = list
			end
			fillRow(entry, offer, order)
		end
		for id in pairs(rows) do
			if not seen[id] then dropRow(id) end
		end
	end

	--..Server..--
	local function request(payload)
		if not remote then return nil, "Unavailable" end
		local ok, reply = pcall(remote.InvokeServer, remote, payload)
		if not ok then return nil, "Unavailable" end
		if type(reply) ~= "table" then return nil, "Unavailable" end
		return reply
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
			end
		end)
	end

	trade = function(id)
		if destroyed or trading[id] then return end
		local entry = rows[id]
		if not entry or not entry.Offer then return end
		local _, _, enabled = Core.ButtonTexts(entry.Offer, isNight(), false, false)
		if not enabled then
			if isNight() then Notify.Warn(DenConfig.ERRORS.Night, 2.5)
			else Notify.Warn(string.format("Place %s on your base first (%s).", DenConfig.WantText(entry.Offer.Want, entry.Offer.Need), Core.HaveText(entry.Offer)), 3) end
			return
		end
		local now = os.clock()
		local armed = confirm[id] and now - confirm[id] < DenConfig.TRADE_CONFIRM_SECONDS
		if not armed then
			confirm[id] = now
			setButtonLook(entry.Frame, entry.Offer, id)
			task.delay(DenConfig.TRADE_CONFIRM_SECONDS, function()
				if not destroyed and confirm[id] == now then
					confirm[id] = nil
					local e = rows[id]
					if e and e.Offer then setButtonLook(e.Frame, e.Offer, id) end
				end
			end)
			return
		end
		confirm[id] = nil
		trading[id] = true
		setButtonLook(entry.Frame, entry.Offer, id)
		task.spawn(function()
			local reply, err = request({Action = "TradeIn", Id = id})
			trading[id] = nil
			if destroyed then return end
			if reply and reply.Ok then
				Notify.Success(string.format("Your %s is back! Pick it up at the den.", tostring(reply.Name or "cucumber")), 3.5)
				if SoundController and type(SoundController.PlayFX) == "function" then pcall(SoundController.PlayFX, "Success", {Volume = 0.8}) end
				dropRow(id)
			else
				local code = reply and reply.Error or err or "Unavailable"
				Notify.Error(DenConfig.ERRORS[code] or "Could not trade that in.", 2.5)
				local e = rows[id]
				if e and e.Offer then setButtonLook(e.Frame, e.Offer, id) end
			end
			refresh(true)
		end)
	end

	--..Countdowns..--
	task.spawn(function()
		while not destroyed do
			task.wait(TICK_SECONDS)
			if destroyed then break end
			if not isOpen() then continue end
			local expired = false
			for id, entry in pairs(rows) do
				if entry.Offer then
					local left = setCountdown(entry.Frame, entry)
					if left and left <= 0 and not entry.Expired then
						entry.Expired = true
						expired = true
					end
				end
			end
			if expired then refresh(true) end
		end
	end)

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
		local folder = mine and mine:FindFirstChild("Placed")
		if not folder then return end
		local function nudge()
			if not isOpen() then return end
			plotDebounce += 1
			local token = plotDebounce
			task.delay(PLOT_DEBOUNCE, function()
				if not destroyed and token == plotDebounce and isOpen() then refresh(false) end
			end)
		end
		table.insert(plotConns, folder.ChildAdded:Connect(nudge))
		table.insert(plotConns, folder.ChildRemoved:Connect(nudge))
	end

	local function onOpen()
		render()
		watchPlot()
		refresh(true)
		if UserInputService.GamepadEnabled and content:FindFirstChild("CloseButton") then GuiService.SelectedObject = content.CloseButton end
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
	connect(workspace:GetAttributeChangedSignal("CyclePhase"), function()
		if isOpen() then refresh(true) end
	end)

	task.spawn(function()
		while not destroyed do
			task.wait(POLL_SECONDS)
			if destroyed then break end
			if isOpen() then refresh(refreshDue) end
		end
	end)

	--..Proximity: walk up to the den = the panel opens; walk away = it closes..--
	local function inBuildMode()
		return hud ~= nil and hud:GetAttribute("BuildMode") == true
	end
	local armedProximity = true
	task.spawn(function()
		while not destroyed do
			task.wait(DenConfig.PROXIMITY_STEP)
			if destroyed then break end
			local center = DenCenter()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if center and root then
				local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
				local open = menus.GetOpenPanel()
				if d <= DenConfig.OPEN_RADIUS then
					if armedProximity and open == nil and not inBuildMode() then
						armedProximity = false
						menus.Open("Den")
					end
				elseif d > DenConfig.CLOSE_RADIUS then
					armedProximity = true
					if open == "Den" then menus.Close() end
				end
			end
		end
	end)

	--.. the remotes may arrive after this client (ZombieDenService creates them at server start)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
		local r = remotes and remotes:WaitForChild(DenConfig.REMOTE, REMOTE_WAIT)
		if destroyed then return end
		if not (r and r:IsA("RemoteFunction")) then
			warn("[DenController] Remotes." .. DenConfig.REMOTE .. " not found - the Zombie Den panel shows nothing")
			return
		end
		remote = r
		local s = remotes:FindFirstChild(DenConfig.STATE_REMOTE) or remotes:WaitForChild(DenConfig.STATE_REMOTE, 10)
		if s and s:IsA("RemoteEvent") then
			stateRemote = s
			connect(s.OnClientEvent, function(payload)
				if type(payload) ~= "table" then return end
				if payload.Kind == "Refresh" then
					if isOpen() then refresh(false) end
				elseif payload.Kind == "Offer" then
					local want = type(payload.Want) == "table" and payload.Want or {}
					Notify.Info(string.format("The Zombie Den will trade your %s back for %s!", tostring(payload.Name or "cucumber"), DenConfig.WantText(want, payload.Need)), 4)
					if isOpen() then refresh(true) end
				elseif payload.Kind == "Traded" then
					if isOpen() then refresh(false) end
				end
			end)
		end
		if isOpen() then onOpen() end
	end)

	--..Studio hook..--
	connect(panel:GetAttributeChangedSignal("DenDev"), function()
		local cmd = panel:GetAttribute("DenDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		panel:SetAttribute("DenDev", nil)
		local kind, arg = cmd:match("^(%w+):?(.*)$")
		if kind == "open" then menus.Open("Den")
		elseif kind == "close" then menus.Close()
		elseif kind == "refresh" then refresh(true)
		elseif kind == "arm" then armedProximity = true
		elseif kind == "trade" then
			local n = tonumber(arg) or 1
			local offer = state and state.Offers and state.Offers[n]
			if offer then
				confirm[tostring(offer.Id)] = os.clock() -- pre-armed: one call trades
				trade(tostring(offer.Id))
			end
		end
	end)

	render()

	function api.Refresh() refresh(true) end
	function api.GetState() return state end
	function api.Destroy()
		destroyed = true
		for _, c in ipairs(connections) do c:Disconnect() end
		for _, c in ipairs(plotConns) do c:Disconnect() end
		for id in pairs(rows) do dropRow(id) end
		for _, t in pairs(tweens) do t:Cancel() end
	end
	return api
end

return Controller

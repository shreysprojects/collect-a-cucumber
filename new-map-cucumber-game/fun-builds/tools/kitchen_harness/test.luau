--!nocheck
-- Kitchen (Fridge / Microwave) offline harness, fun-builds 2026-09-24. Runs the REAL server + client halves on mocks,
-- with the real part names / authored CFrames from models/out/<Key>.parts.json, a scaled + yawed placement, and the
-- server state "replicated" straight into the client's OnState handlers. Checks the fix-pass items:
--   * the first heat after a client starts ends with a Ding + steam, and the Start button beeps
--   * a move / mend reset (state cleared, then 0) is silent: no close thud / clunk, no button press, no ding
--   * dedicated sounds play at PlaybackSpeed 1, clips start at their Skip, close sounds land their thud at the swing end
--   * door angles, turntable one turn, lights, mist, cleanup back to the home pose
--   powershell -NoProfile -ExecutionPolicy Bypass -File tools\kitchen_harness\run.ps1
local M = require("./mocks")
local V, CF, new = M.Vector3.new, M.CFrame, M.new

--==================================================================== world
local workspace = new("Workspace")
workspace.Name = "Workspace"
workspace.CurrentCamera = new("Camera", workspace)
function workspace.GetServerTimeNow() return M.clock end
local RS = new("Folder") RS.Name = "ReplicatedStorage"
local Modules = new("Folder", RS) Modules.Name = "Modules"
local kitMS = new("ModuleScript", Modules) kitMS.Name = "FunBuildKit"
local assetsMS = new("ModuleScript", Modules) assetsMS.Name = "FunAssets"
local RunService = {Stepped = M.Signal(), RenderStepped = M.Signal(), Heartbeat = M.Signal()}
function RunService.IsServer() return true end
local Lighting = {ClockTime = 14.5}
local game = {}
function game.GetService(_, name)
	if name == "ReplicatedStorage" then return RS end
	if name == "RunService" then return RunService end
	if name == "Lighting" then return Lighting end
	if name == "Workspace" then return workspace end
	error("service " .. name)
end

local loaded = {}
local env
local function load(name)
	if loaded[name] == nil then loaded[name] = require("./mod_" .. name)(env) end
	return loaded[name]
end
env = {
	game = game, workspace = workspace, Instance = M.Instance, Vector3 = M.Vector3, CFrame = M.CFrame, Color3 = M.Color3,
	Vector2 = M.Vector2, UDim2 = M.UDim2, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence,
	NumberSequenceKeypoint = M.NumberSequenceKeypoint, ColorSequence = M.ColorSequence, Enum = M.Enum, typeof = M.typeof,
	task = M.task, os = {clock = function() return M.clock end, time = os.time},
	warn = function(...) print("WARN", ...) error("warned: " .. table.concat({...}, " ")) end,
	require = function(ms)
		if ms == kitMS then return load("FunBuildKit") end
		if ms == assetsMS then return load("FunAssets") end
		error("require " .. tostring(ms))
	end,
}
local Kit = load("FunBuildKit")
local Sfx = load("FunAssets").Sfx

local failures = 0
local function check(ok, msg)
	if ok then print("  ok   " .. msg) else failures += 1 print("  FAIL " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end

--==================================================================== a placed build from its parts.json
local function toV3(t) return V(t[1], t[2], t[3]) end
local function Build(key, scale, yawDeg, at)
	local data = require("./parts_" .. key)
	local model = new("Model", workspace)
	model.Name = key
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Scale", scale)
	local mn, mx = toV3(data.min), toV3(data.max)
	local centre = (mn + mx) / 2
	model:SetAttribute("AuthoredCentre", centre)
	for k, v in pairs(data.pivots) do model:SetAttribute("Pivot_" .. k, toV3(v)) end
	for k, v in pairs(data.attrs) do
		model:SetAttribute(k, (type(v) == "table" and #v == 3) and toV3(v) or v)
	end
	local hitbox = new("Part", model)
	hitbox.Name = "Hitbox"
	hitbox.Size = (mx - mn) * scale
	hitbox.CFrame = CF.new(at.X, centre.Y * scale, at.Z) * CF.Angles(0, math.rad(yawDeg), 0)
	model.PrimaryPart = hitbox
	for _, p in ipairs(data.parts) do
		local part = new("Part", model)
		part.Name = p.name
		part.Size = toV3(p.size) * scale
		local c = p.cf
		part.CFrame = Kit.CFrameToWorld(model, CF.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]))
		part.CanCollide = p.collide
		part.Material = "Enum.Material.SmoothPlastic"
		part.Color = M.Color3.new(0.8, 0.8, 0.8)
	end
	return model
end

--==================================================================== ctx doubles (framework semantics, see FunBuildService / FunBuildClient)
local player = new("Player") player.Name = "Tester"
local function ServerCtx(model)
	local ctx = {Model = model, Key = model.Name, Scale = Kit.Scale(model), _conns = {}, _insts = {}, _states = {}, _alive = true}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:SetState(k, v) self._states[k] = true model:SetAttribute(Kit.STATE_PREFIX .. k, v) end
	function ctx:GetState(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	function ctx:HumanoidOf() return true, true end
	function ctx:Prompt(part, opts)
		local a = new("Attachment", part) a.Name = "FunPromptAt" a.Position = opts.Offset
		local pr = new("ProximityPrompt", a)
		pr.Name = opts.Name or "FunPrompt" pr.ActionText = opts.Action pr.ObjectText = opts.Object pr.KeyboardKeyCode = opts.Key
		return self:Add(pr)
	end
	--.. the framework's stop: disconnect, destroy, clear every Fun_ state it set
	function ctx:Stop()
		self._alive = false
		for _, c in ipairs(self._conns) do c:Disconnect() end
		for _, i in ipairs(self._insts) do i:Destroy() end
		for k in pairs(self._states) do model:SetAttribute(Kit.STATE_PREFIX .. k, nil) end
	end
	return ctx
end

local clients = {}
local function ClientCtx(model)
	local ctx = {Model = model, Key = model.Name, Base = model.Name, Scale = Kit.Scale(model), Player = player,
		_conns = {}, _insts = {}, _clean = {}, _alive = true}
	function ctx:Alive() return self._alive end
	function ctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
	function ctx:Add(i) table.insert(self._insts, i) return i end
	function ctx:OnCleanup(fn) table.insert(self._clean, fn) end
	function ctx:State(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	function ctx:OnState(k, fn)
		local name = Kit.STATE_PREFIX .. k
		self:Connect(model:GetAttributeChangedSignal(name), function() fn(model:GetAttribute(name)) end)
		M.task.spawn(fn, model:GetAttribute(name))
	end
	function ctx:Step(fn) self._step = fn end
	function ctx:Every(sec, fn)
		local function loop()
			if not self._alive then return end
			fn()
			M.task.delay(sec, loop)
		end
		M.task.delay(sec, loop)
	end
	function ctx:Sound(parent, id, props)
		local s = new("Sound", parent)
		s.SoundId = tostring(id) s.TimePosition = 0 s.PlaybackSpeed = 1 s.Volume = 0.5
		for k, v in pairs(props or {}) do s[k] = v end
		return self:Add(s)
	end
	function ctx:Part(props)
		local p = new("Part")
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent then p.Parent = workspace.CurrentCamera end
		return self:Add(p)
	end
	function ctx:CameraDistance() return 12 end
	function ctx:Stop()
		self._alive = false
		for _, c in ipairs(self._conns) do c:Disconnect() end
		if self._cleanup then self._cleanup() end
		for _, fn in ipairs(self._clean) do fn() end
		for _, i in ipairs(self._insts) do i:Destroy() end
		for i, c in ipairs(clients) do if c == self then table.remove(clients, i) break end end
	end
	return ctx
end
local function StartClient(model, B)
	local ctx = ClientCtx(model)
	ctx._cleanup = B.Client(model, ctx)
	table.insert(clients, ctx)
	return ctx
end

local DT = 1 / 60
local function Run(seconds, onFrame)
	local n = math.floor(seconds / DT + 0.5)
	for _ = 1, n do
		M.clock += DT
		M.runDue()
		for _, c in ipairs(table.clone(clients)) do if c._step and c._alive then c._step(DT, M.clock) end end
		if onFrame then onFrame() end
	end
end
local function PlayedSince(mark, id)
	local out = {}
	for i = mark + 1, #M.played do
		if id == nil or M.played[i].Id == id then table.insert(out, M.played[i]) end
	end
	return out
end
local function Yaw(part, homeCF)
	local a, b = homeCF.LookVector, part.CFrame.LookVector
	return math.deg(math.atan2(a:Cross(b).Y, a:Dot(b)))
end
local function PromptNamed(model, name)
	for _, d in ipairs(model:GetDescendants()) do if d.Name == name and d.ClassName == "ProximityPrompt" then return d end end
	return nil
end
local function CamPart(name)
	for _, p in ipairs(workspace.CurrentCamera:GetChildren()) do if p.Name == name then return p end end
	return nil
end

M.clock = 1000

--==================================================================== FRIDGE (x1.2, yawed 90)
print("FRIDGE")
do
	local FridgeServer, FridgeClient = load("FridgeServer"), load("FridgeClient")
	local fridge = Build("Fridge", 1.2, 90, V(40, 0, 10))
	local panel, fpanel, strip = fridge:FindFirstChild("DoorPanel"), fridge:FindFirstChild("FreezerDoorPanel"), fridge:FindFirstChild("LightStrip")
	local panelHome, fpanelHome = panel.CFrame, fpanel.CFrame
	local sctx = ServerCtx(fridge)
	FridgeServer.Server(fridge, sctx)
	local cctx = StartClient(fridge, FridgeClient)
	Run(0.5)
	local doorPrompt, freezerPrompt = PromptNamed(fridge, "FridgeDoorPrompt"), PromptNamed(fridge, "FreezerDoorPrompt")
	check(doorPrompt ~= nil and freezerPrompt ~= nil and doorPrompt.Parent.Parent.Name == "SkinL", "both prompts on SkinL")

	local hum
	for _, i in ipairs(cctx._insts) do if i.ClassName == "Sound" and i.Looped then hum = i end end
	check(hum and hum.SoundId == Sfx.FridgeHum and hum.PlaybackSpeed == 1 and hum.IsPlaying, "hum = FridgeHum at speed 1, running near")

	-- open
	local mark = #M.played
	doorPrompt.Triggered:Fire(player)
	check((fridge:GetAttribute("Fun_Door") or 0) > 0 and doorPrompt.ActionText == "Close", "E opens: Fun_Door > 0, prompt reads Close")
	Run(0.8)
	local opens = PlayedSince(mark, Sfx.FridgeOpen)
	check(#opens == 1 and near(opens[1].TimePosition, 0.5) and opens[1].Sound.PlaybackSpeed == 1, "FridgeOpen once, from 0.5 s, speed 1")
	check(near(Yaw(panel, panelHome), 100, 0.5), ("fridge door at 100 deg (%.2f)"):format(Yaw(panel, panelHome)))
	check(near(Yaw(fpanel, fpanelHome), 0, 1e-4), "freezer door untouched")
	check(strip.Material == "Enum.Material.Neon", "LightStrip Neon while open")
	local light = CamPart("FridgeLight"):FindFirstChildOfClass("PointLight")
	check(light and light.Enabled, "fridge PointLight on")
	local mist = CamPart("FridgeMist"):FindFirstChild("ColdMist")
	check(mist.Enabled and mist.Emitted == 8, "mist on + 8-particle burst")
	check(near(hum.Volume, 0.16), "hum a touch louder while open")
	check(panel.CanCollide == false, "open door does not collide locally")

	-- close: the thud lands as the swing ends
	mark = #M.played
	local closedAt = M.clock
	doorPrompt.Triggered:Fire(player)
	local thudAt
	Run(0.8, function()
		if not thudAt and #PlayedSince(mark, Sfx.FridgeClose) > 0 then thudAt = M.clock - closedAt end
	end)
	local closes = PlayedSince(mark, Sfx.FridgeClose)
	check(#closes == 1 and closes[1].Sound.PlaybackSpeed == 1, "FridgeClose once, speed 1")
	check(thudAt and near(thudAt + 0.35, 0.6, DT * 1.5), ("close clip starts %.3f s in, its thud (0.35 s) lands at the 0.6 s swing end"):format(thudAt or -1))
	check(near(Yaw(panel, panelHome), 0, 1e-3) and panel.CanCollide == true, "door shut and solid again")
	check(strip.Material == "Enum.Material.SmoothPlastic" and not light.Enabled and not mist.Enabled, "strip plain, light + mist off")

	-- freezer opens, then the build is MOVED while it is open (server restart: state cleared -> 0)
	freezerPrompt.Triggered:Fire(player)
	Run(0.8)
	check(near(Yaw(fpanel, fpanelHome), 100, 0.5), "freezer door open")
	mark = #M.played
	sctx:Stop()
	sctx = ServerCtx(fridge)
	FridgeServer.Server(fridge, sctx)
	Run(0.3)
	check(#PlayedSince(mark) == 0, "move reset: no sound at all (no false thud) on the old client ctx")
	check(near(Yaw(fpanel, fpanelHome), 0, 1e-3) and near(Yaw(panel, panelHome), 0, 1e-3), "move reset: both doors snap shut")
	-- the framework restarts the client 0.3 s later
	cctx:Stop()
	check(panel.CFrame:FuzzyEq(panelHome, 1e-4) and fpanel.CFrame:FuzzyEq(fpanelHome, 1e-4), "cleanup: doors back on their home CFrames")
	mark = #M.played
	cctx = StartClient(fridge, FridgeClient)
	Run(0.8)
	check(#PlayedSince(mark, Sfx.FridgeClose) == 0 and #PlayedSince(mark, Sfx.FridgeOpen) == 0, "restarted client: silent, doors shut")
	-- after the restart the doors still work
	mark = #M.played
	PromptNamed(fridge, "FridgeDoorPrompt").Triggered:Fire(player)
	Run(0.8)
	check(#PlayedSince(mark, Sfx.FridgeOpen) == 1 and near(Yaw(panel, panelHome), 100, 0.5), "after the move: E opens with its sound")
	cctx:Stop()
	sctx:Stop()
end

--==================================================================== MICROWAVE (x1.0, yawed -90)
print("MICROWAVE")
do
	local MwServer, MwClient = load("MicrowaveServer"), load("MicrowaveClient")
	local mw = Build("Microwave", 1, -90, V(-20, 0, 5))
	local frame, mug, btnStart = mw:FindFirstChild("DoorFrameL"), mw:FindFirstChild("TurntableMug"), mw:FindFirstChild("BtnStart")
	local frameHome, mugHome, btnHome = frame.CFrame, mug.CFrame, btnStart.CFrame
	local btnOpen = mw:FindFirstChild("BtnOpen")
	local btnOpenHome = btnOpen.CFrame
	local sctx = ServerCtx(mw)
	MwServer.Server(mw, sctx)
	local cctx = StartClient(mw, MwClient)
	Run(0.5)
	local heat, door = PromptNamed(mw, "MicrowaveHeatPrompt"), PromptNamed(mw, "MicrowaveDoorPrompt")
	check(heat and door and heat.Parent.Parent.Name == "KeypadPanel", "Heat + Open prompts on KeypadPanel")
	local hum
	for _, i in ipairs(cctx._insts) do if i.ClassName == "Sound" and i.Looped then hum = i end end
	check(hum and hum.SoundId == Sfx.MicrowaveHum and hum.PlaybackSpeed == 1, "hum = MicrowaveHum at speed 1")

	-- the FIRST heat after the client started (the fix-pass bug): beep + press, spin, then Ding + steam
	local mark = #M.played
	local t0 = M.clock
	heat.Triggered:Fire(player)
	local pressed, humMid, lcdMid, doneT = false, false, nil, nil
	local label = mw:FindFirstChild("Display"):FindFirstChild("MicrowaveDisplay"):FindFirstChild("Digits")
	Run(5.6, function()
		local t = M.clock - t0
		if t < 0.1 and not btnStart.CFrame:FuzzyEq(btnHome, 1e-5) then pressed = true end
		if near(t, 2.5, DT / 2) then humMid = hum.IsPlaying lcdMid = label.Text end
		if not doneT and #PlayedSince(mark, Sfx.Ding) > 0 then doneT = t end
	end)
	local beeps = PlayedSince(mark, Sfx.MicrowaveBeep)
	check(#beeps == 1 and beeps[1].Sound.PlaybackSpeed == 1, "first heat: MicrowaveBeep once, speed 1")
	check(pressed and btnStart.CFrame:FuzzyEq(btnHome, 1e-5), "first heat: Start button dipped and came back")
	check(humMid and not hum.IsPlaying, "hum ran mid-heat and stopped after")
	check(lcdMid == "0:03", "LCD counts down (" .. tostring(lcdMid) .. " at 2.5 s)")
	local dings = PlayedSince(mark, Sfx.Ding)
	check(#dings == 1 and near(dings[1].TimePosition, 0.15), "first heat: Ding once, from 0.15 s")
	check(doneT and near(doneT, 5, DT * 1.5), ("ding at the end of the 5 s heat (%.3f)"):format(doneT or -1))
	check(CamPart("MicrowaveSteam"):FindFirstChild("Steam").Emitted == 14, "first heat: 14-particle steam puff")
	check(mug.CFrame:FuzzyEq(mugHome, 1e-4), "turntable made exactly one turn (mug back home)")
	check(mw:GetAttribute("Fun_Heat") == 0 and (mw:GetAttribute("Fun_Done") or 0) > 0, "Fun_Heat 0, Fun_Done set")

	-- door: open squeak from 0.5 s, swing to -100
	mark = #M.played
	door.Triggered:Fire(player)
	Run(0.6)
	local opens = PlayedSince(mark, Sfx.DoorOpen)
	check(#opens == 1 and near(opens[1].TimePosition, 0.5), "door opens: DoorOpen once from 0.5 s")
	check(near(Yaw(frame, frameHome), -100, 0.5), ("door at -100 deg (%.2f)"):format(Yaw(frame, frameHome)))

	-- Heat with the door open: it swings shut (clunk lands at the swing end), then heats, then dings
	mark = #M.played
	local closeT0 = M.clock
	heat.Triggered:Fire(player)
	local clunkAt
	Run(6.2, function()
		if not clunkAt and #PlayedSince(mark, Sfx.DoorClose) > 0 then clunkAt = M.clock - closeT0 end
	end)
	local clunks = PlayedSince(mark, Sfx.DoorClose)
	check(#clunks == 1 and clunkAt and near(clunkAt + 0.25 / 1.15, 0.45, DT * 1.5),
		("close clunk starts %.3f s in and lands at the 0.45 s swing end"):format(clunkAt or -1))
	check(#PlayedSince(mark, Sfx.Ding) == 1, "heat after closing: Ding")

	-- MOVE mid-heat: server restart (state cleared -> 0): silent on the old client, no ding, no clunk, no press
	door.Triggered:Fire(player) -- open again first, so the reset also has a door to snap shut
	Run(0.7)
	heat = PromptNamed(mw, "MicrowaveHeatPrompt")
	heat.Triggered:Fire(player)
	Run(1.5)
	mark = #M.played
	sctx:Stop()
	sctx = ServerCtx(mw)
	MwServer.Server(mw, sctx)
	local anyPress = false
	Run(0.3, function()
		if not btnStart.CFrame:FuzzyEq(btnHome, 1e-5) or not btnOpen.CFrame:FuzzyEq(btnOpenHome, 1e-5) then anyPress = true end
	end)
	check(#PlayedSince(mark) == 0, "move reset mid-heat: no sound (no clunk / beep / ding)")
	check(not anyPress, "move reset: no button press")
	check(near(Yaw(frame, frameHome), 0, 1e-3), "move reset: door snapped shut")
	cctx:Stop()
	check(frame.CFrame:FuzzyEq(frameHome, 1e-4), "cleanup: door frame home")
	-- the restarted client: the very first heat must ding (the reviewer's bug)
	cctx = StartClient(mw, MwClient)
	Run(0.4)
	mark = #M.played
	heat = PromptNamed(mw, "MicrowaveHeatPrompt")
	heat.Triggered:Fire(player)
	Run(5.4)
	check(#PlayedSince(mark, Sfx.MicrowaveBeep) == 1 and #PlayedSince(mark, Sfx.Ding) == 1, "restarted client: first heat beeps and dings")

	-- STREAM-IN mid-heat: silent pick-up, and the ding still comes at the end
	heat.Triggered:Fire(player)
	Run(2)
	cctx:Stop()
	mark = #M.played
	cctx = StartClient(mw, MwClient)
	Run(0.2)
	local heard = {}
	for _, p in ipairs(PlayedSince(mark)) do if p.Id ~= Sfx.MicrowaveHum then table.insert(heard, p.Id) end end
	check(#heard == 0, "stream-in mid-heat: only the hum picks up (no beep / press sound): " .. table.concat(heard, ","))
	check(hum ~= nil and #PlayedSince(mark, Sfx.MicrowaveHum) == 1, "stream-in mid-heat: hum resumes")
	Run(3.2)
	check(#PlayedSince(mark, Sfx.Ding) == 1, "stream-in mid-heat: the Ding still plays when it finishes")
	cctx:Stop()
	sctx:Stop()
end

print(failures == 0 and "ALL OK" or (failures .. " FAILURE(S)"))
if failures > 0 then error("kitchen harness failed") end

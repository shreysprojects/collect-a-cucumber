--!nocheck
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
local Players = {}
local game = {}
function game.GetService(_, name)
	if name == "ReplicatedStorage" then return RS end
	if name == "RunService" then return RunService end
	if name == "Players" then return Players end
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
	Vector2 = M.Vector2, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint,
	ColorSequence = M.ColorSequence, Enum = M.Enum, typeof = M.typeof, task = M.task,
	warn = function(...) print("WARN", ...) error("warned: " .. table.concat({...}, " ")) end,
	require = function(ms)
		if ms == kitMS then return load("FunBuildKit") end
		if ms == assetsMS then return load("FunAssets") end
		error("require " .. tostring(ms))
	end,
}
local Kit = load("FunBuildKit")

--==================================================================== the placed machine (x1.25, yawed 90 degrees)
local SCALE = 1.25
local model = new("Model", workspace)
model.Name = "VendingMachine"
local centre = V(0, 3.28, -0.03)
model:SetAttribute("BuildKey", "VendingMachine")
model:SetAttribute("Scale", SCALE)
model:SetAttribute("AuthoredCentre", centre)
for k, v in pairs({CardSlot = V(-0.91, 2.94, -0.90), CashSlot = V(-0.87, 3.47, -0.90), DropPoint = V(0.47, 1.05, -0.36),
	FlapHinge = V(0.47, 1.58, -0.70), KeypadCentre = V(-0.88, 4.40, -0.92)}) do model:SetAttribute("Pivot_" .. k, v) end
model:SetAttribute("State_FlapAjar", -22) model:SetAttribute("State_FlapOpen", -78) model:SetAttribute("State_FlapShut", 0)
local hitbox = new("Part", model)
hitbox.Name = "Hitbox"
hitbox.Size = V(3.2, 6.56, 1.7) * SCALE
hitbox.CFrame = CF.new(100, 3.28 * SCALE, 50) * CF.Angles(0, math.rad(90), 0)
model.PrimaryPart = hitbox
local function part(name, pos, size, color)
	local p = new("MeshPart", model)
	p.Name = name
	p.Size = size * SCALE
	p.CFrame = Kit.CFrameToWorld(model, CF.new(pos))
	p.Color = color or M.Color3.new(1, 0.3, 0.3)
	return p
end
local flap = part("DeliveryFlap", V(0.47, 1.26, -0.58), V(1.14, 0.65, 0.29))
local neon = part("NeonText", V(-0.01, 5.73, -0.84), V(2.49, 1.27, 0.10), M.Color3.fromRGB(255, 77, 77))
local flapRest = flap.CFrame
local neonRest = neon.Color

--==================================================================== a player with an R15-ish character
local function character(name, at, useConstraints)
	local plr = new("Player")
	plr.Name = name
	plr.UserId = #name
	local ch = new("Model", workspace)
	ch.Name = name
	local root = new("Part", ch) root.Name = "HumanoidRootPart" root.Size = V(2, 2, 1) root.CFrame = at
	new("Humanoid", ch)
	local function limb(n, off, size) local p = new("Part", ch) p.Name = n p.Size = size p.CFrame = at * CF.new(off) return p end
	local ut = limb("UpperTorso", V(0, 0.2, 0), V(2, 1.6, 1))
	local head = limb("Head", V(0, 1.7, 0), V(1.2, 1.2, 1.2))
	local rua = limb("RightUpperArm", V(1.5, 0.45, 0), V(1, 1.17, 1))
	local rla = limb("RightLowerArm", V(1.5, -0.33, 0), V(1, 1.05, 1))
	local rh = limb("RightHand", V(1.5, -0.98, 0), V(1, 0.3, 1))
	local function joint(n, p0, p1)
		local j
		if useConstraints then
			j = new("AnimationConstraint", p1)
			local a1 = new("Attachment", p1) a1.Name = n .. "RigAttachment"
			j.Attachment1 = a1
		else
			j = new("Motor6D", p1)
			j.Part0, j.Part1 = p0, p1
		end
		j.Name = n
		j.Transform = CF.identity
		return j
	end
	joint("RightShoulder", ut, rua) joint("RightElbow", rua, rla) joint("RightWrist", rla, rh) joint("Neck", ut, head)
	plr.Character = ch
	return plr, ch
end
local frontOfMachine = Kit.CFrameToWorld(model, CF.new(-0.4, 3.0 / SCALE, -2.6))
local buyer, buyerChar = character("Buyer", frontOfMachine, false)
local other, otherChar = character("Other", frontOfMachine * CF.new(3, 0, 0), true)
Players.LocalPlayer = buyer

--==================================================================== server half
local fired = {}
local sctx = {Model = model, Scale = SCALE, _insts = {}, _conns = {}}
function sctx:Alive() return model.Parent ~= nil end
function sctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
function sctx:Add(i) table.insert(self._insts, i) return i end
function sctx:Fire(action, payload) table.insert(fired, {action, payload}) end
function sctx:HumanoidOf(p) local ch = p.Character local h = ch and ch:FindFirstChildOfClass("Humanoid") local r = ch and ch:FindFirstChild("HumanoidRootPart") if h and r then return h, r end return nil end
function sctx:Prompt(p, opts)
	local parent = p
	if opts.Offset then local a = new("Attachment", p) a.Name = "FunPromptAt" a.Position = opts.Offset parent = a end
	local pr = new("ProximityPrompt", parent)
	pr.Name = opts.Name or "FunPrompt" pr.ActionText = opts.Action pr.HoldDuration = opts.Hold pr.MaxActivationDistance = opts.Distance
	return pr
end
local Server = load("VendServer")
local serverCleanup = Server.Server(model, sctx)
assert(type(serverCleanup) == "function", "server cleanup")
local prompt = hitbox:FindFirstChild("VendPrompt", true)
assert(prompt and prompt.ActionText == "Get a snack" and prompt.HoldDuration == 0.3, "prompt")
local promptAt = prompt.Parent.Position
print("prompt offset (hitbox space)", promptAt, "keypad world", Kit.Pivot(model, "KeypadCentre"), "attachment world", hitbox.CFrame * promptAt)

--==================================================================== client half
local cctx = {Model = model, Scale = SCALE, Key = "VendingMachine", Player = buyer, _insts = {}, _conns = {}, _clean = {}, StepRange = 160}
local stepFn
function cctx:Alive() return model.Parent ~= nil end
function cctx:Connect(sig, fn) local c = sig:Connect(fn) table.insert(self._conns, c) return c end
function cctx:Add(i) table.insert(self._insts, i) return i end
function cctx:OnCleanup(fn) table.insert(self._clean, fn) end
function cctx:Step(fn) stepFn = fn end
function cctx:Sound(parent, id, props)
	local s = new("Sound", parent) s.SoundId = tostring(id)
	for k, v in pairs(props or {}) do s[k] = v end
	return self:Add(s)
end
function cctx:Part(props)
	local p = new("Part")
	for k, v in pairs(props or {}) do p[k] = v end
	if not p.Parent then p.Parent = workspace.CurrentCamera end
	return self:Add(p)
end
local Client = load("VendClient")
local cleanup = Client.Client(model, cctx)
assert(type(cleanup) == "function", "cleanup")
local cInsts0, sInsts0 = #cctx._insts, #sctx._insts
local function camCount(name)
	local n = 0
	for _, p in ipairs(workspace.CurrentCamera:GetChildren()) do if p.Name == name then n += 1 end end
	return n
end

--==================================================================== run a vend
M.clock = 1000
prompt.Triggered:Fire(buyer)
assert(#fired == 1 and fired[1][1] == "Vend", "vend fired")
local payload = fired[1][2]
print("payload", payload.Snack, payload.Seed, payload.T0, payload.Player.Name)
local t0 = payload.T0
Client.OnEvent(model, "Vend", payload, cctx)
assert(prompt.ActionText == "Out of coins, wait a sec", "wait text: " .. tostring(prompt.ActionText))

local function authoredOf(p) return Kit.Origin(model):PointToObjectSpace(p) / SCALE end
local function flapAngle()
	-- angle of the flap about the authored X axis relative to rest (degrees)
	local rel = flapRest:ToObjectSpace(flap.CFrame)
	local look = (flapRest * CF.new(0, 1, 0)).Position - flapRest.Position
	local now = (flap.CFrame * CF.new(0, 1, 0)).Position - flap.CFrame.Position
	local o = Kit.Origin(model)
	local a = o:Inverse() * (o.Position + look)
	local b = o:Inverse() * (o.Position + now)
	return math.deg(math.atan2(b.Z, b.Y) - math.atan2(a.Z, a.Y)), rel
end
local snapshots = {}
local dt = 1 / 60
local lastPrinted = -1
for frame = 0, math.floor(6 / dt) do
	M.clock = t0 + frame * dt
	M.runDue()
	stepFn(dt, M.clock)
	RunService.Stepped:Fire(M.clock, dt)
	local t = M.clock - t0
	-- the second press inside the cooldown is ignored
	if math.abs(t - 2.0) < dt / 2 then prompt.Triggered:Fire(buyer) assert(#fired == 1, "cooldown ignored") end
	if math.abs(t - 4.4) < dt / 2 then
		local sn = buyerChar:FindFirstChild("FunSnack")
		local hidden, total = 0, 0
		for _, d in ipairs(sn:GetDescendants()) do if d:IsA("BasePart") then total += 1 if d.LocalTransparencyModifier == 1 then hidden += 1 end end end
		print("after burp: snack parts hidden locally", hidden, "/", total)
		local em = 0
		for _, d in ipairs(buyerChar:FindFirstChild("Head"):GetDescendants()) do if d.ClassName == "ParticleEmitter" then em += (d.Emitted or 0) end end
		print("bubbles emitted", em)
	end
	local marks = {0.1, 0.4, 0.6, 0.7, 0.8, 0.95, 1.1, 1.25, 1.35, 1.5, 1.7, 1.75, 2.0, 2.2, 2.6, 3.4, 4.35, 5.0, 5.9}
	for _, mk in ipairs(marks) do
		if math.abs(t - mk) < dt / 2 and lastPrinted ~= mk then
			lastPrinted = mk
			local items = {}
			for _, p in ipairs(workspace.CurrentCamera:GetChildren()) do
				if p.Name == "VendSnack" and p.Transparency < 1 then table.insert(items, p) end
			end
			local itemPos = items[1] and tostring(authoredOf(items[1].Position)) or "-"
			local snack = buyerChar:FindFirstChild("FunSnack")
			local wc0 = snack and snack:FindFirstChild("SnackWeld") and snack:FindFirstChild("SnackWeld").C0
			local sh = buyerChar:FindFirstChild("RightUpperArm"):FindFirstChild("RightShoulder").Transform
			local ang = flapAngle()
			local key = nil
			for _, p in ipairs(workspace.CurrentCamera:GetChildren()) do if p.Name == "VendKeyFlash" and p.Transparency < 1 then key = authoredOf(p.Position) end end
			print(string.format("t=%.2f item(authored)=%s visibleParts=%d flap=%.1f snack=%s weldC0=%s shoulderLook=%s key=%s neonR=%.3f",
				t, itemPos, #items, ang, snack and "yes" or "no", wc0 and tostring(wc0.Position) or "-", tostring(sh.LookVector), tostring(key), neon.Color.R))
		end
	end
end
print("sounds played:", table.concat(M.played, ", "))
local snack = buyerChar:FindFirstChild("FunSnack")
print("snack after 6 s:", snack and "STILL THERE" or "destroyed")
print("ctx lists after a whole vend: client", #cctx._insts - cInsts0, "new, server", #sctx._insts - sInsts0, "new")
assert(#cctx._insts == cInsts0 and #sctx._insts == sInsts0, "per-vend instances must not be ctx-registered")
assert(camCount("VendSnack") == 0, "drop copy freed")

--==================================================================== a far camera (the Step sleeps): 60 vends, one every 8 s
local farT = t0 + 30
for n = 1, 60 do
	M.clock = farT + (n - 1) * 8
	Client.OnEvent(model, "Vend", {Player = other, Snack = ({"Soda", "Cola", "Chips"})[n % 3 + 1], Seed = n * 7919, T0 = M.clock}, cctx)
	for frame = 0, math.floor(7.9 / 0.1) do -- Stepped (sippers) keeps running, the Step does not
		M.clock = farT + (n - 1) * 8 + frame * 0.1
		M.runDue()
		RunService.Stepped:Fire(M.clock, 0.1)
	end
end
print("far camera, 60 vends: drop parts alive", camCount("VendSnack"), "ctx list growth", #cctx._insts - cInsts0)
assert(camCount("VendSnack") == 0 and #cctx._insts == cInsts0, "far vends leak")
-- the camera comes back mid-vend: the copy is built on the first awake frame, the next vend frees it
M.clock = farT + 60 * 8
Client.OnEvent(model, "Vend", {Player = other, Snack = "Cola", Seed = 4242, T0 = M.clock}, cctx)
M.clock += 0.6
stepFn(dt, M.clock)
print("camera back at t=0.6: drop parts", camCount("VendSnack"))
assert(camCount("VendSnack") > 0, "built when awake")
M.clock += 20 -- walks away again before it finished; the next vend prunes it
Client.OnEvent(model, "Vend", {Player = other, Snack = "Soda", Seed = 1, T0 = M.clock}, cctx)
print("after the next (far) vend: drop parts", camCount("VendSnack"))
assert(camCount("VendSnack") == 0, "pruned by the next vend")
M.clock += 20
stepFn(dt, M.clock)
stepFn(dt, M.clock + dt)

--==================================================================== an R6 buyer: plain hold, no pose, gulps + burp still play
local r6 = new("Player") r6.Name = "Rsix" r6.UserId = 4
local r6c = new("Model", workspace) r6c.Name = "Rsix"
do
	local at = frontOfMachine * CF.new(-3, 0, 0)
	local root = new("Part", r6c) root.Name = "HumanoidRootPart" root.Size = V(2, 2, 1) root.CFrame = at
	new("Humanoid", r6c)
	local function limb(n, off, size) local p = new("Part", r6c) p.Name = n p.Size = size p.CFrame = at * CF.new(off) return p end
	local torso = limb("Torso", V(0, 0, 0), V(2, 2, 1))
	local head = limb("Head", V(0, 1.5, 0), V(2, 1, 1))
	local arm = limb("Right Arm", V(1.5, 0, 0), V(1, 2, 1))
	local function joint(n, p0, p1) local j = new("Motor6D", torso) j.Name = n j.Part0, j.Part1 = p0, p1 j.Transform = CF.identity return j end
	joint("Right Shoulder", torso, arm) joint("Neck", torso, head)
	r6.Character = r6c
end
local playedBefore = #M.played
M.clock = M.clock + 30
prompt.Triggered:Fire(r6)
local r6pay = fired[#fired][2]
assert(r6pay.Player == r6, "r6 vend")
Client.OnEvent(model, "Vend", r6pay, cctx)
local neckMoved, r6snackSeen = false, false
for frame = 0, math.floor(5.2 / dt) do
	M.clock = r6pay.T0 + frame * dt
	M.runDue()
	stepFn(dt, M.clock)
	RunService.Stepped:Fire(M.clock, dt)
	local neck = r6c:FindFirstChild("Torso"):FindFirstChild("Neck")
	if neck.Transform.LookVector.Z > -0.9999 then neckMoved = true end
	if r6c:FindFirstChild("FunSnack") then r6snackSeen = true end
end
local r6sounds = {}
for i = playedBefore + 1, #M.played do table.insert(r6sounds, M.played[i]) end
print("R6: neck posed", neckMoved, "snack seen", r6snackSeen, "snack after 5.2 s", r6c:FindFirstChild("FunSnack") and "STILL THERE" or "destroyed")
print("R6 sounds:", table.concat(r6sounds, ", "))
assert(not neckMoved and r6snackSeen and not r6c:FindFirstChild("FunSnack"), "R6")

--==================================================================== a second vend by another player (AnimationConstraint joints), then cleanup mid-way
M.clock = M.clock + 30
local nFired = #fired
prompt.Triggered:Fire(other)
assert(#fired == nFired + 1, "other vend")
local opay = fired[#fired][2]
Client.OnEvent(model, "Vend", opay, cctx)
for frame = 0, math.floor(2.6 / dt) do
	M.clock = opay.T0 + frame * dt
	M.runDue()
	stepFn(dt, M.clock)
	RunService.Stepped:Fire(M.clock, dt)
end
local osh = otherChar:FindFirstChild("RightUpperArm"):FindFirstChild("RightShoulder")
print("other shoulder transform look (mid-sip)", osh.Transform.LookVector)
assert(osh.Transform.LookVector.Z > -0.99, "posed mid-sip")
-- the machine's SERVER ctx stops first (sold / moved / broken): its cleanup takes the snack out of the hand
serverCleanup()
print("server cleanup: other's snack", otherChar:FindFirstChild("FunSnack") and "STILL THERE" or "destroyed")
assert(not otherChar:FindFirstChild("FunSnack"), "server cleanup destroys snacks")
M.clock += dt
RunService.Stepped:Fire(M.clock, dt) -- the client's sipper sees its snack gone and hands the joints back
print("other shoulder transform look after the snack vanished", osh.Transform.LookVector)
assert(osh.Transform.LookVector.Z < -0.9999, "joints released when the snack vanishes mid-sip")
print("flap angle before cleanup", (flapAngle()))
cleanup()
for _, c in ipairs(cctx._conns) do c:Disconnect() end
local headSounds = 0
for _, ch in ipairs({buyerChar, otherChar, r6c}) do
	for _, d in ipairs(ch:FindFirstChild("Head"):GetChildren()) do if d.ClassName == "Sound" or d.Name == "VendBurp" then headSounds += 1 end end
end
print("after cleanup flap back at rest:", (flap.CFrame.Position - flapRest.Position).Magnitude < 1e-6, "neon restored:", neon.Color == neonRest or (neon.Color.R == neonRest.R),
	"drop parts:", camCount("VendSnack"), "head sounds/puffs:", headSounds)
assert(camCount("VendSnack") == 0 and headSounds == 0, "cleanup frees owned instances")
print("prompt text after cleanup:", prompt.ActionText)
print("OK harness finished")

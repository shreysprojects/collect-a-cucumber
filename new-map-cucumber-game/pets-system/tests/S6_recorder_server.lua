--[[
	S6_recorder_server.lua  (pets-system/tests, S6 integration agent, 2026-09-22)
	Combat recorder for the S6 playtests. PASTE the whole file into mcp__robloxstudio__eval_server_runtime
	(play VM only: no loadstring / HTTP there). Re-running stops the old recorder and starts a new one.
	Everything lives in _G.S6 of the play VM and dies with the playtest.
	  * ServerStorage.PetEffectsBus.Emit is wrapped (pass-through; PetCombatService reads Deps.Effects.Emit
	    per shot): every "Shot" is logged with its zombie (Owner / Variety / Shaded / Underground / tag /
	    folder) and, from ZombieAPI.TargetInfos at that moment, the priority of the target and the best
	    priority of every same-owner candidate within the pet's Stats.Range (flat XZ from the shot's
	    ground point). The original Emit is kept in _G.S6_ORIG_EMIT.
	  * Humanoid.HealthChanged drops for every zombie (workspace.Zombies), guardian (workspace.Guardians),
	    player character and the S6Dummy, with a Heartbeat frame counter (turret attribution).
	  * DefenceService turret "Tracer" parts (workspace children) = turret shot times.
	  * per-zombie transitions of Carrying / Grappling (TargetInfos) and Shaded / Underground / Dead.
	Helpers for staging: S.Plot(uid), S.Spawn(variety) (ZombieDev spawn: for Players:GetPlayers()[1]),
	S.PlaceAt(model, plot, lx, lz, anchored, hp), S.Dummy(pos), S.Stop().
	GOTCHA (S6, 2026-09-22): Humanoid.Health is a float32. At 1e9 HP a hit under 32 rounds away (ulp 64), so an
	"invulnerable" zombie at 1e9 never shows pet damage in HealthChanged. Use hp = 1e6 (ulp 0.0625). A drop larger
	than 1e5 is ignored (a deferred HealthChanged from before the MaxHealth / Health write carries the old value).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SS = game:GetService("ServerStorage")
local CS = game:GetService("CollectionService")
local Bus = require(SS:WaitForChild("PetEffectsBus"))
local PetService = require(SS:WaitForChild("PetService"))
local old = _G.S6
if old and old.Stop then pcall(old.Stop) end
if not _G.S6_ORIG_EMIT then _G.S6_ORIG_EMIT = Bus.Emit end
local ORIG = _G.S6_ORIG_EMIT
local S = {Shots = {}, HP = {}, Tracers = {}, Trans = {}, Frame = 0, T0 = workspace:GetServerTimeNow(), Conns = {}, Watched = {}, Last = {}, State = {}, Marks = {}}
_G.S6 = S
local function now() return workspace:GetServerTimeNow() - S.T0 end
S.Now = now
local function flat(a, b) local dx, dz = a.X - b.X, a.Z - b.Z return math.sqrt(dx * dx + dz * dz) end
S.Flat = flat
local function conn(c) table.insert(S.Conns, c) return c end
function S.Mark(label) table.insert(S.Marks, {t = now(), l = label}) return now() end

local function Infos()
	local api = SS:FindFirstChild("ZombieAPI")
	local ti = api and api:FindFirstChild("TargetInfos")
	if not ti then return {} end
	local ok, r = pcall(ti.Invoke, ti)
	return ok and type(r) == "table" and r or {}
end
S.Infos = Infos

local function PetById(id)
	local ok, list = pcall(PetService.GetActivePets)
	if not ok or type(list) ~= "table" then return nil end
	for _, p in ipairs(list) do if p.PetId == id then return p end end
	return nil
end

Bus.Emit = function(event, owner, position)
	if type(event) == "table" and event.Kind == "Shot" then
		local ok, err = pcall(function()
			local z = event.Zombie
			local uid = typeof(owner) == "Instance" and owner.UserId or owner
			local pet = PetById(event.PetId)
			local range = pet and type(pet.Stats) == "table" and pet.Stats.Range or nil
			local ground = event.From - Vector3.new(0, 1.5, 0)
			local zombies = workspace:FindFirstChild("Zombies")
			local r = {t = now(), f = S.Frame, id = event.PetId, uid = uid, dmg = event.Damage, rar = event.Rarity, range = range,
				gx = ground.X, gz = ground.Z, z = z, zn = z and z.Name or "nil", var = z and z:GetAttribute("Variety"),
				zo = z and z:GetAttribute("Owner"), sh = z ~= nil and z:GetAttribute("Shaded") == true,
				ug = z ~= nil and z:GetAttribute("Underground") == true, tag = z ~= nil and CS:HasTag(z, "Zombie"),
				inFolder = z ~= nil and zombies ~= nil and z.Parent == zombies}
			local maxP, nIn, nd, nm = 0, 0, math.huge, nil
			for _, info in ipairs(Infos()) do
				if info.Owner == uid and typeof(info.Position) == "Vector3" then
					local d = flat(ground, info.Position)
					local p = info.Carrying and 3 or (info.Grappling and 2 or 1)
					if info.Model == z then r.tp, r.d = p, d end
					if range and d <= range then
						nIn += 1
						if p > maxP then maxP = p end
						if d < nd then nd, nm = d, info.Model end
					end
				end
			end
			r.maxP, r.nIn, r.nearest = maxP, nIn, nm == z
			table.insert(S.Shots, r)
		end)
		if not ok then S.Err = tostring(err) end
	end
	return ORIG(event, owner, position)
end

local function Watch(model, kind)
	if S.Watched[model] then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	S.Watched[model] = kind
	S.Last[model] = hum.Health
	conn(hum.HealthChanged:Connect(function(h)
		local prev = S.Last[model] or h
		S.Last[model] = h
		if h < prev and prev - h < 1e5 then
			table.insert(S.HP, {t = now(), f = S.Frame, m = model, n = model.Name, k = kind, o = model:GetAttribute("Owner"),
				v = model:GetAttribute("Variety"), dmg = prev - h, hp = h})
		end
	end))
end
S.Watch = Watch

local zf = workspace:FindFirstChild("Zombies")
if zf then
	for _, m in ipairs(zf:GetChildren()) do Watch(m, "zombie") end
	conn(zf.ChildAdded:Connect(function(m) task.defer(Watch, m, "zombie") end))
end
local gf = workspace:FindFirstChild("Guardians")
if gf then
	for _, m in ipairs(gf:GetChildren()) do Watch(m, "guardian") end
	conn(gf.ChildAdded:Connect(function(m) task.defer(Watch, m, "guardian") end))
end
conn(workspace.ChildAdded:Connect(function(c)
	if c.Name == "Zombies" and not zf then
		zf = c
		conn(c.ChildAdded:Connect(function(m) task.defer(Watch, m, "zombie") end))
	elseif c.Name == "Tracer" and c:IsA("BasePart") then
		table.insert(S.Tracers, {t = now(), f = S.Frame, pos = c.Position})
	end
end))
local function WatchPlayer(p)
	if p.Character then Watch(p.Character, "player") end
	conn(p.CharacterAdded:Connect(function(c) task.defer(Watch, c, "player") end))
end
for _, p in ipairs(Players:GetPlayers()) do WatchPlayer(p) end
conn(Players.PlayerAdded:Connect(WatchPlayer))

conn(RunService.Heartbeat:Connect(function()
	S.Frame += 1
	local flags = {}
	for _, info in ipairs(Infos()) do
		flags[info.Model] = (info.Carrying and "C" or "") .. (info.Grappling and "G" or "")
	end
	local folder = workspace:FindFirstChild("Zombies")
	if not folder then return end
	for _, m in ipairs(folder:GetChildren()) do
		local st = (flags[m] or "-") .. (m:GetAttribute("Shaded") == true and "S" or "") .. (m:GetAttribute("Underground") == true and "U" or "")
			.. (m:GetAttribute("Dead") == true and "D" or "")
		if S.State[m] ~= st then
			S.State[m] = st
			table.insert(S.Trans, {t = now(), f = S.Frame, m = m, n = m.Name, v = m:GetAttribute("Variety"), o = m:GetAttribute("Owner"), s = st})
		end
	end
end))

--..staging helpers..--
function S.Plot(uid)
	for _, pl in ipairs(workspace.Map.Lobby.Plots:GetChildren()) do
		if pl:GetAttribute("Owner") == uid then return pl end
	end
	return nil
end

function S.Spawn(variety) -- ZombieDev spawn (Players:GetPlayers()[1]'s raid); returns the new zombie model or nil
	local folder = workspace:FindFirstChild("Zombies")
	local before = {}
	if folder then for _, m in ipairs(folder:GetChildren()) do before[m] = true end end
	workspace:SetAttribute("ZombieDev", "spawn:" .. variety)
	local t = os.clock()
	while os.clock() - t < 2 do
		task.wait()
		folder = workspace:FindFirstChild("Zombies")
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if not before[m] and (m:GetAttribute("Variety") == variety or m.Name == variety) then
					Watch(m, "zombie")
					return m
				end
			end
		end
	end
	return nil
end

function S.PlaceAt(model, plot, lx, lz, anchored, hp) -- hp: optional MaxHealth = Health (1e6 = "invulnerable", see GOTCHA)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (hum and root) then return false end
	if hp then
		S.Last[model] = hp
		hum.MaxHealth = hp
		hum.Health = hp
	end
	root.Anchored = anchored == true
	if plot then
		local top = plot.CFrame * CFrame.new(lx, plot.Size.Y * 0.5, lz)
		local pos = top.Position + Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5 + 0.05, 0)
		local offset = model:GetPivot():ToObjectSpace(root.CFrame)
		model:PivotTo((CFrame.new(pos) * root.CFrame.Rotation) * offset:Inverse())
	end
	return true
end

function S.Dummy(pos)
	if S.DummyModel then S.DummyModel:Destroy() end
	local m = Instance.new("Model")
	m.Name = "S6Dummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Anchored = true
	head.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	head.Parent = m
	Instance.new("Humanoid").Parent = m
	m.PrimaryPart = root
	m.Parent = workspace
	Watch(m, "dummy")
	S.DummyModel = m
	return m
end

function S.Stop()
	for _, c in ipairs(S.Conns) do c:Disconnect() end
	S.Conns = {}
	if Bus.Emit ~= ORIG then Bus.Emit = ORIG end
	if S.DummyModel then S.DummyModel:Destroy() S.DummyModel = nil end
end

local Combat = require(SS:WaitForChild("PetCombatService"))
S.Diag0 = Combat.GetDiagnostics()
local active = {}
for _, p in ipairs(PetService.GetActivePets()) do
	table.insert(active, ("%s:%s:%s r%s i%s d%s"):format(tostring(p.UserId), tostring(p.Model and p.Model.Name), tostring(p.PetId):sub(1, 8),
		tostring(p.Stats and p.Stats.Range), tostring(p.Stats and p.Stats.ShotInterval), tostring(p.Stats and p.Stats.ShotDamage)))
end
return ("S6 recorder on (frame 0, T0 %.3f). Combat started %s, diag %s. Active pets %d: %s"):format(S.T0, tostring(Combat.IsStarted()),
	game:GetService("HttpService"):JSONEncode(S.Diag0), #active, table.concat(active, " | "))

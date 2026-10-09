--[[
	S6_recorder_client.lua  (pets-system/tests, S6 integration agent, 2026-09-22)
	Client side of the S6 combat checks. PASTE into mcp__robloxstudio__eval_client_runtime (play VM only).
	Re-running replaces it; _G.S6C dies with the playtest. Records:
	  * Remotes.ZombieRaid messages by Kind (a pet shot must never produce "Hostile");
	  * Remotes.PetEffects "Shot" events (all / own) and the server From per PetId;
	  * every PetEffectsClient shot orb (a PetFx Ball <= 0.5 studs turning visible in Camera.PetFxLocal): its start
	    point vs the nearest RENDERED pet muzzle (PrimaryPart + 1.5) at that moment, that pet's rendered speed, and
	    the distance to the event's server From;
	  * FxShotAt writes on pet models (PetRoamClient's aim / squash input) and local character health drops.
	Summary: return _G.S6C.Summary()
]]
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local old = _G.S6C
if old and old.Stop then pcall(old.Stop) end
local S = {Kinds = {}, Shots = 0, OwnShots = 0, Orbs = {}, Conns = {}, Watched = {}, Prev = {}, Ev = {}, T0 = os.clock(), AimWrites = 0, PlayerHits = 0, PetWatch = {}}
_G.S6C = S
local lp = Players.LocalPlayer
local MUZ = Vector3.new(0, 1.5, 0)
local function conn(c) table.insert(S.Conns, c) return c end
local remotes = RS:WaitForChild("Remotes", 5)
local zr = remotes and remotes:FindFirstChild("ZombieRaid")
if zr then
	conn(zr.OnClientEvent:Connect(function(msg)
		local k = type(msg) == "table" and tostring(msg.Kind) or tostring(msg)
		S.Kinds[k] = (S.Kinds[k] or 0) + 1
	end))
end
local pe = remotes and remotes:FindFirstChild("PetEffects")
if pe then
	conn(pe.OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" or type(batch.Events) ~= "table" then return end
		for _, ev in ipairs(batch.Events) do
			if type(ev) == "table" and ev.Kind == "Shot" then
				S.Shots += 1
				if ev.Owner == lp.UserId then S.OwnShots += 1 end
				S.Ev[ev.PetId] = {t = os.clock(), From = ev.From}
			end
		end
	end))
end

local function WatchPet(m)
	if S.PetWatch[m] then return end
	S.PetWatch[m] = true
	conn(m:GetAttributeChangedSignal("FxShotAt"):Connect(function() S.AimWrites += 1 end))
end
for _, m in ipairs(CS:GetTagged("PlotPet")) do WatchPet(m) end
conn(CS:GetInstanceAddedSignal("PlotPet"):Connect(WatchPet))

conn(RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, m in ipairs(CS:GetTagged("PlotPet")) do
		local pp = m.PrimaryPart
		if pp then
			local p = S.Prev[m]
			S.Prev[m] = {pos = pp.Position, t = t, last = p and p.pos, lastT = p and p.t}
		end
	end
end))

local function OrbStart(part)
	local pos = part.Position
	if pos.Y < -4000 then return end
	local bestD, bestM = math.huge, nil
	for _, m in ipairs(CS:GetTagged("PlotPet")) do
		local pp = m.PrimaryPart
		if pp then
			local d = (pp.Position + MUZ - pos).Magnitude
			if d < bestD then bestD, bestM = d, m end
		end
	end
	local rec = {t = os.clock() - S.T0, d = bestD}
	if bestM then
		local id = bestM:GetAttribute("PetId")
		rec.id = id
		local pv = S.Prev[bestM]
		if pv and pv.last and pv.lastT and pv.t > pv.lastT then rec.speed = (pv.pos - pv.last).Magnitude / (pv.t - pv.lastT) end
		local ev = id and S.Ev[id]
		if ev and typeof(ev.From) == "Vector3" and os.clock() - ev.t < 0.5 then rec.dFrom = (ev.From - pos).Magnitude end
	end
	table.insert(S.Orbs, rec)
end

local function Watch(part)
	if S.Watched[part] or not part:IsA("BasePart") or part.Name ~= "PetFx" then return end
	S.Watched[part] = true
	conn(part:GetPropertyChangedSignal("Transparency"):Connect(function()
		if part.Transparency == 0 and part.Shape == Enum.PartType.Ball and part.Size.X <= 0.5 then
			if part.Position.Y < -4000 then task.defer(OrbStart, part) else OrbStart(part) end
		end
	end))
end
local function HookFolder(folder)
	for _, c in ipairs(folder:GetChildren()) do Watch(c) end
	conn(folder.ChildAdded:Connect(Watch))
end
local cam = workspace.CurrentCamera
local folder = cam and cam:FindFirstChild("PetFxLocal")
if folder then HookFolder(folder) elseif cam then
	conn(cam.ChildAdded:Connect(function(c) if c.Name == "PetFxLocal" then HookFolder(c) end end))
end

local function WatchChar(c)
	local hum = c:WaitForChild("Humanoid", 5)
	if not hum then return end
	local last = hum.Health
	conn(hum.HealthChanged:Connect(function(h) if h < last then S.PlayerHits += 1 end last = h end))
end
if lp.Character then task.spawn(WatchChar, lp.Character) end
conn(lp.CharacterAdded:Connect(WatchChar))

function S.Stop()
	for _, c in ipairs(S.Conns) do c:Disconnect() end
	S.Conns = {}
end

function S.Summary()
	local ds, sp, df = {}, {}, {}
	local moving = 0
	for _, o in ipairs(S.Orbs) do
		table.insert(ds, o.d)
		if o.speed then table.insert(sp, o.speed) if o.speed > 0.5 then moving += 1 end end
		if o.dFrom then table.insert(df, o.dFrom) end
	end
	local function q(t, p) if #t == 0 then return "n/a" end table.sort(t) return ("%.3f"):format(t[math.max(1, math.ceil(#t * p))]) end
	local kinds = {}
	for k, v in pairs(S.Kinds) do table.insert(kinds, k .. "=" .. v) end
	table.sort(kinds)
	return ("client %s (uid %d): PetEffects shots %d (own %d); orbs %d: start->rendered muzzle median %s p90 %s max %s; pet moving (>0.5 st/s) at %d of %d, speed median %s; start->server From median %s max %s; FxShotAt writes %d; ZombieRaid kinds {%s}; local player health drops %d")
		:format(lp.Name, lp.UserId, S.Shots, S.OwnShots, #S.Orbs, q(ds, 0.5), q(ds, 0.9), q(ds, 1), moving, #sp, q(sp, 0.5), q(df, 0.5), q(df, 1), S.AimWrites,
			table.concat(kinds, ", "), S.PlayerHits)
end
return "S6C client recorder on for " .. lp.Name .. " (" .. lp.UserId .. "), PetFxLocal " .. tostring(folder ~= nil)

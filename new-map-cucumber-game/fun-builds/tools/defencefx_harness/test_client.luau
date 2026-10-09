--!nocheck
-- Offline run of DefenceFXClient (fun-builds package DefenceFX): mocks from ./mocks, the script wrapped by gen.py.
--   py gen.py; luau test_client.luau
local M = require("./mocks")
local V, CF, new = M.Vector3.new, M.CFrame, M.new

local fails, passes = 0, 0
local function check(cond, msg)
	if cond then passes += 1 else fails += 1 print("FAIL " .. msg) end
end
local warns = {}

--==================================================================== world + services
local workspace = new("Workspace")
workspace.Name = "Workspace"
workspace.Gravity = 196.2
local terrain = new("Terrain", workspace)
terrain.Name = "Terrain"
workspace.Terrain = terrain
local camera = new("Camera", workspace)
camera.CFrame = CF.lookAt(V(0, 20, 60), V(0, 0, 0))
workspace.CurrentCamera = camera
function workspace.GetServerTimeNow() return M.clock end
function workspace.Raycast(_, origin, dir, _params)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 then return {Position = V(origin.X, 0, origin.Z)} end
	return nil
end
local RS = new("Folder") RS.Name = "ReplicatedStorage"
local Modules = new("Folder", RS) Modules.Name = "Modules"
local kitMS = new("ModuleScript", Modules) kitMS.Name = "FunBuildKit"
local Remotes = new("Folder", RS) Remotes.Name = "Remotes"
local remote = new("RemoteEvent", Remotes) remote.Name = "DefenceFX"
local PB = new("Folder", RS) PB.Name = "PlaceableBuilds"
local PBD = new("Folder", PB) PBD.Name = "Defences"

local RunService = {Heartbeat = M.Signal(), RenderStepped = M.Signal(), Stepped = M.Signal()}
function RunService.IsServer() return false end
local plr = new("Player") plr.Name = "Tester" plr.UserId = 1
local Players = {LocalPlayer = plr}
function Players.GetPlayers() return {plr} end
local tags = {}
local CS = {added = {}, removed = {}}
function CS.GetTagged(_, tag) local out = {} for i in pairs(tags[tag] or {}) do table.insert(out, i) end return out end
function CS.GetInstanceAddedSignal(_, tag) CS.added[tag] = CS.added[tag] or M.Signal() return CS.added[tag] end
function CS.GetInstanceRemovedSignal(_, tag) CS.removed[tag] = CS.removed[tag] or M.Signal() return CS.removed[tag] end
local function addTag(inst, tag) tags[tag] = tags[tag] or {} tags[tag][inst] = true if CS.added[tag] then CS.added[tag]:Fire(inst) end end
local function removeTag(inst, tag) if tags[tag] then tags[tag][inst] = nil end if CS.removed[tag] then CS.removed[tag]:Fire(inst) end end
local TweenService = {}
function TweenService.Create(_, inst, _info, goals) return {Play = function() for k, v in pairs(goals) do inst[k] = v end end} end
local Debris = {}
function Debris.AddItem(_, inst, t) M.task.delay(t, function() inst:Destroy() end) end
local game = {}
function game.GetService(_, name)
	local s = ({ReplicatedStorage = RS, RunService = RunService, Players = Players, CollectionService = CS, TweenService = TweenService, Debris = Debris, Workspace = workspace})[name]
	return s or error("service " .. name)
end

local script = new("LocalScript") script.Name = "DefenceFXClient"
local loaded = {}
local env
env = {
	game = game, workspace = workspace, Instance = M.Instance, Vector3 = M.Vector3, CFrame = M.CFrame, Color3 = M.Color3,
	Vector2 = M.Vector2, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint,
	ColorSequence = M.ColorSequence, Enum = M.Enum, typeof = M.typeof, task = M.task, print = function() end,
	warn = function(...) local s = table.concat({...}, " ") table.insert(warns, s) print("WARN " .. s) end,
	os = {clock = function() return M.clock end}, script = script, TweenInfo = M.TweenInfo,
	RaycastParams = {new = function() return {} end},
	require = function(ms)
		if ms == kitMS then
			loaded.kit = loaded.kit or require("./mod_kit")(env)
			return loaded.kit
		end
		error("require " .. tostring(ms))
	end,
}
local Kit = env.require(kitMS)

local DT = 1 / 60
local function step(seconds)
	local n = math.max(1, math.floor(seconds / DT + 0.5))
	for _ = 1, n do
		M.clock += DT
		M.runDue()
		M.frame += 1 -- = the client's Frame (both count Heartbeats)
		RunService.Heartbeat:Fire(DT)
	end
end

--==================================================================== a FreezeTower template + placed build
local AUTH = V(0, 6.4, 0)
local GLOWS = {"GlowRune01", "GlowRune02", "GlowGem1", "GlowStrip1Low", "GlowCradle"}
local template = new("Model", PBD) template.Name = "FreezeTower"
for _, n in ipairs(GLOWS) do local p = new("Part", template) p.Name = n p.Transparency = 0 end
local function placeTower(at)
	local model = new("Model")
	model.Name = "FreezeTower"
	model:SetAttribute("BuildKey", "FreezeTower")
	model:SetAttribute("Category", "Defences")
	model:SetAttribute("Scale", 1)
	model:SetAttribute("AuthoredCentre", AUTH)
	for i, v in ipairs({V(2.63, 0.62, -2.63), V(-2.63, 0.62, -2.63), V(-2.63, 0.62, 2.63), V(2.63, 0.62, 2.63)}) do model:SetAttribute("Pivot_Mist" .. i, v) end
	local hitbox = new("Part", model) hitbox.Name = "Hitbox" hitbox.Size = V(7.8, 12.8, 7.8) hitbox.Transparency = 1
	hitbox.CFrame = CF.new(at + AUTH)
	model.PrimaryPart = hitbox
	local parts = {}
	for i, n in ipairs(GLOWS) do
		local p = new("Part", model) p.Name = n p.CFrame = CF.new(at + V(0, i, 0))
		parts[n] = p
	end
	local orb = new("Part", model) orb.Name = "Orb"
	model.Parent = workspace
	addTag(model, "PlacedBuild")
	return model, hitbox, parts
end

local zombies = new("Folder", workspace) zombies.Name = "Zombies"
local function zombie(name, at, scale)
	scale = scale or 1
	local z = new("Model", zombies)
	z.Name = name
	local root = new("Part", z) root.Name = "HumanoidRootPart" root.Size = V(2, 2, 1) * scale root.CFrame = CF.new(at)
	z.PrimaryPart = root
	local function limb(n, off, size) local p = new("Part", z) p.Name = n p.Size = size * scale p.CFrame = CF.new(at + off * scale) return p end
	limb("UpperTorso", V(0, 0.2, 0), V(2, 1.6, 1))
	limb("Head", V(0, 1.7, 0), V(1.2, 1.2, 1.2))
	limb("LeftUpperArm", V(-1.5, 0.45, 0), V(1, 1.17, 1))
	limb("RightUpperArm", V(1.5, 0.45, 0), V(1, 1.17, 1))
	limb("LeftUpperLeg", V(-0.5, -1.5, 0), V(1, 1.5, 1))
	new("Humanoid", z)
	z:SetAttribute("Zombie", true)
	return z
end

--==================================================================== load the client
local tower, hitbox, glowParts = placeTower(V(0, 0, 0)) -- placed BEFORE the script runs (GetTagged path)
require("./mod_client")(env)
step(0.1)

local function count(name) local n = 0 for _, c in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do if not name or c.Name == name then n += 1 end end return n end
local function pointsOf(styleName)
	local out = {}
	for _, a in ipairs(terrain:GetChildren()) do if a.Name == "DefenceFX_" .. styleName then table.insert(out, a) end end
	return out
end
local function emittedBy(styleName) -- summed over every emission point of the style
	local n = 0
	for _, att in ipairs(pointsOf(styleName)) do
		for _, pe in ipairs(att:GetChildren()) do n += (M.emitted[pe] or 0) end
	end
	return n
end
--.. the emissions of a style in the current frame: {att = {pos, n}} (distinct points = distinct bursts on screen)
local function emitsThisFrame(styleName)
	local out, points = {}, 0
	for _, e in ipairs(M.emitLog) do
		if e.frame == M.frame and e.att and e.att.Name == "DefenceFX_" .. styleName then
			if not out[e.att] then out[e.att] = {pos = e.pos, n = 0} points += 1 end
			out[e.att].n += e.n
		end
	end
	return out, points
end
local function resetEmits() table.clear(M.emitted) end
local function highlightOf(z) return z:FindFirstChild("DefenceFXTint") end
local function stat(name) step(0.5) return script:GetAttribute(name) end

--==================================================================== 1. idle: glow pulse + mist on the tower
step(1.0)
check(script:GetAttribute("IdleBuilds") == 1, "idle build registered (" .. tostring(script:GetAttribute("IdleBuilds")) .. ")")
local seen = {}
for _ = 1, 60 do
	step(0.05)
	for n, p in pairs(glowParts) do
		seen[n] = seen[n] or {lo = 1, hi = 0}
		seen[n].lo = math.min(seen[n].lo, p.Transparency)
		seen[n].hi = math.max(seen[n].hi, p.Transparency)
	end
end
for n, s in pairs(seen) do
	check(s.lo >= -1e-6 and s.hi <= 0.35 + 1e-6 and s.hi - s.lo > 0.2, ("glow %s pulses in 0..0.35 (%.3f..%.3f)"):format(n, s.lo, s.hi))
end
local mists = 0
for _, a in ipairs(terrain:GetChildren()) do
	if a.Name == "DefenceFX_Mist" then
		mists += 1
		local pe = a:FindFirstChildOfClass("ParticleEmitter")
		check(pe and pe.Enabled == true and pe.Rate > 0, "mist emitter on while the camera is near")
		local look = a.WorldCFrame.LookVector
		local out = V(a.WorldCFrame.p.X, 0, a.WorldCFrame.p.Z).Unit
		check(look:Dot(out) > 0.99, "mist faces outward from the tower")
	end
end
check(mists == 4, "4 mist attachments (" .. mists .. ")")

--==================================================================== 2. broken: the server's fade is never overwritten, mend resumes
for _, p in pairs(glowParts) do p.Transparency = 0.65 end -- BuildHealthService.Break writes first ...
tower:SetAttribute("Broken", true)                           -- ... then the attribute
step(1.0)
local okBroken = true
for _, p in pairs(glowParts) do if math.abs(p.Transparency - 0.65) > 1e-6 then okBroken = false end end
check(okBroken, "broken fade (0.65) left alone")
local mistLeft = 0
for _, a in ipairs(terrain:GetChildren()) do if a.Name == "DefenceFX_Mist" then mistLeft += 1 end end
check(mistLeft == 0, "mist removed while broken")
check(stat("IdleBuilds") == 0, "no idle record while broken")
for _, p in pairs(glowParts) do p.Transparency = 0 end -- Mend restores ...
tower:SetAttribute("Broken", nil)                         -- ... then clears the attribute
step(1.0)
local moved = false
for _ = 1, 20 do step(0.05) for _, p in pairs(glowParts) do if p.Transparency > 0.02 then moved = true end end end
check(moved, "glow pulses again after the mend")
check(stat("IdleBuilds") == 1, "idle record back after the mend")

--==================================================================== 3. moved: mist follows the hitbox
local shift = V(40, 0, 0)
hitbox.CFrame = hitbox.CFrame + shift
for _, p in pairs(glowParts) do p.CFrame = p.CFrame + shift end
step(0.6)
local near = 0
for _, a in ipairs(terrain:GetChildren()) do
	if a.Name == "DefenceFX_Mist" and math.abs(a.WorldCFrame.p.X - 40) < 3 then near += 1 end
end
check(near == 4, "mist re-made at the new spot (" .. near .. ")")

--==================================================================== 4. frost hits: burst, shards, tint, crystals; fade after the last
local z1 = zombie("Z1", V(40, 3, 10))
local z2 = zombie("Z2", V(44, 3, 10), 1.4)
local z3 = zombie("Z3", V(36, 3, 12))
resetEmits()
local function frost(list, extra)
	local batch = {}
	for _, z in ipairs(list) do table.insert(batch, {k = "Frost", z = z, p = z.HumanoidRootPart.Position, x = extra or {slow = true}}) end
	remote.OnClientEvent:Fire(batch)
end
frost({z1, z2, z3})
do -- the reviewer's collapse: Emit() takes the position at render time, so each hit of a batch needs its own point
	local pts, npts = emitsThisFrame("Frost")
	local okPts = npts == 3
	for _, z in ipairs({z1, z2, z3}) do
		local found = false
		for _, e in pairs(pts) do if (e.pos - z.UpperTorso.Position).Magnitude < 1e-6 and e.n == 16 then found = true end end
		if not found then okPts = false end
	end
	check(okPts, "a batch of 3 frost hits = 3 emission points, each on its own zombie's torso with all 16 particles (" .. npts .. " points)")
end
step(DT)
check(emittedBy("Frost") >= 3 * 16, "frost burst emitted for 3 zombies (" .. emittedBy("Frost") .. ")")
check(count("DefenceFXDebris") == 6, "2 ice shards per hit (" .. count("DefenceFXDebris") .. ")")
check(count("FrostCrystal") == 15, "5 crystals per slowed zombie (" .. count("FrostCrystal") .. ")")
local h1 = highlightOf(z1)
check(h1 ~= nil and math.abs(h1.FillTransparency - 0.6) < 1e-6 and h1.FillColor.B > 0.99, "frost highlight at 0.6")
local c1 = workspace:FindFirstChild("DefenceFXLocal"):FindFirstChild("FrostCrystal")
local weld = c1 and c1:FindFirstChildOfClass("WeldConstraint")
check(weld ~= nil and weld.Part0 ~= nil and weld.Part0:IsDescendantOf(zombies) and c1.Anchored == false, "crystal welded to a zombie body part")
-- the hits continue every 0.5 s for 2 s: the tint holds
for _ = 1, 4 do step(0.5) frost({z1, z2, z3}) end
step(0.6)
h1 = highlightOf(z1)
check(h1 ~= nil and math.abs(h1.FillTransparency - 0.6) < 1e-6, "frost tint held 0.6 s after the last hit")
check(count("FrostCrystal") >= 15, "crystals still on while slowed")
step(0.35)                                             -- 0.95 s after the last hit: fading
h1 = highlightOf(z1)
check(h1 ~= nil and h1.FillTransparency > 0.6 and h1.FillTransparency < 1, "frost tint fading after 0.8 s")
step(0.2)                                              -- 1.15 s: crystals shed (fall + fade)
local anchoredShed = true
for _, c in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
	if c.Name == "FrostCrystal" and c.Anchored ~= true then anchoredShed = false end
end
check(anchoredShed, "crystals unwelded + falling after the slow ends")
step(0.3)                                              -- 1.45 s: tint gone
check(highlightOf(z1) == nil and highlightOf(z2) == nil, "frost highlight removed after the fade")
check(stat("Highlights") == 0, "highlight count back to 0 (" .. tostring(script:GetAttribute("Highlights")) .. ")")
step(2.0)
check(count() == 0, "every effect part gone after the frost ends (" .. count() .. ")")
check(stat("Tinted") == 0, "no zombie state left")

--==================================================================== 5. freeze pulse: ice block for the stun, then it shatters
resetEmits()
frost({z1}, {slow = true, pulse = true, stun = 1.5})
step(DT)
check(emittedBy("IceBurst") > 0, "pulse ice burst")
check(count("IceBlock") == 1 and count("IceSpike") == 2, "ice block + 2 spikes (" .. count("IceBlock") .. "/" .. count("IceSpike") .. ")")
check(count("FrostCrystal") == 0, "no crystals grown inside the ice block (" .. count("FrostCrystal") .. ")")
frost({z1}) -- a chill tick while frozen: still none
step(DT)
check(count("FrostCrystal") == 0, "a chill tick on a frozen zombie grows no crystals")
local block = workspace:FindFirstChild("DefenceFXLocal"):FindFirstChild("IceBlock")
local bw = block and block:FindFirstChildOfClass("WeldConstraint")
check(bw and bw.Part0 == z1.HumanoidRootPart, "ice block welded to the root")
local _, zsize = z1:GetBoundingBox()
check(block and block.Size.Y >= zsize.Y + 0.4 and block.Size.X >= zsize.X + 0.7, "ice block covers the zombie (" .. tostring(block and block.Size) .. " vs " .. tostring(zsize) .. ")")
step(1.3)
check(count("IceBlock") == 1, "block holds through the stun")
resetEmits()
step(0.4)
check(count("IceBlock") == 0 and emittedBy("IceBurst") > 0, "block shattered at the end of the stun")
check(count("DefenceFXDebris") >= 6, "shatter shards fly (" .. count("DefenceFXDebris") .. ")")
step(3)

--==================================================================== 6. tesla white flash 0.15 s; laser red flicker while inside
resetEmits()
remote.OnClientEvent:Fire({{k = "Tesla", z = z2, p = z2.HumanoidRootPart.Position, x = {hop = 0}}})
step(DT * 2)
local h2 = highlightOf(z2)
check(emittedBy("Tesla") >= 13 and h2 ~= nil and h2.FillColor.R > 0.99 and h2.FillColor.B > 0.99, "tesla sparks + white flash")
step(0.2)
check(highlightOf(z2) == nil, "tesla flash over after 0.15 s")
--.. the real laser gap: the server's 0.25 s throttle on a 0.1 s tick in a 0.05 s loop = ~0.3 s, + network jitter
--.. (here 0.4 s): one Highlight the whole time (LASER_HOLD 0.5), never dropped and re-made between hits
local laserH, laserSame = nil, true
for i = 1, 6 do
	remote.OnClientEvent:Fire({{k = "Laser", z = z3, p = z3.HumanoidRootPart.Position}})
	for _ = 1, 24 do -- 0.4 s, checked every frame
		step(DT)
		local h3 = highlightOf(z3)
		if i == 1 and not laserH then laserH = h3 end
		if h3 ~= laserH then laserSame = false end
	end
	local h3 = highlightOf(z3)
	check(h3 ~= nil and h3.FillColor.R > 0.99 and h3.FillColor.G < 0.3, "laser red tint while inside")
end
check(laserH ~= nil and laserSame, "one laser Highlight for the whole stay (hits 0.4 s apart, hold 0.5 s)")
step(0.2)
check(highlightOf(z3) == nil, "laser tint gone after it leaves")
check(emittedBy("Laser") > 0, "laser embers emitted")

--==================================================================== 7. mortar: one ring per burst, flash per zombie; catapult / spikes / turret / minigun
resetEmits()
local c = V(40, 0.5, 11)
remote.OnClientEvent:Fire({
	{k = "Mortar", z = z1, p = z1.HumanoidRootPart.Position, x = {c = c}},
	{k = "Mortar", z = z2, p = z2.HumanoidRootPart.Position, x = {c = c}},
	{k = "Mortar", z = z3, p = z3.HumanoidRootPart.Position, x = {c = c}},
})
do
	local _, mpts = emitsThisFrame("MortarHit")
	check(mpts == 3, "3 mortar hits in one batch = 3 emission points (" .. mpts .. ")")
end
step(DT)
check(emittedBy("MortarRing") == 2, "one shockwave ring (+ dust ring) for the burst (" .. emittedBy("MortarRing") .. ")")
check(emittedBy("MortarHit") == 33, "sparks + glow on each of 3 zombies (" .. emittedBy("MortarHit") .. ")")
check(count("DefenceFXDebris") == 5, "5 debris chunks (" .. count("DefenceFXDebris") .. ")")
local ho = highlightOf(z3)
check(ho ~= nil and ho.FillColor.R > 0.99 and ho.FillColor.B < 0.3, "orange flash on a hit zombie")
local ring = terrain:FindFirstChild("DefenceFX_MortarRing")
check(ring and math.abs(ring.WorldCFrame.p.Y - 0.15) < 1e-6, "ring on the ground under the burst")
step(3)
resetEmits()
remote.OnClientEvent:Fire({
	{k = "Catapult", z = z1, p = z1.HumanoidRootPart.Position, x = {c = c}},
	{k = "Spikes", z = z2, p = V(44, 0.45, 10)},
	{k = "Turret", z = z3, p = z3.HumanoidRootPart.Position, x = {from = V(40, 5, 40)}},
	{k = "Minigun", z = z3, p = z3.HumanoidRootPart.Position, x = {from = V(40, 5, 40)}},
})
step(DT)
check(emittedBy("Catapult") == 12 and count("DefenceFXDebris") == 3, "catapult dust + 3 rock chips")
local sp = terrain:FindFirstChild("DefenceFX_Spikes")
check(emittedBy("Spikes") == 7 and sp and math.abs(sp.WorldCFrame.p.Y - 0.75) < 1e-6, "spike sparks at the plate")
local tur = terrain:FindFirstChild("DefenceFX_Turret")
check(emittedBy("Turret") == 10 and tur.WorldCFrame.LookVector.Z > 0.5, "turret sparks face the gun")
check(emittedBy("Minigun") == 5, "minigun sparks + dust")
step(3)

--==================================================================== 8. zombie missing on this client / far away / dead
resetEmits()
remote.OnClientEvent:Fire({{k = "Frost", z = nil, p = V(40, 3, 30), x = {slow = true}}})
step(DT)
check(emittedBy("Frost") > 0 and #warns == 0, "no zombie: burst at p, no error")
resetEmits()
remote.OnClientEvent:Fire({{k = "Frost", z = nil, p = V(600, 3, 0), x = {slow = true}}})
step(DT)
check(emittedBy("Frost") == 0, "farther than 250 studs: nothing")
step(3)

--==================================================================== 8b. shadow zombies phasing out (Shaded) lose every trace at once
frost({z1, z2})
step(DT)
check(highlightOf(z1) ~= nil and count("FrostCrystal") > 0, "z1 chilled: tint + crystals")
frost({z2}, {slow = true, pulse = true, stun = 1.5})
step(DT)
check(count("IceBlock") == 1, "z2 frozen in a block")
z1:SetAttribute("Shaded", true)
z2:SetAttribute("Shaded", true)
step(DT)
check(highlightOf(z1) == nil and highlightOf(z2) == nil, "shaded: tint dropped the same frame")
check(count("IceBlock") == 0, "shaded: the ice block shatters at once")
local welded = 0
for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
	if p.Name == "FrostCrystal" and p:FindFirstChildOfClass("WeldConstraint") then welded += 1 end
end
check(welded == 0, "shaded: no crystal left on it (" .. welded .. " welded)")
check(stat("Tinted") == 0, "shaded: state dropped")
resetEmits()
frost({z1}) -- a late event for a shaded zombie: particles, but no tint / crystals / state
step(DT)
check(emittedBy("Frost") > 0 and highlightOf(z1) == nil, "event on a shaded zombie: particles only")
check(stat("Tinted") == 0, "event on a shaded zombie: no state")
z1:SetAttribute("Shaded", nil)
z2:SetAttribute("Shaded", nil)
step(3)

--==================================================================== 8c. the reviewer's budget case: 12 slowed zombies near the camera, then a pulse
local dozen = {}
for i = 1, 12 do table.insert(dozen, zombie("D" .. i, V(20 + (i % 4) * 5, 3, 10 + math.floor((i - 1) / 4) * 5))) end
local maxCrystals, maxLive, shardsOk = 0, 0, true
for tick = 1, 6 do
	local before = {}
	for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do before[p] = true end
	frost(dozen)
	local shardsNow = 0
	for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
		if p.Name == "DefenceFXDebris" and not before[p] then shardsNow += 1 end
	end
	if shardsNow < 2 * #dozen then shardsOk = false print(("  tick %d: %d new shards"):format(tick, shardsNow)) end
	for _ = 1, 30 do
		step(DT)
		maxCrystals = math.max(maxCrystals, count("FrostCrystal"))
		maxLive = math.max(maxLive, count())
	end
	if tick == 6 then
		check(stat("Crystals") <= 20, "crystal stat within the cap (" .. tostring(script:GetAttribute("Crystals")) .. ")")
	end
end
check(maxCrystals <= 20 and maxCrystals >= 12, "crystals on 12 slowed zombies stay within their cap of 20 (max " .. maxCrystals .. ")")
check(maxLive <= 60, "live parts <= 60 (max " .. maxLive .. ")")
check(shardsOk, "frost shards still fly on every tick while the crystals are on")
local holders = 0
for _, z in ipairs(dozen) do
	for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
		local w = p.Name == "FrostCrystal" and p:FindFirstChildOfClass("WeldConstraint")
		if w and w.Part0 and w.Part0:IsDescendantOf(z) then holders += 1 break end
	end
end
check(holders >= 4, "at least 4 zombies carry crystals (" .. holders .. ")")
do -- the nearest zombies hold them: no crystal-less zombie is nearer the camera than the farthest holder
	local camPos = camera.CFrame.p
	local farHolder, nearBare = 0, math.huge
	for _, z in ipairs(dozen) do
		local has = false
		for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
			local w = p.Name == "FrostCrystal" and p:FindFirstChildOfClass("WeldConstraint")
			if w and w.Part0 and w.Part0:IsDescendantOf(z) then has = true break end
		end
		local d = (z.UpperTorso.Position - camPos).Magnitude
		if has then farHolder = math.max(farHolder, d) else nearBare = math.min(nearBare, d) end
	end
	check(farHolder <= nearBare + 1e-6, ("crystals go to the nearest zombies (farthest holder %.1f, nearest bare %.1f)"):format(farHolder, nearBare))
end
frost(dozen, {slow = true, pulse = true, stun = 1.5})
check(count("IceBlock") == 12, "a pulse on 12 slowed zombies: 12 ice blocks (" .. count("IceBlock") .. ")")
check(count() <= 60, "still <= 60 parts (" .. count() .. ")")
step(DT)
check(count("FrostCrystal") == 0 or (function()
	for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do
		if p.Name == "FrostCrystal" and p:FindFirstChildOfClass("WeldConstraint") then return false end
	end
	return true
end)(), "no crystals left welded on zombies inside blocks")
step(2.0)
check(count("IceBlock") == 0, "all 12 blocks shattered after the stun")
do -- 12 shatters in one frame: 12 separate IceBurst points, none moved twice before a render
	local shatterFrames = {}
	for _, e in ipairs(M.emitLog) do
		if e.att and e.att.Name == "DefenceFX_IceBurst" then
			shatterFrames[e.frame] = shatterFrames[e.frame] or {}
			shatterFrames[e.frame][e.att] = true
		end
	end
	local most = 0
	for _, atts in pairs(shatterFrames) do
		local n = 0
		for _ in pairs(atts) do n += 1 end
		most = math.max(most, n)
	end
	check(most >= 12, "12 blocks shattering in one frame use 12 IceBurst points (" .. most .. ")")
end
for _, z in ipairs(dozen) do z:Destroy() end
step(4)
check(count() == 0, "dozen: every part gone (" .. count() .. ")")

--==================================================================== 8d. one huge batch: at most SLOT_MAX points per style, skipped past that
local crowd = {}
for i = 1, 30 do table.insert(crowd, zombie("K" .. i, V(-40 + (i % 6) * 4, 3, 10 + math.floor(i / 6) * 4))) end
local skipped0 = script:GetAttribute("BurstsSkipped") or 0
local tb = {}
for _, z in ipairs(crowd) do table.insert(tb, {k = "Tesla", z = z, p = z.HumanoidRootPart.Position, x = {hop = 0}}) end
remote.OnClientEvent:Fire(tb)
do
	local pts, npts = emitsThisFrame("Tesla")
	local okFull = true
	for _, e in pairs(pts) do if e.n ~= 13 then okFull = false end end
	check(npts == 24 and okFull, "30 tesla hits in one frame: 24 points, full count each (" .. npts .. ")")
end
check(stat("BurstsSkipped") - skipped0 == 6, "the other 6 skipped (" .. tostring(script:GetAttribute("BurstsSkipped")) .. ")")
remote.OnClientEvent:Fire(tb) -- the next batch 2 frames on (the stat step above ran 0.5 s): the points are free again
do
	local _, npts = emitsThisFrame("Tesla")
	check(npts == 24, "points reused once a frame rendered (" .. npts .. ")")
end
check(#pointsOf("Tesla") == 24, "the tesla pool never grows past 24 (" .. #pointsOf("Tesla") .. ")")
step(DT)
remote.OnClientEvent:Fire({tb[1]}) -- 1 frame later: every point is still busy (used last frame) -> skipped, never moved
do
	local _, npts = emitsThisFrame("Tesla")
	check(npts == 0, "a point used last frame is not moved again (" .. npts .. ")")
end
for _, z in ipairs(crowd) do z:Destroy() end
step(3)

--==================================================================== 9. budget: 30 zombies frozen at once never pass 60 parts / 12 highlights
local horde = {}
for i = 1, 30 do table.insert(horde, zombie("H" .. i, V(30 + (i % 6) * 4, 3, 20 + math.floor(i / 6) * 4))) end
for _ = 1, 6 do
	frost({table.unpack(horde, 1, 15)}, {slow = true, pulse = true, stun = 1.5})
	frost({table.unpack(horde, 16, 30)})
	step(0.25)
	local live = 0
	for _, p in ipairs(workspace:FindFirstChild("DefenceFXLocal"):GetChildren()) do live += 1 end
	check(live <= 60, "live parts <= 60 (" .. live .. ")")
	local hl = 0
	for _, z in ipairs(horde) do if highlightOf(z) then hl += 1 end end
	check(hl <= 12, "highlights <= 12 (" .. hl .. ")")
	step(0.25)
end
--.. a zombie dies frozen: its ice shatters, crystals drop, state goes
local victim = horde[1]
victim.Humanoid.Health = 0
step(0.1)
check(highlightOf(victim) == nil, "dead zombie untinted")
victim:Destroy()
step(4)
check(count() == 0, "all parts gone after the horde (" .. count() .. ")")
check(stat("Highlights") == 0 and stat("Tinted") == 0, "no highlights / state left (" .. tostring(script:GetAttribute("Highlights")) .. ")")

--==================================================================== 10. test hook + sold build restores the glow
resetEmits()
workspace:SetAttribute("DefenceFXTest", "Tesla")
step(DT)
check(emittedBy("Tesla") > 0 and workspace:GetAttribute("DefenceFXTest") == nil, "DefenceFXTest hook plays + clears")
step(0.3)
step(0.37) -- somewhere mid-pulse
tower.Parent = nil
removeTag(tower, "PlacedBuild")
step(0.1)
local restored = true
for _, p in pairs(glowParts) do if p.Transparency ~= 0 then restored = false end end
check(restored, "glow restored to its authored transparency when the build goes")
local left = 0
for _, a in ipairs(terrain:GetChildren()) do if a.Name == "DefenceFX_Mist" then left += 1 end end
check(left == 0 and stat("IdleBuilds") == 0, "idle effects torn down with the build")

--==================================================================== 11. a TeslaCoil without Spark pivots crackles at its ProngTips; a LaserGate at Spark pivots
local function placeKind(key, pivots, at)
	local model = new("Model")
	model.Name = key
	model:SetAttribute("BuildKey", key)
	model:SetAttribute("Category", "Defences")
	model:SetAttribute("Scale", 1)
	model:SetAttribute("AuthoredCentre", V(0, 4, 0))
	for k, v in pairs(pivots) do model:SetAttribute("Pivot_" .. k, v) end
	local hb = new("Part", model) hb.Name = "Hitbox" hb.CFrame = CF.new(at + V(0, 4, 0))
	model.PrimaryPart = hb
	model.Parent = workspace
	addTag(model, "PlacedBuild")
	return model
end
local tesla = placeKind("TeslaCoil", {ProngTip1 = V(0.85, 9.59, -0.85), ProngTip2 = V(-0.85, 9.59, -0.85)}, V(-20, 0, 0))
local laser = placeKind("LaserGate", {Spark1 = V(-1.95, 2, 0), Spark2 = V(1.95, 2, 0)}, V(-40, 0, 0))
step(2.0)
local sparkAtts, sparkEmits = 0, 0
for _, a in ipairs(terrain:GetChildren()) do
	if a.Name == "DefenceFX_Spark" then
		sparkAtts += 1
		sparkEmits += (M.emitted[a:FindFirstChildOfClass("ParticleEmitter")] or 0)
	end
end
check(sparkAtts == 2 and sparkEmits > 4, "tesla + laser idle sparks (" .. sparkAtts .. " atts, " .. sparkEmits .. " sparks)")
check(stat("IdleBuilds") == 2, "two idle builds")

--==================================================================== the whole run: no emission point ever moved before a render
do
	local lastFrame, emitterFrame = {}, {}
	local bad, total = 0, 0
	for _, e in ipairs(M.emitLog) do
		total += 1
		if emitterFrame[e.pe] == e.frame then bad += 1 end -- one emitter twice in a frame = two bursts on one point
		emitterFrame[e.pe] = e.frame
		local lf = lastFrame[e.att]
		if lf and lf ~= e.frame and e.frame - lf < 2 then bad += 1 end -- moved again the very next frame
		lastFrame[e.att] = e.frame
	end
	check(total > 200 and bad == 0, "no emission point reused before a render in the whole run (" .. bad .. " of " .. total .. " emits)")
end

check(#warns == 0, "no warnings (" .. #warns .. ")")
print(("DefenceFXClient harness: %d passed, %d failed"):format(passes, fails))
if fails > 0 then error("FAILED") end

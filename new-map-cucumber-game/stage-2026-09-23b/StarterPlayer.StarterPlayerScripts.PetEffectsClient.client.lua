--[[
	PetEffectsClient  (LocalScript, StarterPlayerScripts)
	Every pet world effect on this client (2026-09-22, pet-system polish). Purely cosmetic: the
	server already applied the damage / buff / block before it sent the event, so a dropped or
	culled effect never changes gameplay, and nothing here talks back to the server.
	Remotes.PetEffects (PetEffectsBus: the owner + every player within FX.RADIUS) delivers batches
	{T, Events}; every event has Id, Kind, T (server clock) and Owner (UserId):
	  * Shot -- a pooled neon BOLT (2026-09-23: the Zombie Cucumber Game's pet-bolt look - a ribbon Trail
	    behind a ball that accelerates into the target and shrinks, coloured by the rarity glow) flies from
	    the pet's muzzle (its PrimaryPart + PetMotion.MUZZLE_HEIGHT when the model with that PetId is
	    streamed in here, else the server's From) to To in FX.SHOT_TRAVEL_MIN..MAX seconds, flashing
	    bigger for a moment as it leaves and bursting into a small hit sparkle on arrival. It always
	    reaches the old endpoint (a dead zombie is fine) and never deals damage. It also writes the
	    client-local attributes FxAimAt / FxAimUntil / FxShotAt on that pet model, which
	    PetRoamClient -- the only PivotTo owner of pets -- turns into facing the target plus a short
	    shot squash. FxShotAt is the moment the effect starts here (the event's T, or the arrival
	    time when the batch arrives after T) so the squash plays with the orb.
	  * AbilityApplied -- an FX.ARC_TIME orb arc in the ability colour from the pet to the cucumber
	    and a pulse on the target, with one soft sound; the owner also gets ONE Notify toast
	    (PetBalance.TEXT.ProcToast, e.g. "Cat gave Lucky Harvest to your cucumber - x1.5 for 90s"),
	    also while the effect itself is culled or streamed out.
	  * ShieldBlocked -- a ring of green shards bursting from the cucumber plus one restrained sound
	    (SoundController.PlayFXAt with a Key + MinInterval); the owner gets TEXT.ShieldToast.
	SHIELD SHELLS: every streamed PlacedCucumber with a live PetBuff_Guard (its expiry, server clock)
	gets a faint green SelectionBox adorned to its PlotHitbox, parented to the LOCAL folder
	workspace.CurrentCamera.PetFxLocal -- never under the cucumber model (the build-mode move ghost is a
	client clone of the model and would copy it). Only real placed cucumbers qualify: Parent named
	"Placed" inside workspace.Map.Lobby.Plots (the "<name> Preview" ghost keeps the tag and the
	PetBuff_* attributes but hangs straight under workspace), judged lazily on AncestryChanged and on
	every SHELL_TICK, never cached from a moment the model had no parent. A shell whose PlotHitbox
	streams out is dropped; a DescendantAdded watcher rebuilds it when a PlotHitbox comes back under
	the still-tagged model. The PetId -> model index follows the PlotPet tag and AncestryChanged.
	Budget: one pool of neon parts, at most FX.MAX_PROJECTILES alive (effects past it are dropped);
	world effects whose endpoints are all farther than FX.RADIUS from the camera are culled; ONE
	Heartbeat stepper, no tweens (plays in an unfocused Studio too).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PET_TAG = "PlotPet"
local CUCUMBER_TAG = "PlacedCucumber"
local EFFECTS_REMOTE = "PetEffects"
local FX_FOLDER = "PetFxLocal" -- under workspace.CurrentCamera: local-only parts and shells
local SHOT_SPEED = 180 -- studs/s; the travel time is clamped to FX.SHOT_TRAVEL_MIN..MAX
local SHOT_SIZE = 0.45 -- studs
local MUZZLE_FLASH_TIME, MUZZLE_FLASH_SCALE = 0.04, 1.7 -- the orb starts this much bigger for a moment
local SPARK_TIME, SPARK_SIZE = 0.16, 1.3 -- the hit sparkle: grows to SPARK_SIZE studs while fading
local AIM_HOLD = 0.6 -- s the pet keeps facing its target (FxAimUntil)
local ARC_SIZE = 0.7 -- studs
local ARC_HEIGHT_MIN, ARC_HEIGHT_MAX, ARC_HEIGHT_FRAC = 2, 9, 0.35 -- arc apex over the straight line
local PULSE_TIME, PULSE_SIZE = 0.35, 4 -- the target pulse
local SHARD_COUNT, SHARD_TIME, SHARD_REACH, SHARD_RISE = 8, 0.45, 3.5, 1.2
local SHARD_SIZE = Vector3.new(0.5, 0.12, 0.28)
local SHELL_TICK = 0.25 -- s between shell re-checks (expiry, ghost filter, streamed hitbox)
local SHELL_LINE, SHELL_TRANSPARENCY, SHELL_SURFACE = 0.04, 0.4, 0.92
local SHIELD_SOUND = {Name = "Rock Crumble", Volume = 0.45, Key = "PetShieldBlock", MinInterval = 0.5}
local ABILITY_SOUND = {Name = "Magic Shimmer", Volume = 0.4, Key = "PetAbility", MinInterval = 0.3}
local SHIELD_TOAST_GAP = 1 -- s between two shield toasts (several zombies can hit one shield wall)
local MAX_EVENTS = 64 -- events read per batch (the bus sends <= FX.MAX_EVENTS_PER_BATCH)
local WARN_GAP = 60 -- s between two warnings with the same key
local PARK = CFrame.new(0, -5000, 0) -- idle pooled parts wait here, invisible
local WHITE = Color3.fromRGB(255, 255, 255)
--.. 2026-09-23 (user: "the bullets from pets that hit cucumbers" in the Zombie Cucumber Game should hit the
--.. zombies here): the pet BOLT look ported from that game's BreakablesClient.petBolts - a 0.4-stud neon ball
--.. that ACCELERATES into its target (Quad In) while shrinking to 0.2, trailing a soft ribbon (Trail, 0.18 s,
--.. light emission). Colours blend the zombie game's pale-green ball / green ribbon with the pet's rarity glow.
local BOLT_BALL = Color3.fromRGB(225, 255, 200)
local BOLT_TRAIL = Color3.fromRGB(120, 220, 90)
local BOLT_BLEND = 0.5 -- 0 = the zombie game's colours, 1 = pure rarity glow
local BOLT_END_SIZE = 0.2 -- studs at impact
local TRAIL_LIFETIME = 0.18

--..Pure helpers (2026-09-22): the unit tests load this source with loadstring(src)("__core")..--
local Core = {}

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.Finite = Finite

local function ValidVector(v)
	return typeof(v) == "Vector3" and Finite(v.X) and Finite(v.Y) and Finite(v.Z)
end
Core.ValidVector = ValidVector

--.. a shot's flight time: distance / speed, clamped to [min, max] (max for broken input)
function Core.TravelTime(distance, min, max, speed)
	if not Finite(distance) or not Finite(speed) or speed <= 0 then return max end
	return math.clamp(distance / speed, min, max)
end

--.. a point on the ability arc: the straight line plus a parabola peaking `height` studs at k = 0.5
function Core.ArcPoint(from, to, height, k)
	k = math.clamp(k, 0, 1)
	return from:Lerp(to, k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
end

--.. cull a world effect when every endpoint is farther than radius from the camera (no camera: keep)
function Core.ShouldCull(camPos, a, b, radius)
	if typeof(camPos) ~= "Vector3" then return false end
	local near = false
	if typeof(a) == "Vector3" and (a - camPos).Magnitude <= radius then near = true end
	if typeof(b) == "Vector3" and (b - camPos).Magnitude <= radius then near = true end
	return not near
end

--.. is a PetBuff_Guard expiry (server clock) still ahead of now
function Core.GuardLive(expiresAt, now)
	return Finite(expiresAt) and Finite(now) and expiresAt > now
end

--.. the effect budget: Take() -> false when `max` are alive (the new effect is dropped), Give() frees one
function Core.NewBudget(max)
	local budget = {Live = 0, Max = Finite(max) and math.max(math.floor(max), 0) or 0, Dropped = 0}
	function budget:Take()
		if self.Live >= self.Max then
			self.Dropped += 1
			return false
		end
		self.Live += 1
		return true
	end
	function budget:Give()
		if self.Live > 0 then self.Live -= 1 end
	end
	return budget
end

--.. FxShotAt / FxAimUntil for a shot sent at eventT and shown at `now` (both server clock): the squash
--.. starts when the orb does, which is `now` when the batch arrived after eventT
function Core.AimStamp(eventT, now, hold)
	local shotAt = now
	if Finite(eventT) and Finite(now) and eventT > now then shotAt = eventT end
	return shotAt, shotAt + hold
end

--.. the whole seconds a buff granted at t lasts (for PetStats.AbilityShort); nil for broken input
function Core.ToastSeconds(expiresAt, t)
	if not Finite(expiresAt) or not Finite(t) then return nil end
	return math.max(math.floor(expiresAt - t + 0.5), 0)
end

if ... == "__core" then return Core end -- unit tests only: a LocalScript is never started with arguments

local LocalPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local PetBalance = require(Modules:WaitForChild("PetBalance"))
local PetStats = require(Modules:WaitForChild("PetStats"))
local PetMotion = require(Modules:WaitForChild("PetMotion"))
local PetsCatalog = require(Modules:WaitForChild("PetsCatalog"))
local Notify = require(Modules:WaitForChild("Notify"))
local SoundController = require(Modules:WaitForChild("SoundController"))

local FX = type(PetBalance.FX) == "table" and PetBalance.FX or {}
local TEXT = type(PetBalance.TEXT) == "table" and PetBalance.TEXT or {}
local ABILITIES = type(PetBalance.ABILITIES) == "table" and PetBalance.ABILITIES or {}
local MAX_PROJECTILES = tonumber(FX.MAX_PROJECTILES) or 64
local RADIUS = tonumber(FX.RADIUS) or 180
local TRAVEL_MIN, TRAVEL_MAX = tonumber(FX.SHOT_TRAVEL_MIN) or 0.12, tonumber(FX.SHOT_TRAVEL_MAX) or 0.2
local ARC_TIME = tonumber(FX.ARC_TIME) or 0.32
local MUZZLE = Vector3.new(0, tonumber(PetMotion.MUZZLE_HEIGHT) or 1.5, 0)
local GUARD_COLOR = ABILITIES.Guard and typeof(ABILITIES.Guard.Color) == "Color3" and ABILITIES.Guard.Color or Color3.fromRGB(90, 230, 110)

local Budget = Core.NewBudget(MAX_PROJECTILES)
local FreeParts = {} -- pooled parts waiting at PARK
local animations = {} -- live effects: one stepping function each
local PetModels = {} -- [PetId] = pet Model (its PrimaryPart may be streamed out)
local PetConns = {} -- [model] = AncestryChanged connection
local Cucumbers = {} -- [model] = {Conns, Shell, Watch}
local Guarded = {} -- [model] = entry, for the cucumbers carrying a PetBuff_Guard attribute
local lastWarn = {}
local lastShieldToast = -math.huge
local fxFolder = nil

local function WarnOnce(key, message)
	local now = os.clock()
	if lastWarn[key] and now - lastWarn[key] < WARN_GAP then return end
	lastWarn[key] = now
	warn(message)
end

--.. the local folder under the camera (a destroyed camera takes the old folder with it: start a new one)
local function FxFolder()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	if fxFolder and fxFolder.Parent ~= camera then
		if not pcall(function() fxFolder.Parent = camera end) then fxFolder = nil end
	end
	if not fxFolder then
		fxFolder = camera:FindFirstChild(FX_FOLDER)
		if not fxFolder then
			fxFolder = Instance.new("Folder")
			fxFolder.Name = FX_FOLDER
			fxFolder.Parent = camera
		end
	end
	return fxFolder
end

--..Pool..--
local function AcquirePart(shape, size, color)
	local folder = FxFolder()
	if not folder or not Budget:Take() then return nil end
	local part
	while #FreeParts > 0 do
		local p = table.remove(FreeParts)
		if p.Parent == folder then part = p break end -- (a part lost with an old camera is skipped)
	end
	if not part then
		part = Instance.new("Part")
		part.Name = "PetFx"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Massless = true
		part.Material = Enum.Material.Neon
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = 1
		part.CFrame = PARK
		part.Parent = folder
	end
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Transparency = 0
	return part
end

--.. the ribbon behind a bolt: built once per pooled part, switched on only while a shot flies
local function TrailOf(part)
	local trail = part:FindFirstChild("BoltTrail")
	if not trail then
		local a0 = Instance.new("Attachment")
		a0.Name = "BoltA0"
		a0.Position = Vector3.new(0, 0.15, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "BoltA1"
		a1.Position = Vector3.new(0, -0.15, 0)
		a1.Parent = part
		trail = Instance.new("Trail")
		trail.Name = "BoltTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
		trail.Lifetime = TRAIL_LIFETIME
		trail.LightEmission = 0.6
		trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2)})
		trail.Enabled = false
		trail.Parent = part
	end
	return trail
end

local function ReleasePart(part)
	Budget:Give()
	local trail = part:FindFirstChild("BoltTrail")
	if trail then trail.Enabled = false end
	part.Transparency = 1
	part.CFrame = PARK
	if #FreeParts < MAX_PROJECTILES then
		table.insert(FreeParts, part)
	else
		part:Destroy()
	end
end

--..Pets: PetId -> model index..--
local function IndexPet(model)
	local id = model:GetAttribute("PetId")
	if type(id) == "string" and model:IsDescendantOf(workspace) then PetModels[id] = model end
end

local function UnindexPet(model)
	local id = model:GetAttribute("PetId")
	if type(id) == "string" and PetModels[id] == model then PetModels[id] = nil end
end

local function AddPet(model)
	if not model:IsA("Model") or PetConns[model] then return end
	IndexPet(model)
	PetConns[model] = model.AncestryChanged:Connect(function()
		if model:IsDescendantOf(workspace) then IndexPet(model) else UnindexPet(model) end
	end)
end

local function RemovePet(model)
	UnindexPet(model)
	local conn = PetConns[model]
	PetConns[model] = nil
	if conn then conn:Disconnect() end
end

local function PetModelOf(petId)
	local model = type(petId) == "string" and PetModels[petId] or nil
	if model and not model:IsDescendantOf(workspace) then
		PetModels[petId] = nil
		return nil
	end
	return model
end

--.. the muzzle of the locally rendered pet (PetRoamClient's pose), else the server's origin
local function MuzzleOf(petId, fallback)
	local model = PetModelOf(petId)
	local root = model and model.PrimaryPart
	if root and root.Parent then return root.Position + MUZZLE, model end
	return fallback, model
end

--.. where an effect lands on a cucumber: its PlotHitbox when streamed in here, else the server's point
local function CucumberPoint(cucumber, fallback)
	if typeof(cucumber) == "Instance" and cucumber:IsDescendantOf(workspace) then
		local hitbox = cucumber:FindFirstChild("PlotHitbox")
		if hitbox and hitbox:IsA("BasePart") then return hitbox.Position end
		if cucumber:IsA("Model") then return cucumber:GetPivot().Position end
	end
	return ValidVector(fallback) and fallback or nil
end

local function CameraPosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

--..Effects..--
local function OnShot(ev, nowServer, camPos)
	local to = ev.To
	if not ValidVector(to) then return end
	local from, model = MuzzleOf(ev.PetId, ValidVector(ev.From) and ev.From or nil)
	if model then -- PetRoamClient reads these (local attributes, never replicated)
		local shotAt, aimUntil = Core.AimStamp(ev.T, nowServer, AIM_HOLD)
		model:SetAttribute("FxAimAt", to)
		model:SetAttribute("FxAimUntil", aimUntil)
		model:SetAttribute("FxShotAt", shotAt)
	end
	if not from or Core.ShouldCull(camPos, from, to, RADIUS) then return end
	local glow = PetsCatalog.RARITY_GLOW
	local rarity = type(glow) == "table" and typeof(glow[ev.Rarity]) == "Color3" and glow[ev.Rarity] or WHITE
	local color = BOLT_BALL:Lerp(rarity, BOLT_BLEND)
	local part = AcquirePart(Enum.PartType.Ball, Vector3.one * SHOT_SIZE, color)
	if not part then return end
	local travel = Core.TravelTime((to - from).Magnitude, TRAVEL_MIN, TRAVEL_MAX, SHOT_SPEED)
	local t0 = os.clock()
	part.CFrame = CFrame.new(from)
	local trail = TrailOf(part)
	trail.Color = ColorSequence.new(BOLT_TRAIL:Lerp(rarity, BOLT_BLEND))
	trail.Enabled = true
	table.insert(animations, function(now)
		local t = now - t0
		if t < travel then
			local k = t / travel
			k = k * k -- Quad In: the bolt accelerates into the zombie (the zombie game's pet bolt flight)
			part.CFrame = CFrame.new(from:Lerp(to, k))
			part.Size = Vector3.one * (t < MUZZLE_FLASH_TIME and SHOT_SIZE * MUZZLE_FLASH_SCALE or (SHOT_SIZE + (BOLT_END_SIZE - SHOT_SIZE) * k))
			return true
		end
		trail.Enabled = false
		local k = (t - travel) / SPARK_TIME
		if k >= 1 then
			ReleasePart(part)
			return false
		end
		part.CFrame = CFrame.new(to)
		part.Size = Vector3.one * (SHOT_SIZE + (SPARK_SIZE - SHOT_SIZE) * k)
		part.Transparency = k
		return true
	end)
end

local function OnAbility(ev, nowServer, camPos)
	local ability = ev.Ability
	local row = type(ability) == "string" and ABILITIES[ability] or nil
	if type(row) ~= "table" then return end
	local color = typeof(row.Color) == "Color3" and row.Color or WHITE
	if LocalPlayer and ev.Owner == LocalPlayer.UserId and type(TEXT.ProcToast) == "string" then
		local petName = type(ev.PetName) == "string" and ev.PetName ~= "" and ev.PetName or "Your pet"
		local short = PetStats.AbilityShort(ability, Core.ToastSeconds(ev.ExpiresAt, ev.T))
		local ok, text = pcall(string.format, TEXT.ProcToast, petName, tostring(row.DisplayName or ability), short)
		if ok then Notify.Show(text, color) end
	end
	local from = MuzzleOf(ev.PetId, ValidVector(ev.From) and ev.From or nil)
	local to = CucumberPoint(ev.Cucumber, ev.To)
	if not from or not to or Core.ShouldCull(camPos, from, to, RADIUS) then return end
	SoundController.PlayFXAt(ABILITY_SOUND.Name, to, {Volume = ABILITY_SOUND.Volume, Key = ABILITY_SOUND.Key, MinInterval = ABILITY_SOUND.MinInterval})
	local part = AcquirePart(Enum.PartType.Ball, Vector3.one * ARC_SIZE, color)
	if not part then return end
	local height = math.clamp((to - from).Magnitude * ARC_HEIGHT_FRAC, ARC_HEIGHT_MIN, ARC_HEIGHT_MAX)
	local t0 = os.clock()
	part.CFrame = CFrame.new(from)
	table.insert(animations, function(now)
		local t = now - t0
		if t < ARC_TIME then
			part.CFrame = CFrame.new(Core.ArcPoint(from, to, height, t / ARC_TIME))
			return true
		end
		local k = (t - ARC_TIME) / PULSE_TIME -- the target pulse
		if k >= 1 then
			ReleasePart(part)
			return false
		end
		part.CFrame = CFrame.new(to)
		part.Size = Vector3.one * (ARC_SIZE + (PULSE_SIZE - ARC_SIZE) * k)
		part.Transparency = 0.3 + 0.7 * k
		return true
	end)
end

local function OnShield(ev, nowServer, camPos)
	if LocalPlayer and ev.Owner == LocalPlayer.UserId and type(TEXT.ShieldToast) == "string" then
		local clock = os.clock()
		if clock - lastShieldToast >= SHIELD_TOAST_GAP then
			lastShieldToast = clock
			Notify.Show(TEXT.ShieldToast, GUARD_COLOR)
		end
	end
	local at = CucumberPoint(ev.Cucumber, ev.At)
	if not at or Core.ShouldCull(camPos, at, nil, RADIUS) then return end
	SoundController.PlayFXAt(SHIELD_SOUND.Name, at, {Volume = SHIELD_SOUND.Volume, Key = SHIELD_SOUND.Key, MinInterval = SHIELD_SOUND.MinInterval})
	local t0 = os.clock()
	local offset = math.random() * math.pi * 2
	for i = 1, SHARD_COUNT do
		local part = AcquirePart(Enum.PartType.Block, SHARD_SIZE, GUARD_COLOR)
		if not part then break end -- over budget: fewer shards
		local angle = offset + (i / SHARD_COUNT) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local spin = (i % 2 == 0 and 1 or -1) * math.pi * 2
		part.CFrame = CFrame.new(at)
		table.insert(animations, function(now)
			local k = (now - t0) / SHARD_TIME
			if k >= 1 then
				ReleasePart(part)
				return false
			end
			local out = 1 - (1 - k) * (1 - k) -- quad out: bursts, then drifts
			local pos = at + dir * (SHARD_REACH * out) + Vector3.new(0, SHARD_RISE * out, 0)
			part.CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, spin * k)
			part.Transparency = k * k
			return true
		end)
	end
end

local HANDLERS = {Shot = OnShot, AbilityApplied = OnAbility, ShieldBlocked = OnShield}

--..Shield shells..--
local function Plots()
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("Plots") or nil
end

--.. rule 0.14: a real placed cucumber, not the build-mode move ghost (judged now, never cached)
local function IsRealPlaced(model)
	local parent = model.Parent
	if not parent or parent.Name ~= "Placed" then return false end
	local plots = Plots()
	return plots ~= nil and model:IsDescendantOf(plots)
end

local UpdateShell

local function SetHitboxWatch(model, entry, on)
	if on and not entry.Watch then
		entry.Watch = model.DescendantAdded:Connect(function(d)
			if d.Name == "PlotHitbox" and d:IsA("BasePart") then
				task.defer(function()
					if Cucumbers[model] == entry then UpdateShell(model, entry, workspace:GetServerTimeNow()) end
				end)
			end
		end)
	elseif not on and entry.Watch then
		entry.Watch:Disconnect()
		entry.Watch = nil
	end
end

function UpdateShell(model, entry, now)
	local want = IsRealPlaced(model) and Core.GuardLive(model:GetAttribute("PetBuff_Guard"), now)
	local hitbox = want and model:FindFirstChild("PlotHitbox") or nil
	if hitbox and not hitbox:IsA("BasePart") then hitbox = nil end
	if hitbox then
		local shell = entry.Shell
		if not shell or not shell.Parent then
			local folder = FxFolder()
			if not folder then return end
			shell = Instance.new("SelectionBox")
			shell.Name = "LeafShield"
			shell.Color3 = GUARD_COLOR
			shell.LineThickness = SHELL_LINE
			shell.Transparency = SHELL_TRANSPARENCY
			shell.SurfaceColor3 = GUARD_COLOR
			shell.SurfaceTransparency = SHELL_SURFACE
			shell.Adornee = hitbox
			shell.Parent = folder
			entry.Shell = shell
		elseif shell.Adornee ~= hitbox then
			shell.Adornee = hitbox
		end
	elseif entry.Shell then
		entry.Shell:Destroy()
		entry.Shell = nil
	end
	--.. a live guard whose PlotHitbox is streamed out: rebuild the moment one comes back
	SetHitboxWatch(model, entry, want and not hitbox)
end

local function RefreshGuard(model, entry)
	if Cucumbers[model] ~= entry then return end
	Guarded[model] = model:GetAttribute("PetBuff_Guard") ~= nil and entry or nil
	UpdateShell(model, entry, workspace:GetServerTimeNow())
end

local function AddCucumber(model)
	if Cucumbers[model] or not model:IsA("Model") then return end
	local entry = {Conns = {}}
	Cucumbers[model] = entry
	local function refresh() RefreshGuard(model, entry) end
	table.insert(entry.Conns, model:GetAttributeChangedSignal("PetBuff_Guard"):Connect(refresh))
	table.insert(entry.Conns, model.AncestryChanged:Connect(refresh))
	refresh()
end

local function RemoveCucumber(model)
	local entry = Cucumbers[model]
	if not entry then return end
	Cucumbers[model] = nil
	Guarded[model] = nil
	for _, c in ipairs(entry.Conns) do c:Disconnect() end
	SetHitboxWatch(model, entry, false)
	if entry.Shell then
		entry.Shell:Destroy()
		entry.Shell = nil
	end
end

--..ONE Heartbeat stepper: effects every frame, shells every SHELL_TICK..--
local shellClock = 0
RunService.Heartbeat:Connect(function(dt)
	shellClock += dt
	if shellClock >= SHELL_TICK then
		shellClock = 0
		local now = workspace:GetServerTimeNow()
		for model, entry in pairs(Guarded) do UpdateShell(model, entry, now) end
	end
	if #animations == 0 then return end
	local now = os.clock()
	for index = #animations, 1, -1 do
		if not animations[index](now) then
			animations[index] = animations[#animations]
			animations[#animations] = nil
		end
	end
end)

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(EFFECTS_REMOTE, 60)
	if not remote then warn("[PetEffectsClient] no Remotes." .. EFFECTS_REMOTE .. " (PetEffectsBus makes it) - pet effects are off") return end
	remote.OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" or type(batch.Events) ~= "table" then return end
		local nowServer = workspace:GetServerTimeNow()
		local camPos = CameraPosition()
		for i = 1, math.min(#batch.Events, MAX_EVENTS) do
			local ev = batch.Events[i]
			local handler = type(ev) == "table" and HANDLERS[ev.Kind] or nil
			if handler then
				local ok, err = pcall(handler, ev, nowServer, camPos)
				if not ok then WarnOnce("event:" .. tostring(ev.Kind), "[PetEffectsClient] " .. tostring(ev.Kind) .. " effect failed: " .. tostring(err)) end
			end
		end
	end)
end)

for _, model in ipairs(CollectionService:GetTagged(PET_TAG)) do AddPet(model) end
CollectionService:GetInstanceAddedSignal(PET_TAG):Connect(AddPet)
CollectionService:GetInstanceRemovedSignal(PET_TAG):Connect(RemovePet)
for _, model in ipairs(CollectionService:GetTagged(CUCUMBER_TAG)) do AddCucumber(model) end
CollectionService:GetInstanceAddedSignal(CUCUMBER_TAG):Connect(AddCucumber)
CollectionService:GetInstanceRemovedSignal(CUCUMBER_TAG):Connect(RemoveCucumber)

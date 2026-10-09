--[[
	Fridge  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the working FRIDGE (server half: ServerStorage.FunBehaviours.Fridge; model =
	fun-builds/models/build_Fridge.py).
	  * DOORS: Fun_Door / Fun_Freezer are signed server times (> 0 opened at, < 0 closed at, 0 shut). The
	    Door* / FreezerDoor* parts swing as rigid groups about the vertical axis through Pivot_DoorHinge /
	    Pivot_FreezerHinge by State_DoorOpen / State_FreezerDoorOpen degrees (+ = free edge to the front):
	    opening eases out with a small overshoot, closing eases in-out and ends on a soft thud. Progress comes
	    from Kit.Now() - so every client swings together, and one streaming in mid-swing picks it up.
	    While a door is off its seat its parts stop colliding locally (a swinging door never shoves the local
	    character); closed doors collide again.
	  * while a compartment is open: its ceiling / back-wall strip (LightStrip / FreezerLight) turns Neon, a
	    PointLight fills it (one per compartment - 2 lights max) and cold mist spills out of the bottom of the
	    opening and sinks to the floor (a burst on opening, then a gentle trickle).
	  * a quiet compressor hum loops at the back (only audible close by, only running while the camera is within
	    HUM_RANGE), a touch louder while a door is open.
	Sounds: FunAssets.Sfx.FridgeHum / FridgeOpen / FridgeClose at their natural pitch (HumLoop / DoorOpen / DoorClose only
	if a key is ever dropped). The open clip skips its lead-in so the seal squeak comes as the door leaves the cabinet;
	the close clip starts early so its thud lands as the door meets it.
	The state resetting to 0 (the server restarting the behaviour after a move / mend) is a silent snap shut, no thud.
	Every part touched (CFrame, CanCollide, Material, Color) is restored on cleanup, relative to where the
	build IS then (a move re-runs the behaviour from scratch).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local SWING_TIME = 0.6                       -- s per swing (the server cooldown is a touch longer)
local OVERSHOOT = 1.35                       -- ease-out-back strength of the opening swing
local LIGHT_OFF_AT = 0.85                    -- closing progress at which the interior light goes out
local SOLID_BELOW_DEG = 1                    -- a door this close to shut collides again
local STRIP_COLOR = Color3.fromRGB(255, 246, 222)
local FREEZER_STRIP_COLOR = Color3.fromRGB(225, 242, 255)
local HUM_VOLUME, HUM_VOLUME_OPEN = 0.1, 0.16
local HUM_RANGE = 34                         -- studs camera <-> build within which the hum loop runs
local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MIST_RATE = 10                         -- particles / s per open compartment
local MIST_BURST = 8                         -- puffed out the moment a door opens

--..Sounds (fun-builds/assets/ASSETS.md)..--
--.. Speed = PlaybackSpeed, Skip = s of the clip jumped over on Play, Hit = s into the clip of its audible moment
local SFX = FunAssets.Sfx
local SOUNDS = {
	Hum = {Id = SFX.FridgeHum or SFX.HumLoop, Speed = 1},               -- refrigerator hum, 72 s loop (both keys)
	Open = SFX.FridgeOpen and {Id = SFX.FridgeOpen, Speed = 1, Volume = 0.45, Skip = 0.5} -- seal squeak at 0.65 s
		or {Id = SFX.DoorOpen, Speed = 1, Volume = 0.45, Skip = 0.45},                   -- squeak at 0.6-0.9 s
	Close = SFX.FridgeClose and {Id = SFX.FridgeClose, Speed = 1, Volume = 0.55, Hit = 0.35} -- soft slam: thud at 0.35 s
		or {Id = SFX.DoorClose, Speed = 0.9, Volume = 0.55, Hit = 0.25},                   -- clunk at 0.25 s
}
--.. s into a closing swing to start the close sound, so its thud lands as the door meets the cabinet
local CLOSE_START = math.max(0, SWING_TIME - SOUNDS.Close.Hit / SOUNDS.Close.Speed)

local DOORS = {
	{State = "Door", Prefix = "Door", Hinge = "DoorHinge", OpenAttr = "State_DoorOpen", Strip = "LightStrip",
		Light = "FridgeLight", Mist = "FridgeMist", Opening = "OpeningFridge", Color = STRIP_COLOR,
		Range = 7, Brightness = 1.3, DefaultOpening = Vector3.new(3.42, 4.52, 0)},
	{State = "Freezer", Prefix = "FreezerDoor", Hinge = "FreezerHinge", OpenAttr = "State_FreezerDoorOpen",
		Strip = "FreezerLight", Light = "FreezerLight", Mist = "FreezerMist", Opening = "OpeningFreezer",
		Color = FREEZER_STRIP_COLOR, Range = 5, Brightness = 1.0, DefaultOpening = Vector3.new(3.42, 2.08, 0)},
}

local B = {}
B.Keys = {"Fridge"}
B.StepRange = 160

--..Easing..--
local function EaseOutBack(p)
	local c = OVERSHOOT
	local q = p - 1
	return 1 + (c + 1) * q * q * q + c * q * q
end

local function EaseInOutCubic(p)
	if p < 0.5 then return 4 * p * p * p end
	local q = -2 * p + 2
	return 1 - q * q * q / 2
end

--..Sound helpers..--
local function MakeSfx(ctx, parent, def, extra)
	local props = {Volume = def.Volume, PlaybackSpeed = def.Speed}
	for k, v in pairs(extra or {}) do props[k] = v end
	return ctx:Sound(parent, def.Id, props)
end

--.. Play() starts at the TimePosition a script last set, so this jumps over the clip's lead-in
local function PlayFrom(sound, def)
	sound.TimePosition = def.Skip or 0
	sound:Play()
end

--..Effects..--
local function MakeMist(ctx, cf, width, s)
	local holder = ctx:Part({Name = "FridgeMist", Transparency = 1, Size = Vector3.new(math.max(0.2, width), 0.25 * s, 0.2 * s), CFrame = cf})
	local e = Instance.new("ParticleEmitter")
	e.Name = "ColdMist"
	e.Texture = MIST_TEXTURE
	e.Color = ColorSequence.new(Color3.fromRGB(232, 244, 255))
	e.LightEmission = 0.15
	e.LightInfluence = 0.6
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * s),
		NumberSequenceKeypoint.new(1, 2.3 * s),
	})
	e.Lifetime = NumberRange.new(1.6, 2.6)
	e.Rate = MIST_RATE
	e.Speed = NumberRange.new(0.9 * s, 1.8 * s)
	e.SpreadAngle = Vector2.new(25, 12)
	e.EmissionDirection = Enum.NormalId.Front -- the holder is turned like the build: Front = out of the fridge
	e.Acceleration = Vector3.new(0, -1.6 * s, 0) -- cold air sinks and spills along the floor
	e.Drag = 1.1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	e.Enabled = false
	e.Parent = holder
	return holder, e
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local origin = Kit.Origin(model)

	--..Hum at the back..--
	local humAt = Kit.Pivot(model, "Hum") or Kit.ToWorld(model, Vector3.new(0, 0.6, 1.2))
	local humHolder = ctx:Part({Name = "FridgeHum", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(humAt)})
	local hum = MakeSfx(ctx, humHolder, SOUNDS.Hum, {
		Looped = true, Volume = HUM_VOLUME, RollOffMinDistance = 4, RollOffMaxDistance = 26,
	})
	--.. only loops while the camera is close (a street of fridges should not keep dozens of silent loops running)
	local function SyncHum()
		local near = ctx:CameraDistance() < HUM_RANGE
		if near and not hum.IsPlaying then
			pcall(function() hum:Play() end)
		elseif not near and hum.IsPlaying then
			hum:Stop()
		end
	end
	SyncHum()
	ctx:Every(1, SyncHum)

	--..Door rigs..--
	local doors = {}
	local home = {} -- [part] = CFrame relative to the Hitbox (cleanup)
	local collide = {} -- [part] = authored CanCollide
	for _, cfg in ipairs(DOORS) do
		local parts = Kit.Parts(model, cfg.Prefix)
		local hinge = Kit.Pivot(model, cfg.Hinge)
		if #parts > 0 and hinge then
			local hingeCF = CFrame.new(hinge) * origin.Rotation -- local Y = the build's up
			for _, p in ipairs(parts) do
				home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame)
				collide[p] = p.CanCollide
			end
			local d = {
				Cfg = cfg, Parts = parts, Rig = Kit.Rig(parts, hingeCF),
				HingeRel = hitbox.CFrame:ToObjectSpace(hingeCF),
				OpenDeg = tonumber(model:GetAttribute(cfg.OpenAttr)) or 100,
				Open = false, At = 0, From = 0, Angle = 0, Settled = true, Primed = false,
				Quiet = true, Thud = true, Lit = false, Solid = true,
			}
			--.. interior strip (restored on cleanup)
			local strip = Kit.Part(model, cfg.Strip)
			if strip then
				d.Strip, d.StripMat, d.StripColor = strip, strip.Material, strip.Color
			end
			--.. PointLight (off until the door opens)
			local lightAt = Kit.Pivot(model, cfg.Light)
			if lightAt then
				local holder = ctx:Part({Name = "FridgeLight", Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(lightAt)})
				local light = Instance.new("PointLight")
				light.Color = cfg.Color
				light.Range = cfg.Range * s
				light.Brightness = cfg.Brightness
				light.Shadows = false
				light.Enabled = false
				light.Parent = holder
				d.Light = light
			end
			--.. cold mist + door sounds at the bottom-front of the opening
			local mistAt = model:GetAttribute("Pivot_" .. cfg.Mist)
			if typeof(mistAt) == "Vector3" then
				local opening = model:GetAttribute(cfg.Opening)
				if typeof(opening) ~= "Vector3" then opening = cfg.DefaultOpening end
				local holder, emitter = MakeMist(ctx, Kit.CFrameToWorld(model, CFrame.new(mistAt)), opening.X * 0.9 * s, s)
				d.Mist = emitter
				d.OpenSound = MakeSfx(ctx, holder, SOUNDS.Open)
				d.CloseSound = MakeSfx(ctx, holder, SOUNDS.Close)
			end
			table.insert(doors, d)
		end
	end
	if #doors == 0 then return end

	--..Lights / collisions..--
	local function SetLit(d, lit)
		if d.Lit == lit then return end
		d.Lit = lit
		if d.Light then d.Light.Enabled = lit end
		if d.Strip and d.Strip.Parent then
			d.Strip.Material = lit and Enum.Material.Neon or d.StripMat
			d.Strip.Color = lit and d.Cfg.Color or d.StripColor
		end
	end

	local function SetSolid(d, solid)
		if d.Solid == solid then return end
		d.Solid = solid
		for _, p in ipairs(d.Parts) do
			if p.Parent then p.CanCollide = solid and collide[p] or false end
		end
	end

	local function UpdateHum()
		local any = false
		for _, d in ipairs(doors) do
			if d.Open then any = true end
		end
		hum.Volume = any and HUM_VOLUME_OPEN or HUM_VOLUME
	end

	--..State -> swing..--
	local function Refresh(d)
		local v = tonumber(ctx:State(d.Cfg.State)) or 0
		local open, at = v > 0, math.abs(v)
		if d.Primed and open == d.Open and at == d.At then return end
		if not d.Primed then
			--.. first look (stream-in / restart): a swing already over just snaps, one under way plays on silently
			d.Primed = true
			d.From = open and 0 or d.OpenDeg
			d.Quiet = true
			d.Thud = not open and Kit.Now() - at > SWING_TIME
		else
			d.From = d.Angle -- carry on from wherever the door is now
			d.Quiet = false
			d.Thud = open
		end
		d.Open, d.At, d.Settled = open, at, false
		if at == 0 then
			--.. 0 = shut: a fresh build, or the server restarting the behaviour after a move / mend (it clears the
			--.. state, then sets 0) - a silent snap shut, never a swing or a thud
			d.From, d.Quiet, d.Thud = 0, true, true
		end
		if d.Mist then
			d.Mist.Enabled = open
			if open and not d.Quiet then pcall(function() d.Mist:Emit(MIST_BURST) end) end
		end
		if open and not d.Quiet and d.OpenSound then PlayFrom(d.OpenSound, SOUNDS.Open) end
		UpdateHum()
	end

	for _, d in ipairs(doors) do
		ctx:OnState(d.Cfg.State, function() Refresh(d) end)
	end

	--..Every frame (only while a door is moving)..--
	ctx:Step(function(_, now)
		if not hitbox.Parent then return end
		for _, d in ipairs(doors) do
			if not d.Settled then
				local p = math.clamp((now - d.At) / SWING_TIME, 0, 1)
				local target = d.Open and d.OpenDeg or 0
				local e = d.Open and EaseOutBack(p) or EaseInOutCubic(p)
				d.Angle = d.From + (target - d.From) * e
				Kit.PoseRig(d.Rig, hitbox.CFrame * d.HingeRel * CFrame.Angles(0, math.rad(d.Angle), 0))
				SetSolid(d, math.abs(d.Angle) < SOLID_BELOW_DEG)
				SetLit(d, d.Open or p < LIGHT_OFF_AT)
				if not d.Open and not d.Thud and now - d.At >= CLOSE_START then
					d.Thud = true -- started early: the clip's thud lands as the swing ends
					if not d.Quiet and d.CloseSound then PlayFrom(d.CloseSound, SOUNDS.Close) end
				end
				if p >= 1 then d.Settled = true end
			end
		end
	end)

	--..Cleanup: doors shut and solid, strips back to plain plastic, relative to where the build IS now..--
	return function()
		for _, d in ipairs(doors) do
			if d.Strip and d.Strip.Parent then
				d.Strip.Material = d.StripMat
				d.Strip.Color = d.StripColor
			end
		end
		if not hitbox.Parent then return end
		--.. a Broken build: BuildHealthService owns the collisions (it turned them off and gives them back on mend)
		local broken = Kit.IsBroken(model)
		for p, rel in pairs(home) do
			if p.Parent then
				p.CFrame = hitbox.CFrame * rel
				if not broken then p.CanCollide = collide[p] end
			end
		end
	end
end

return B

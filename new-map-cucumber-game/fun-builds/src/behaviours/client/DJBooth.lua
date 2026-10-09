--[[
	DJBooth  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the working DJ booth (fun-builds/CONTRACT.md, package DJBooth). Everything here is local and
	cosmetic, driven by the server state Fun_Playing / Fun_Track / Fun_StartedAt + Kit.Now(), so every client
	hears the same bar and sees the same light show:
	  * music: ONE looped 3D Sound in the booth's Hitbox (FunAssets.Music[Track], Volume 0.6, rolls off by 120
	    studs). Every SYNC_EVERY s its TimePosition is checked against (Kit.Now() - StartedAt) % TimeLength and
	    re-seeked when it drifts > 0.6 s. It pauses while the camera is > HEAR_RANGE away or the player muted
	    music (LocalPlayer attribute MusicMuted, the MusicClient convention). While the local character stands
	    near a playing booth the lobby music ducks (MusicManager.SetDuck "FunDJBooth"); the DJ track is NOT
	    registered with MusicManager, or that duck would duck it too
	  * records: the prop's Records part holds BOTH vinyls (one merged mesh), so each deck gets a runtime Neon
	    record disc with two groove marks that spins at 45 rpm while playing, colours cycling
	  * spot cans: the cans are merged into Hardware, so each one gets a runtime beam: a SpotLight + a camera-
	    facing light-cone Beam from its lens, sweeping between State_SpotAimFloor and State_SpotAimCrowd with a
	    mirrored side-to-side yaw (the two beams cross over the floor), colours cycling, a Neon lens cap over the
	    real lens in the beam colour
	  * beat: Letters / LedStrip / SpotGlow (the prop's Neon parts - "beat-sync by cycling their Transparency",
	    the Blender author's note) pulse on the beat: Sound.PlaybackLoudness drives it while the track is audible,
	    else a fixed 120 BPM pulse on the StartedAt grid. LedStrip also cycles its hue
	  * split parts (dormant on the shipped prop): if the model ever gets per-deck parts DeckAPlatter /
	    DeckARecord (+B) they spin instead of the runtime discs; DeckATonearm / DeckBTonearm swing between
	    State_ArmParked and State_ArmPlaying (the shipped arms are merged into Hardware in the built = playing
	    pose); SpotA / SpotB cans follow their beams
	B.Live[model] = {Pulse, Beat, At} is shared with the DanceFloor client (same Lua VM, required via
	script.Parent), so floors near a booth flash with its loudness pulse.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))
local MusicManager = nil
do
	local m = Modules:FindFirstChild("MusicManager")
	if m then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then MusicManager = mod end
	end
end

local player = Players.LocalPlayer

--..Config..--
local BPM = 120                    -- the fixed pulse when no loudness is available
local MUSIC_VOLUME = 0.6
local MUSIC_ROLLOFF_MIN = 14       -- studs: full volume inside this
local MUSIC_ROLLOFF_MAX = 120      -- studs: silent beyond this
local HEAR_RANGE = 200             -- camera farther than this: the local track pauses (resyncs on return)
local SYNC_EVERY = 0.5             -- s between drift checks
local MAX_DRIFT = 0.6              -- s of drift before the track is re-seeked
local DUCK_TAG = "FunDJBooth"
local DUCK_RANGE = 70              -- studs character <-> booth: the lobby music ducks inside this
local DUCK_FACTOR = 0.15
local RECORD_RPM = 45
local RECORD_LIFT = 0.20           -- authored: deck top (Pivot y 2.90) -> record-disc centre (vinyl face 3.09)
local RECORD_DIAMETER = 0.71       -- authored (the vinyl is 0.72)
local RECORD_THICK = 0.03
local GROOVE_RADIUS = 0.27         -- authored: between the label (r 0.20) and the rim (r 0.36)
local SPOT_YAW = math.rad(28)      -- side-to-side sweep amplitude
local SPOT_YAW_PERIOD = 3.2        -- s
local SPOT_TILT_PERIOD = 2.3       -- s for a floor -> crowd -> floor nod
local LENS_OUT = 0.235             -- authored: spot pivot -> just in front of the lens along the can axis
local LENS_DIAMETER = 0.46         -- authored (the lens is r 0.22)
local BEAM_LENGTH = 11             -- authored studs (the floor aim lands ~7.8 out; the ground hides the rest)
local BEAM_WIDTH0, BEAM_WIDTH1 = 0.4, 3.6 -- authored studs at the lens / the far end
local LIGHT_RANGE = 22             -- authored studs (clamped to 60)
local LIGHT_ANGLE = 40
local HUE_SPEED = 0.07             -- hue turns per second
local PULSE_DIM = 0.5              -- Neon Transparency added between beats
local BROKEN_T = 0.65              -- BuildHealthService BROKEN_TRANSPARENCY (a broken build's parts)
local NEON_PARTS = {"Letters", "LedStrip", "SpotGlow"}
local HUE_CYCLE_PART = "LedStrip"
local GROOVE_COLOUR = Color3.fromRGB(16, 20, 28)
local TAU = math.pi * 2
local DISC_TURN = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X: stand it up along Y

--..Authored fallbacks (props-dump/DJBooth.txt) for a model missing its Pivot_* / State_* attributes..--
local PIVOTS = {
	DeckAPlatter = Vector3.new(1.30, 2.90, 0.44), DeckBPlatter = Vector3.new(-1.30, 2.90, 0.44),
	DeckATonearm = Vector3.new(1.74, 3.20, 1.00), DeckBTonearm = Vector3.new(-1.74, 3.20, 1.00),
	SpotA = Vector3.new(3.30, 3.88, 0.30), SpotB = Vector3.new(-3.30, 3.88, 0.30),
}
local STATES = {ArmParked = 20, ArmPlaying = 0, SpotAimFloor = -120, SpotAimCrowd = -100}

local B = {}
B.StepRange = 220
B.Live = {} -- [booth model] = {Pulse = 0..1, Beat = beats since StartedAt, At = os.clock()} while it plays on screen

--..Lobby-music duck, shared by every booth on this client..--
local DuckVotes = {} -- [booth model] = true
local ducked = false
local function ApplyDuck()
	local want = next(DuckVotes) ~= nil
	if want == ducked or not MusicManager then return end
	ducked = want
	pcall(function()
		if want then
			MusicManager.SetDuck(DUCK_TAG, DUCK_FACTOR, 1)
		else
			MusicManager.ClearDuck(DUCK_TAG, 1.5)
		end
	end)
end

--..Helpers..--
local function AuthoredPivot(model, name)
	local v = model:GetAttribute("Pivot_" .. name)
	return typeof(v) == "Vector3" and v or PIVOTS[name]
end

local function AuthoredState(model, name)
	return tonumber(model:GetAttribute("State_" .. name)) or STATES[name]
end

--.. the can axis in the authored frame for a tilt about X (the Blender "degrees about X") and a yaw about Y:
--.. the can's rest axis is +Y, so tilt -120 = 30 degrees below horizontal, toward the front (-Z)
local function SpotAxis(tilt, yaw)
	return (CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)):VectorToWorldSpace(Vector3.yAxis)
end

local function Muted()
	return player:GetAttribute("MusicMuted") == true
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local hitbox = Kit.Hitbox(model)
	local hitboxCF0 = hitbox.CFrame
	local rot = Kit.Origin(model).Rotation

	--.. a local folder for the FX parts (in workspace, not the camera: SpotLights must light the world)
	local fx = ctx:Add(Instance.new("Folder"))
	fx.Name = "DJBoothFX"
	fx.Parent = workspace

	--.. has the build been moved / broken since this ran? (the framework restarts us 0.3 s later - stop writing now)
	local function Stale()
		return Kit.IsBroken(model) or hitbox.CFrame ~= hitboxCF0
	end

	--.. the value a restored Transparency should take (a broken build's parts stay faded like the server made them)
	local function Settle(t)
		if Kit.IsBroken(model) and t < 1 then return math.max(t, BROKEN_T) end
		return t
	end

	--..Beat-pulsed Neon parts..--
	local neon = {}
	for _, name in ipairs(NEON_PARTS) do
		local p = Kit.Part(model, name)
		if p then table.insert(neon, {Part = p, T = p.Transparency, Color = p.Color, Cycle = name == HUE_CYCLE_PART}) end
	end
	local function RestoreNeon()
		for _, n in ipairs(neon) do
			if n.Part.Parent then
				n.Part.Color = n.Color
				n.Part.Transparency = Settle(n.T)
			end
		end
	end

	--..Records (runtime discs, or split platter/record parts)..--
	local decks = {}
	for i, d in ipairs({"A", "B"}) do
		local base = Kit.CFrameToWorld(model, CFrame.new(AuthoredPivot(model, "Deck" .. d .. "Platter") + Vector3.new(0, RECORD_LIFT, 0)))
		local deck = {Base = base, Hue = (i - 1) * 0.5}
		local split = {}
		for _, name in ipairs({"Deck" .. d .. "Platter", "Deck" .. d .. "Record"}) do
			local p = Kit.Part(model, name)
			if p then table.insert(split, p) end
		end
		if #split > 0 then
			deck.Rig = Kit.Rig(split, base)
			deck.Home = {}
			for _, p in ipairs(split) do deck.Home[p] = hitboxCF0:ToObjectSpace(p.CFrame) end
		else
			deck.Disc = ctx:Part({
				Name = "DJRecord" .. d,
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Neon,
				Size = Vector3.new(RECORD_THICK, RECORD_DIAMETER, RECORD_DIAMETER) * s,
				CFrame = base * DISC_TURN,
				Transparency = 1,
				Parent = fx,
			})
			deck.Marks = {}
			for _, side in ipairs({1, -1}) do
				table.insert(deck.Marks, {
					Offset = CFrame.new(side * GROOVE_RADIUS * s, (RECORD_THICK * 0.5 + 0.004) * s, 0),
					Part = ctx:Part({
						Name = "DJGroove",
						Material = Enum.Material.SmoothPlastic,
						Color = GROOVE_COLOUR,
						Size = Vector3.new(0.13, 0.016, 0.035) * s,
						CFrame = base,
						Transparency = 1,
						Parent = fx,
					}),
				})
			end
		end
		decks[i] = deck
	end

	--..Tonearms (only when split out of Hardware)..--
	local armPlaying, armParked = AuthoredState(model, "ArmPlaying"), AuthoredState(model, "ArmParked")
	local arms = {}
	for i, d in ipairs({"A", "B"}) do
		local p = Kit.Part(model, "Deck" .. d .. "Tonearm")
		if p then
			local pivotCF = CFrame.new(Kit.ToWorld(model, AuthoredPivot(model, "Deck" .. d .. "Tonearm"))) * rot
			table.insert(arms, {
				Part = p, Pivot = pivotCF, Rel = pivotCF:ToObjectSpace(p.CFrame), Home = hitboxCF0:ToObjectSpace(p.CFrame),
				Sign = i == 1 and 1 or -1, Angle = nil, -- deck B is the mirror image: negate its angle
			})
		end
	end
	local function PoseArms(playing, dt)
		for _, arm in ipairs(arms) do
			--.. the arm was built in the playing pose, so the motion is relative to ArmPlaying
			local target = math.rad((playing and armPlaying or armParked) - armPlaying) * arm.Sign
			local angle = arm.Angle and arm.Angle + (target - arm.Angle) * math.min(1, dt * 5) or target
			if arm.Angle == nil or math.abs(angle - arm.Angle) > 1e-4 then
				arm.Angle = angle
				arm.Part.CFrame = arm.Pivot * CFrame.Angles(0, angle, 0) * arm.Rel
			end
		end
	end

	--..Spot beams..--
	local floorTilt = math.rad(AuthoredState(model, "SpotAimFloor")) -- the cans are built at this tilt
	local crowdTilt = math.rad(AuthoredState(model, "SpotAimCrowd"))
	local restAxis = rot:VectorToWorldSpace(SpotAxis(floorTilt, 0))
	local spots = {}
	for i, d in ipairs({"A", "B"}) do
		local pivot = Kit.ToWorld(model, AuthoredPivot(model, "Spot" .. d))
		local spot = {Pivot = pivot, Sign = i == 1 and 1 or -1, Phase = (i - 1) * math.pi, Hue = (i - 1) * 0.5}
		local can = Kit.Part(model, "Spot" .. d)
		if can then
			spot.Can = can
			spot.CanRel = (CFrame.new(pivot) * rot):ToObjectSpace(can.CFrame)
			spot.CanHome = hitboxCF0:ToObjectSpace(can.CFrame)
		end
		local lensAt = pivot + restAxis * (LENS_OUT * s)
		spot.Lens = ctx:Part({
			Name = "DJSpotLens",
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Size = Vector3.new(0.02, LENS_DIAMETER, LENS_DIAMETER) * s,
			CFrame = CFrame.lookAt(lensAt, lensAt + restAxis) * CFrame.Angles(0, math.pi / 2, 0), -- cylinder X = the can axis
			Transparency = 1,
			Parent = fx,
		})
		spot.Anchor = ctx:Part({
			Name = "DJSpotBeam",
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = CFrame.lookAt(lensAt, lensAt + restAxis),
			Transparency = 1,
			Parent = fx,
		})
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamStart"
		a0.Parent = spot.Anchor
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamEnd"
		a1.Position = Vector3.new(0, 0, -BEAM_LENGTH * s)
		a1.Parent = spot.Anchor
		local beam = Instance.new("Beam")
		beam.Name = "Cone"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true -- a camera-facing ribbon from narrow to wide reads as a light cone from every side
		beam.Width0 = BEAM_WIDTH0 * s
		beam.Width1 = BEAM_WIDTH1 * s
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.55, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Enabled = false
		beam.Parent = spot.Anchor
		spot.Beam = beam
		spot.HasBrightness = pcall(function() beam.Brightness = 1 end)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = LIGHT_ANGLE
		light.Range = math.min(60, LIGHT_RANGE * s)
		light.Brightness = 3
		light.Shadows = false
		light.Enabled = false
		light.Parent = spot.Anchor
		spot.Light = light
		spots[i] = spot
	end

	--..Show / hide the runtime show..--
	local shown = false
	local function Show(on)
		shown = on
		for _, deck in ipairs(decks) do
			if deck.Disc then
				deck.Disc.Transparency = on and 0 or 1
				for _, mark in ipairs(deck.Marks) do mark.Part.Transparency = on and 0 or 1 end
			end
		end
		for _, spot in ipairs(spots) do
			spot.Beam.Enabled = on
			spot.Light.Enabled = on
			spot.Lens.Transparency = on and 0 or 1
		end
		if not on then
			RestoreNeon()
			B.Live[model] = nil
		end
	end

	--..Music..--
	local sound, soundEntry = nil, nil
	local Sync -- (forward: a new Sound's Loaded calls it)

	local function TrackEntry()
		local list = FunAssets.Music
		if type(list) ~= "table" or #list == 0 then return nil end
		local index = (math.floor(tonumber(ctx:State("Track")) or 1) - 1) % #list + 1
		local entry = list[index]
		if type(entry) == "table" and entry.Id then return entry end
		return nil
	end

	local function EnsureSound(entry)
		if sound and soundEntry == entry and sound.Parent then return sound end
		if sound then sound:Destroy() end
		soundEntry = entry
		sound = ctx:Sound(hitbox, entry.Id, {
			Name = "DJBoothMusic",
			Looped = true,
			Volume = MUSIC_VOLUME,
			RollOffMinDistance = MUSIC_ROLLOFF_MIN,
			RollOffMaxDistance = MUSIC_ROLLOFF_MAX,
		})
		ctx:Connect(sound.Loaded, function() Sync() end)
		return sound
	end

	Sync = function()
		if not ctx:Alive() or Stale() then return end
		local playing = ctx:State("Playing") == true
		--.. the lobby music ducks while the local character is close to a playing booth
		local _, root = ctx:LocalCharacter()
		DuckVotes[model] = (playing and root ~= nil and (root.Position - hitbox.Position).Magnitude <= DUCK_RANGE) or nil
		ApplyDuck()
		--.. the Step sleeps beyond StepRange: take the show down instead of leaving frozen beams in the sky
		if shown and ctx:CameraDistance() > B.StepRange then Show(false) end

		local entry = playing and TrackEntry() or nil
		if not entry or Muted() or ctx:CameraDistance() > HEAR_RANGE then
			if sound and sound.IsPlaying then sound:Pause() end
			return
		end
		local track = EnsureSound(entry)
		local length = track.TimeLength
		if not track.IsLoaded or length <= 0 then return end -- its Loaded event syncs again
		local startedAt = tonumber(ctx:State("StartedAt")) or Kit.Now()
		local target = (Kit.Now() - startedAt) % length
		if not track.IsPlaying then
			track:Play()
			track.TimePosition = target
		else
			local drift = math.abs(track.TimePosition - target)
			if math.min(drift, length - drift) > MAX_DRIFT then track.TimePosition = target end
		end
	end

	--..Beat..--
	local env, avg, peak = 0, 0, 60
	local function Pulse(dt, beat)
		local loud = 0
		if sound and sound.Parent and sound.IsPlaying and sound.Volume > 0 then loud = sound.PlaybackLoudness end
		if loud > 1 then
			--.. an onset follower: the level above a slow average, against a slowly falling peak
			avg += (loud - avg) * math.min(1, dt * 2)
			peak = math.max(loud, peak * (1 - math.min(0.5, dt * 0.35)), 60)
			local floor = avg * 0.8
			local raw = math.clamp((loud - floor) / math.max(peak - floor, 1), 0, 1)
			env = raw > env and raw or math.max(raw, env - dt * 4)
			return env
		end
		env = 0
		return math.exp(-(beat % 1) * 5) -- a hit on every beat, decaying
	end

	--..Frame..--
	ctx:Step(function(dt, now)
		if Stale() then
			if shown then Show(false) end
			return
		end
		local playing = ctx:State("Playing") == true
		PoseArms(playing, dt)
		if not playing then
			if shown then Show(false) end
			return
		end
		if not shown then Show(true) end

		local startedAt = tonumber(ctx:State("StartedAt")) or now
		local t = now - startedAt
		local beat = t * BPM / 60
		local pulse = Pulse(dt, beat)

		--.. records: clockwise seen from above (a negative turn about +Y)
		local spin = CFrame.Angles(0, -t * RECORD_RPM / 60 * TAU, 0)
		for _, deck in ipairs(decks) do
			local cf = deck.Base * spin
			if deck.Rig then
				Kit.PoseRig(deck.Rig, cf)
			else
				deck.Disc.CFrame = cf * DISC_TURN
				deck.Disc.Color = Color3.fromHSV((t * HUE_SPEED + deck.Hue) % 1, 0.8, 0.55 + 0.45 * pulse)
				for _, mark in ipairs(deck.Marks) do mark.Part.CFrame = cf * mark.Offset end
			end
		end

		--.. spots: mirrored yaw (the beams cross in the middle), counter-phased floor <-> crowd nods
		local sway = math.sin(t * TAU / SPOT_YAW_PERIOD)
		for _, spot in ipairs(spots) do
			local yaw = SPOT_YAW * sway * spot.Sign
			local nod = 0.5 + 0.5 * math.sin(t * TAU / SPOT_TILT_PERIOD + spot.Phase)
			local tilt = floorTilt + (crowdTilt - floorTilt) * nod
			local axis = rot:VectorToWorldSpace(SpotAxis(tilt, yaw))
			local from = spot.Pivot + axis * (LENS_OUT * s)
			spot.Anchor.CFrame = CFrame.lookAt(from, from + axis)
			local colour = Color3.fromHSV((t * HUE_SPEED + spot.Hue) % 1, 0.75, 1)
			spot.Beam.Color = ColorSequence.new(colour)
			if spot.HasBrightness then spot.Beam.Brightness = 1 + 2 * pulse end
			spot.Light.Color = colour
			spot.Light.Brightness = 1.5 + 3 * pulse
			spot.Lens.Color = colour
			if spot.Can then
				spot.Can.CFrame = CFrame.new(spot.Pivot) * rot * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt - floorTilt, 0, 0) * spot.CanRel
				spot.Lens.CFrame = CFrame.lookAt(from, from + axis) * CFrame.Angles(0, math.pi / 2, 0)
			end
		end

		--.. the Neon parts dim between beats and flash on them
		for _, n in ipairs(neon) do
			n.Part.Transparency = math.min(0.95, n.T + (1 - pulse) * PULSE_DIM)
			if n.Cycle then n.Part.Color = Color3.fromHSV((t * HUE_SPEED * 1.5) % 1, 0.7, 1) end
		end

		local live = B.Live[model] or {}
		live.Pulse, live.Beat, live.At = pulse, beat, os.clock()
		B.Live[model] = live
	end)

	--..State..--
	ctx:OnState("Playing", Sync)
	ctx:OnState("Track", Sync)
	ctx:OnState("StartedAt", Sync)
	ctx:Connect(player:GetAttributeChangedSignal("MusicMuted"), Sync)
	ctx:Every(SYNC_EVERY, Sync)

	return function()
		B.Live[model] = nil
		DuckVotes[model] = nil
		ApplyDuck()
		RestoreNeon()
		--.. split parts go back to their built spot relative to where the build IS now (it may have just moved)
		local home = hitbox.CFrame
		for _, deck in ipairs(decks) do
			for p, rel in pairs(deck.Home or {}) do
				if p.Parent then p.CFrame = home * rel end
			end
		end
		for _, arm in ipairs(arms) do
			if arm.Part.Parent then arm.Part.CFrame = home * arm.Home end
		end
		for _, spot in ipairs(spots) do
			if spot.Can and spot.Can.Parent then spot.Can.CFrame = home * spot.CanHome end
		end
	end
end

return B

--[[
	GrandfatherClock  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24  fun-builds HomeOffice
	Client half of the GRANDFATHER CLOCK (fun-builds/notes/GrandfatherClock.md). There is no server half: the clock
	has no prompt and no state - it reads the game's own day/night clock, ServerScriptService.DayNightCycle:
	  DAY    Lighting.ClockTime runs 11:00 -> 16:00 over the 180 s day (the loop stops just short: ~15:59.8)
	  NIGHT  workspace.IsNight = true for the 10 s night. Since the BRIGHT NIGHT (2026-09-23) ClockTime is NOT moved at
	         night (it stays at the day's last value unless DayNightCycle has a NightClockTime attribute), so the dial
	         does not read ClockTime then: while IsNight is set the clock shows MIDNIGHT, whatever ClockTime says.
	  PENDULUM  Pendulum* swing about Pivot_PendulumPivot (the build's authored Z axis), State_PendulumSwing degrees
	            either way, PERIOD 2 s, phased from Kit.Now() so every client swings in step
	  TICK      a soft tock at each end of the swing (Sfx.ClockTick, alternating pitch) while the local character is
	            within TICK_RANGE studs
	  HANDS     HourHand* / MinuteHand* turn about Pivot_FaceCentre to show that time; Moon* (the sun/moon dial in
	            the arch, about Pivot_MoonCentre) turns once a day - sun up at noon, moon up at midnight.
	            The shown time only ever moves FORWARD: when the time jumps (night falls ~16:00 -> midnight, day
	            breaks midnight -> 11:00) the hands whirr round at SPIN_RATE hours per second with fast ticking
	  CHIME     every in-game hour (each 36 s by day) the clock strikes the hour: 1..12 strikes of Sfx.ClockChime,
	            STRIKE_GAP apart; a whirr that lands on (or, as the clock keeps running while the hands spin, up to
	            SNAP_HOURS past) the hour strikes it too: midnight strikes twelve as the zombies come, daybreak
	            strikes eleven. An hour struck while the last one is still ringing out waits its turn (queued).
	A positive angle turns clockwise as seen from the front: CFrame.Angles(0, 0, rad(angle)) about the pivot; the
	shipped poses are State_HourAngle / State_MinuteAngle / State_MoonAngle (the model shows 10:10, sun up).
	Everything is posed relative to the Hitbox; cleanup puts the parts back as shipped.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

--..Config..--
local LOCAL_FOLDER = "FunBuildLocal"
local PERIOD = 2                       -- s: one full swing there and back
local DEFAULT_SWING = 6                -- degrees either way
local DEFAULT_HOUR_SHIP, DEFAULT_MINUTE_SHIP, DEFAULT_MOON_SHIP = 305, 60, 0
local FACE_FALLBACK = Vector3.new(0, 6.25, -0.93)      -- authored (build_GrandfatherClock.py), if a pivot is missing
local PENDULUM_FALLBACK = Vector3.new(0, 5.12, -0.22)
local MOON_FALLBACK = Vector3.new(0, 7.5, -0.625)
local CHIME_FALLBACK = Vector3.new(0, 6.3, 0)
local SNAP_HOURS = 0.25                -- a forward step smaller than this is just time passing
local HOLD_HOURS = 1                   -- the clock less than this BEHIND the shown time: wait for it (never run back)
local SPIN_RATE = 5                    -- hours per second while whirring forward
local SPIN_TICK = 0.07                 -- s between whirr ticks
local LAND_EPS = 1e-3                  -- hours: float slack - a whirr landing a hair UNDER the hour lands on it
local STRIKE_GAP = 1.1                 -- s between strikes
local HOUR_PAUSE = 1.1                 -- s of extra silence before a queued hour starts striking
local MAX_STRIKES = 12
local MAX_QUEUED = 2                   -- hours that may wait to strike (the one ringing + the next)
local TICK_RANGE = 22                  -- studs (local character) for the tick-tock and the whirr
local CHIME_RANGE = 120                -- studs (camera): strikes only start within this
local TICK_VOLUME, CHIME_VOLUME = 0.22, 0.45
local TICK_PITCH = {1.0, 0.86}         -- tick, tock
local MAX_DT = 1 / 15
local WAKE_GAP = 0.5                   -- s without a Step (camera away) -> snap to the time, no sounds

local B = {}
B.Keys = {"GrandfatherClock"}
B.StepRange = 160

--..Helpers..--
local function LocalFolder()
	local folder = workspace:FindFirstChild(LOCAL_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = LOCAL_FOLDER
		folder.Archivable = false
		folder.Parent = workspace
	end
	return folder
end

--.. clockwise (seen from the front) about the pivot's Z axis
local function Turn(deg)
	return CFrame.Angles(0, 0, math.rad(deg))
end

--.. 0 -> 12, 13 -> 1 ...
local function Hour12(h)
	return (h - 1) % 12 + 1
end

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local rotation = Kit.Origin(model).Rotation
	local function PivotFrame(name, fallback)
		local pos = Kit.Pivot(model, name) or Kit.ToWorld(model, fallback)
		local cf = CFrame.new(pos) * rotation
		return cf, hitbox.CFrame:ToObjectSpace(cf)
	end
	local function Ship(attr, default)
		return tonumber(model:GetAttribute(attr)) or default
	end

	--..Rigs (each relative to its zero pose: the shipped parts turned back by their State_* angle)..--
	local home = {} -- [part] = CFrame relative to the Hitbox, restored on cleanup
	local function MakeRig(prefix, pivotCF, shipAngle)
		local parts = Kit.Parts(model, prefix)
		for _, p in ipairs(parts) do home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame) end
		return #parts > 0 and Kit.Rig(parts, pivotCF * Turn(shipAngle)) or nil
	end
	local pendCF, pendRel = PivotFrame("PendulumPivot", PENDULUM_FALLBACK)
	local faceCF, faceRel = PivotFrame("FaceCentre", FACE_FALLBACK)
	local moonCF, moonRel = PivotFrame("MoonCentre", MOON_FALLBACK)
	local swing = Ship("State_PendulumSwing", DEFAULT_SWING)
	local pendulum = MakeRig("Pendulum", pendCF, 0)
	local hourHand = MakeRig("HourHand", faceCF, Ship("State_HourAngle", DEFAULT_HOUR_SHIP))
	local minuteHand = MakeRig("MinuteHand", faceCF, Ship("State_MinuteAngle", DEFAULT_MINUTE_SHIP))
	local moon = MakeRig("Moon", moonCF, Ship("State_MoonAngle", DEFAULT_MOON_SHIP))

	--..Sounds (from the movement inside the hood)..--
	local chimePos = Kit.Pivot(model, "Chime") or Kit.ToWorld(model, CHIME_FALLBACK)
	local speaker = ctx:Part({Name = "GrandfatherClockMovement", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(chimePos), Transparency = 1, Parent = LocalFolder()})
	local function Sfx(name, volume, maxDistance)
		local id = type(FunAssets.Sfx) == "table" and FunAssets.Sfx[name] or nil
		if not id then return nil end
		return ctx:Sound(speaker, id, {Volume = volume, Looped = false, RollOffMinDistance = 6, RollOffMaxDistance = maxDistance})
	end
	local sfxTick = Sfx("ClockTick", TICK_VOLUME, 30)
	local chimes = {Sfx("ClockChime", CHIME_VOLUME, 80), Sfx("ClockChime", CHIME_VOLUME, 80)} -- two, so a strike rings on under the next
	local function Play(sound, speed)
		if not sound then return end
		pcall(function()
			sound.PlaybackSpeed = speed or 1
			sound.TimePosition = 0
			sound:Play()
		end)
	end

	--..Strikes (a queue: midnight's twelve outlast the 10 s night, so daybreak's eleven follow them)..--
	local queue = {}         -- strikes left per waiting hour, [1] = the one ringing now
	local nextStrike, strikeN = 0, 0
	local function Strike(hour, now)
		if ctx:CameraDistance() > CHIME_RANGE or #queue >= MAX_QUEUED then return end
		if #queue == 0 then nextStrike = math.max(nextStrike, now) end
		table.insert(queue, math.min(MAX_STRIKES, Hour12(hour)))
	end

	--..What turns, and by how much..--
	local shown = nil        -- the time on the dial in hours, continuous (only grows; wrapped when drawn)
	local jobs = {}          -- {Rig, Rel (pivot relative to the Hitbox), Angle = fn(now), Posed = last angle}
	local function Job(rig, rel, angle)
		if rig then table.insert(jobs, {Rig = rig, Rel = rel, Angle = angle}) end
	end
	Job(pendulum, pendRel, function(now) return swing * math.sin(now * math.pi * 2 / PERIOD) end)
	Job(hourHand, faceRel, function() return (shown % 12) * 30 end)
	Job(minuteHand, faceRel, function() return (shown % 1) * 360 end)
	Job(moon, moonRel, function() return ((shown - 12) % 24) * 15 end)

	--..Every frame..--
	local spinning = false
	local lastClock = -math.huge
	local lastSwingEnd = nil
	local lastSpinTick = 0
	local posedAt = nil      -- the Hitbox CFrame the parts were last posed against
	ctx:Step(function(dt, now)
		if not hitbox.Parent then return end
		local clock = os.clock()
		local woke = clock - lastClock > WAKE_GAP
		lastClock = clock
		dt = math.clamp(dt, 0, MAX_DT)

		--.. the shown time chases the game's time forward: Lighting.ClockTime by day, MIDNIGHT all night (the
		--.. bright night leaves ClockTime at ~15.997, so night falling reads as a whirr 16 -> 24 onto midnight)
		local target
		if workspace:GetAttribute("IsNight") == true then
			target = 0
		else
			target = (tonumber(Lighting.ClockTime) or 12) % 24
		end
		if woke or shown == nil then
			shown, spinning = target, false
			table.clear(queue)
		else
			local ahead = (target - shown) % 24
			if ahead > 24 - HOLD_HOURS then
				--.. the clock is a little behind the dial: hold
			elseif ahead <= SNAP_HOURS and not spinning then
				local before = shown
				shown += ahead
				if math.floor(shown) > math.floor(before) then Strike(math.floor(shown) % 24, now) end
			else
				spinning = true
				local step = math.min(ahead, SPIN_RATE * dt)
				shown += step
				if now - lastSpinTick >= SPIN_TICK and ctx:Near(TICK_RANGE) then
					lastSpinTick = now
					Play(sfxTick, 1.5)
				end
				if ahead - step <= 1e-6 then
					--.. landed. The clock kept running while the hands spun (daybreak lands ~11:04), so anything
					--.. up to SNAP_HOURS past an hour strikes it; a float hair under the hour lands ON it
					spinning = false
					local h = math.floor(shown + LAND_EPS)
					if h > shown then shown = h end
					if shown - h < SNAP_HOURS then Strike(h % 24, now) end
				end
			end
			if shown > 240 then shown -= 240 end -- keep the number small (a multiple of 24 and 12)
		end

		--.. the pendulum's tick at each end of its swing (angle = swing * sin(2 pi t / PERIOD))
		local swingEnd = math.floor((now - PERIOD * 0.25) / (PERIOD * 0.5))
		if lastSwingEnd and swingEnd ~= lastSwingEnd and not woke and ctx:Near(TICK_RANGE) then
			Play(sfxTick, TICK_PITCH[swingEnd % 2 + 1])
		end
		lastSwingEnd = swingEnd

		--.. strikes
		if queue[1] and now >= nextStrike then
			queue[1] -= 1
			strikeN += 1
			nextStrike = now + STRIKE_GAP
			Play(chimes[strikeN % 2 + 1], 1)
			if queue[1] <= 0 then
				table.remove(queue, 1)
				if queue[1] then nextStrike += HOUR_PAUSE end -- a beat of silence between two hours
			end
		end

		--.. pose (the pendulum every frame, the hands / moon only when they moved)
		local hb = hitbox.CFrame
		local moved = hb ~= posedAt
		posedAt = hb
		for _, j in ipairs(jobs) do
			local angle = j.Angle(now)
			if moved or j.Posed == nil or math.abs(j.Posed - angle) > 0.01 then
				Kit.PoseRig(j.Rig, hb * j.Rel * Turn(angle))
				j.Posed = angle
			end
		end
	end)

	--..Cleanup: every rigged part back as shipped, relative to where the build IS now..--
	return function()
		if not hitbox.Parent then return end
		for part, rel in pairs(home) do
			if part.Parent then part.CFrame = hitbox.CFrame * rel end
		end
	end
end

return B

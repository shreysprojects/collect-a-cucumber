--!nocheck
return function(env)
	local game, workspace, Instance, Vector3, CFrame, Color3, Vector2, UDim2, NumberRange, NumberSequence, NumberSequenceKeypoint, ColorSequence, Enum, typeof, task, require, warn, os = env.game, env.workspace, env.Instance, env.Vector3, env.CFrame, env.Color3, env.Vector2, env.UDim2, env.NumberRange, env.NumberSequence, env.NumberSequenceKeypoint, env.ColorSequence, env.Enum, env.typeof, env.task, env.require, env.warn, env.os
--[[
	Microwave  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the working MICROWAVE (server half: ServerStorage.FunBehaviours.Microwave; model =
	fun-builds/models/build_Microwave.py). Everything is drawn from the server's state + Kit.Now():
	  * DOOR (Fun_Door, signed server time: > 0 opened at, < 0 closed at): the Door* parts swing about the
	    vertical axis through Pivot_DoorHinge by State_DoorOpen degrees (negative: the free edge swings out to
	    the front), eased; they stop colliding locally while off their seat. Opening lights the cavity softly.
	  * HEAT (Fun_Heat = start time, 0 idle; HEAT_TIME long): the cavity lamp (CavityLight) turns Neon, a warm
	    PointLight fills the cavity and tints the dark window amber, the Turntable* parts (plate, mug of cocoa)
	    make exactly one turn about Pivot_Turntable, the hum loops and the LCD counts down 0:05 .. 0:01.
	  * DONE (Fun_Done = time the last heat finished): a Ding, a steam puff over the door (Pivot_Steam) and a
	    blinking END on the LCD for a few seconds; otherwise the LCD shows the in-game clock (Lighting.ClockTime).
	  * the Start / door-release buttons dip in when their prompt is used.
	Sounds: FunAssets.Sfx.MicrowaveHum / MicrowaveBeep (dedicated, natural pitch; HumLoop / Click only if a key is ever
	dropped), Ding, DoorOpen, DoorClose - each started at the right point of its clip (SOUNDS below) so the squeak, the
	clunk and the ding land on the animation.
	A client streaming in mid-heat picks the spin, light and countdown up where they are, silently. The state resetting
	to 0 (the server restarting the behaviour after a move / mend) is silent too: no clunk, no button press.
	Everything touched (CFrame, CanCollide, Material, Color) is restored on cleanup relative to where the build IS.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))
local FunAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunAssets"))

--..Config..--
local HEAT_TIME = 5                                   -- s; must match the server half
local SPIN = 2 * math.pi / HEAT_TIME                  -- rad/s: one full turn per heat, so it ends where it began
local SWING_TIME = 0.45                               -- s per door swing
local OVERSHOOT = 1.2                                 -- ease-out-back of the opening swing
local END_SHOW = 4                                    -- s the LCD blinks END after a heat
local PRESS_TIME = 0.18                               -- s a keypad button stays pressed
local PRESS_DEPTH = 0.035                             -- authored studs a button dips in
local HEAT_LIGHT = {Color = Color3.fromRGB(255, 190, 110), Brightness = 2.2, Strip = Color3.fromRGB(255, 214, 140)}
local OPEN_LIGHT = {Color = Color3.fromRGB(255, 242, 222), Brightness = 0.9, Strip = Color3.fromRGB(255, 244, 225)}
local WINDOW_GLOW = Color3.fromRGB(125, 92, 48)       -- the dark window while the cavity glows
local LCD_IDLE = Color3.fromRGB(95, 210, 130)
local LCD_ACTIVE = Color3.fromRGB(140, 255, 170)
local STEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local STEAM_BURST = 14
local STEAM_TRICKLE = 1.2                             -- s of gentle steam after the burst

--..Sounds (fun-builds/assets/ASSETS.md)..--
--.. Speed = PlaybackSpeed, Skip = s of the clip jumped over on Play, Hit = s into the clip of its audible moment
local SFX = FunAssets.Sfx
local SOUNDS = {
	Hum = SFX.MicrowaveHum and {Id = SFX.MicrowaveHum, Speed = 1, Volume = 0.22} -- magnetron hum, 10.6 s loop
		or {Id = SFX.HumLoop, Speed = 1.25, Volume = 0.2},
	Beep = SFX.MicrowaveBeep and {Id = SFX.MicrowaveBeep, Speed = 1, Volume = 0.35} -- 0.12 s keypad beep
		or {Id = SFX.Click, Speed = 1.4, Volume = 0.35},
	Ding = {Id = SFX.Ding, Speed = 1, Volume = 0.7, Skip = 0.15},        -- desk bell: the strike is at 0.2 s
	Open = {Id = SFX.DoorOpen, Speed = 1.1, Volume = 0.45, Skip = 0.5},  -- squeak at 0.6-0.9 s -> just after the release
	Close = {Id = SFX.DoorClose, Speed = 1.15, Volume = 0.5, Hit = 0.25}, -- clunk at 0.25 s (a smaller, lighter door)
}
--.. s into a closing swing to start the close sound, so its clunk lands as the door meets the case
local CLOSE_START = math.max(0, SWING_TIME - SOUNDS.Close.Hit / SOUNDS.Close.Speed)

local B = {}
B.Keys = {"Microwave"}
B.StepRange = 140

--..Helpers..--
local function EaseOutBack(p)
	local q = p - 1
	return 1 + (OVERSHOOT + 1) * q * q * q + OVERSHOOT * q * q
end

local function EaseInOutCubic(p)
	if p < 0.5 then return 4 * p * p * p end
	local q = -2 * p + 2
	return 1 - q * q * q / 2
end

local function ClockText()
	local minutes = math.floor((Lighting.ClockTime % 24) * 60)
	local h, m = math.floor(minutes / 60), minutes % 60
	h = h % 12
	if h == 0 then h = 12 end
	return string.format("%d:%02d", h, m)
end

--.. the face of `part` that looks along the world direction `dir` (a merged-mesh install may turn a part's own axes)
local function FaceToward(part, dir)
	local cf = part.CFrame
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, pair in ipairs({
		{Enum.NormalId.Front, cf.LookVector}, {Enum.NormalId.Back, -cf.LookVector},
		{Enum.NormalId.Right, cf.RightVector}, {Enum.NormalId.Left, -cf.RightVector},
		{Enum.NormalId.Top, cf.UpVector}, {Enum.NormalId.Bottom, -cf.UpVector},
	}) do
		local d = pair[2]:Dot(dir)
		if d > bestDot then best, bestDot = pair[1], d end
	end
	return best
end

local function Holder(ctx, name, cf)
	return ctx:Part({Name = name, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf})
end

--.. a Sound for one SOUNDS entry (extra props on top)
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

--..Behaviour..--
function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local s = ctx.Scale
	local origin = Kit.Origin(model)

	local home = {}     -- [part] = CFrame relative to the Hitbox (cleanup + presses)
	local collide = {}  -- [part] = authored CanCollide
	local function Track(p)
		home[p] = hitbox.CFrame:ToObjectSpace(p.CFrame)
		collide[p] = p.CanCollide
	end

	--..Door rig..--
	local doorParts = Kit.Parts(model, "Door")
	local hinge = Kit.Pivot(model, "DoorHinge")
	local door
	if #doorParts > 0 and hinge then
		local hingeCF = CFrame.new(hinge) * origin.Rotation
		for _, p in ipairs(doorParts) do Track(p) end
		door = {
			Parts = doorParts, Rig = Kit.Rig(doorParts, hingeCF), HingeRel = hitbox.CFrame:ToObjectSpace(hingeCF),
			OpenDeg = tonumber(model:GetAttribute("State_DoorOpen")) or -100,
			Open = false, At = 0, From = 0, Angle = 0, Settled = true, Primed = false, Solid = true,
		}
	end

	--..Turntable rig..--
	local tableParts = Kit.Parts(model, "Turntable")
	local tableAt = Kit.Pivot(model, "Turntable")
	local turntable
	if #tableParts > 0 and tableAt then
		local pivotCF = CFrame.new(tableAt) * origin.Rotation
		for _, p in ipairs(tableParts) do Track(p) end
		turntable = {Rig = Kit.Rig(tableParts, pivotCF), PivotRel = hitbox.CFrame:ToObjectSpace(pivotCF), Base = 0, Angle = 0}
	end

	--..Buttons..--
	local buttons = {}
	for _, name in ipairs({"BtnStart", "BtnOpen"}) do
		local p = Kit.Part(model, name)
		if p then
			Track(p)
			buttons[name] = {Part = p, Until = 0, Down = false}
		end
	end
	local function Press(name)
		local b = buttons[name]
		if b then b.Until = os.clock() + PRESS_TIME end
	end

	--..Lamp, window, display..--
	local strip = Kit.Part(model, "CavityLight")
	local stripMat, stripColor = strip and strip.Material, strip and strip.Color
	local window = Kit.Part(model, "DoorWindow")
	local windowColor = window and window.Color

	local lightAt = Kit.Pivot(model, "CavityLight") or hitbox.Position
	local cavity = Holder(ctx, "MicrowaveCavity", CFrame.new(lightAt))
	local light = Instance.new("PointLight")
	light.Range = 4.5 * s
	light.Shadows = false
	light.Enabled = false
	light.Parent = cavity
	local hum = MakeSfx(ctx, cavity, SOUNDS.Hum, {Looped = true, RollOffMaxDistance = 40})
	local ding = MakeSfx(ctx, cavity, SOUNDS.Ding, {RollOffMaxDistance = 70})
	local openSound = MakeSfx(ctx, cavity, SOUNDS.Open)
	local closeSound = MakeSfx(ctx, cavity, SOUNDS.Close)
	local beep = MakeSfx(ctx, cavity, SOUNDS.Beep)

	local label
	local display = Kit.Part(model, "Display")
	if display then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "MicrowaveDisplay"
		gui.Face = FaceToward(display, origin.LookVector) -- the side facing the build's front (-Z authored)
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 150
		gui.LightInfluence = 0
		label = Instance.new("TextLabel")
		label.Name = "Digits"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.52)
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Font = Enum.Font.Arcade
		label.TextScaled = true
		label.TextColor3 = LCD_IDLE
		label.Text = ClockText()
		label.Parent = gui
		gui.Parent = display
		ctx:Add(gui)
	end

	--..Steam (a burst over the door when it dings)..--
	local steamAt = model:GetAttribute("Pivot_Steam")
	if typeof(steamAt) ~= "Vector3" then steamAt = Vector3.new(0.48, 4.1, -1.1) end
	local steamHolder = ctx:Part({Name = "MicrowaveSteam", Transparency = 1, Size = Vector3.new(1.0 * s, 0.1 * s, 0.3 * s),
		CFrame = Kit.CFrameToWorld(model, CFrame.new(steamAt))})
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Steam"
	steam.Texture = STEAM_TEXTURE
	steam.Color = ColorSequence.new(Color3.fromRGB(250, 250, 250))
	steam.LightEmission = 0.2
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3 * s), NumberSequenceKeypoint.new(1, 1.8 * s)})
	steam.Lifetime = NumberRange.new(1.0, 1.8)
	steam.Speed = NumberRange.new(1.5 * s, 3 * s)
	steam.SpreadAngle = Vector2.new(22, 22)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Acceleration = Vector3.new(0, 1.5 * s, 0)
	steam.Drag = 2
	steam.Rotation = NumberRange.new(0, 360)
	steam.RotSpeed = NumberRange.new(-40, 40)
	steam.Rate = 8
	steam.Enabled = false
	steam.Parent = steamHolder
	local steamUntil = 0

	--..State..--
	--.. -1 = nothing seen yet: the FIRST value (0 while idle) must still get through the early returns below and
	--.. prime them, or the first real heat after a stream-in / move / mend would end with no ding. Every use checks > 0.
	local heatStart, doneAt = -1, -1
	local primedHeat, primedDone = false, false

	local function Heating(now)
		return heatStart > 0 and now >= heatStart and now < heatStart + HEAT_TIME
	end

	ctx:OnState("Door", function(v)
		if not door then return end
		v = tonumber(v) or 0
		local open, at = v > 0, math.abs(v)
		if door.Primed and open == door.Open and at == door.At then return end
		--.. first look (stream-in / restart: a swing under way plays on) or a reset to 0 (the server restarting the
		--.. behaviour after a move / mend): silent, no clunk, no button press
		local quiet = not door.Primed or at == 0
		door.From = quiet and (open and 0 or door.OpenDeg) or door.Angle
		if at == 0 then door.From = 0 end -- 0 = shut: no swing at all
		door.Primed = true
		door.Open, door.At, door.Settled, door.Quiet, door.Thud = open, at, false, quiet, open or quiet
		if not quiet then
			Press("BtnOpen")
			if open then PlayFrom(openSound, SOUNDS.Open) end
		end
	end)

	ctx:OnState("Heat", function(v)
		v = tonumber(v) or 0
		if v == heatStart then return end
		if turntable then
			if v > 0 then
				turntable.Base = turntable.Angle -- a new heat turns on from wherever the plate stopped
			else
				turntable.Base = turntable.Angle % (2 * math.pi)
			end
		end
		heatStart = v
		if v > 0 and primedHeat then
			Press("BtnStart")
			PlayFrom(beep, SOUNDS.Beep)
		end
		primedHeat = true
	end)

	ctx:OnState("Done", function(v)
		v = tonumber(v) or 0
		if v == doneAt then return end
		doneAt = v
		if primedDone and v > 0 and Kit.Now() - v < 1.5 then
			PlayFrom(ding, SOUNDS.Ding)
			pcall(function() steam:Emit(STEAM_BURST) end)
			steamUntil = os.clock() + STEAM_TRICKLE
		end
		primedDone = true
	end)

	--..Every frame..--
	local lastText, lastLit
	local clockText, nextClock = ClockText(), 0
	local wasHeating = false
	ctx:Step(function(_, now)
		if not hitbox.Parent then return end
		local base = hitbox.CFrame
		local heating = Heating(now)

		--.. door swing
		if door and not door.Settled then
			local p = math.clamp((now - door.At) / SWING_TIME, 0, 1)
			local target = door.Open and door.OpenDeg or 0
			local e = door.Open and EaseOutBack(p) or EaseInOutCubic(p)
			door.Angle = door.From + (target - door.From) * e
			Kit.PoseRig(door.Rig, base * door.HingeRel * CFrame.Angles(0, math.rad(door.Angle), 0))
			local solid = math.abs(door.Angle) < 1
			if solid ~= door.Solid then
				door.Solid = solid
				for _, part in ipairs(door.Parts) do
					if part.Parent then part.CanCollide = solid and collide[part] or false end
				end
			end
			if not door.Open and not door.Thud and now - door.At >= CLOSE_START then
				door.Thud = true -- started early: the clip's clunk lands as the swing ends
				PlayFrom(closeSound, SOUNDS.Close)
			end
			if p >= 1 then door.Settled = true end
		end

		--.. turntable: one turn per heat
		if turntable and (heating or wasHeating) then
			if heating then
				turntable.Angle = turntable.Base + (now - heatStart) * SPIN
			elseif heatStart > 0 and now >= heatStart + HEAT_TIME then
				turntable.Angle = turntable.Base + 2 * math.pi -- ran its time: exactly one turn, back where it began
			end
			Kit.PoseRig(turntable.Rig, base * turntable.PivotRel * CFrame.Angles(0, turntable.Angle, 0))
		end

		--.. hum
		if heating ~= wasHeating then
			if heating then hum:Play() else hum:Stop() end
		end
		wasHeating = heating

		--.. lamp: warm while heating, soft while the door is open
		local doorOpen = door ~= nil and door.Open
		local lit = heating and "heat" or (doorOpen and "open" or nil)
		if lit ~= lastLit then
			lastLit = lit
			local look = lit == "heat" and HEAT_LIGHT or (lit == "open" and OPEN_LIGHT or nil)
			light.Enabled = look ~= nil
			if look then
				light.Color = look.Color
				light.Brightness = look.Brightness
			end
			if strip and strip.Parent then
				strip.Material = look and Enum.Material.Neon or stripMat
				strip.Color = look and look.Strip or stripColor
			end
			if window and window.Parent then window.Color = lit == "heat" and WINDOW_GLOW or windowColor end
		end

		--.. buttons
		local clock = os.clock()
		for _, b in pairs(buttons) do
			local down = clock < b.Until
			if down ~= b.Down and b.Part.Parent then
				b.Down = down
				--.. dips along the build's +Z (into the panel), whatever the part's own axes are
				b.Part.CFrame = base * home[b.Part] + base:VectorToWorldSpace(Vector3.new(0, 0, down and PRESS_DEPTH * s or 0))
			end
		end

		--.. steam trickle after the burst
		local trickle = clock < steamUntil
		if steam.Enabled ~= trickle then steam.Enabled = trickle end

		--.. LCD
		if label then
			local text, color
			if heatStart > 0 and now < heatStart + HEAT_TIME then
				text = string.format("0:%02d", math.clamp(math.ceil(heatStart + HEAT_TIME - now), 1, HEAT_TIME))
				color = LCD_ACTIVE
			elseif doneAt > 0 and now - doneAt < END_SHOW then
				text = (math.floor((now - doneAt) * 2) % 2 == 0) and "END" or ""
				color = LCD_ACTIVE
			else
				if clock >= nextClock then -- the in-game clock, read twice a second
					nextClock = clock + 0.5
					clockText = ClockText()
				end
				text = clockText
				color = LCD_IDLE
			end
			if text ~= lastText then
				lastText = text
				label.Text = text
				label.TextColor3 = color
			end
		end
	end)

	--..Cleanup: rest pose relative to where the build IS now, plain lamp + window..--
	return function()
		if strip and strip.Parent then
			strip.Material = stripMat
			strip.Color = stripColor
		end
		if window and window.Parent then window.Color = windowColor end
		if not hitbox.Parent then return end
		local broken = Kit.IsBroken(model) -- BuildHealthService owns collisions while Broken
		for p, rel in pairs(home) do
			if p.Parent then
				p.CFrame = hitbox.CFrame * rel
				if not broken then p.CanCollide = collide[p] end
			end
		end
	end
end

return B

end

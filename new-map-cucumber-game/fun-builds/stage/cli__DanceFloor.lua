--[[
	DanceFloor  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the light-up dance floor (fun-builds/CONTRACT.md, package DJBooth). No server half: nothing is
	shared state - the floor follows the DJ booths' replicated state and every client derives the same picture
	from Kit.Now().
	  * tiles: the 16 Neon parts Tile_r<row>_c<col> (row 0 = the back, +Z; col 0 = the +X edge - the prop's grid
	    contract). Idle they sit DIM (State_Dim = Transparency 0.45) in the shipped checkerboard, the lit half
	    swapping every IDLE_SWAP s. While any DJBooth build within BOOTH_RANGE studs has Fun_Playing = true they go
	    ON (State_On) and flash on its beat, cycling a pattern every PATTERN_BEATS beats:
	      1 checker swap   the lit half swaps every beat, hues stepping round the prop's CYCLE
	      2 rainbow wave   a hue wave rolling diagonally across the floor
	      3 ripple         a ring of light running out from the centre on every beat
	    The beat is the booth client's loudness pulse (DJBooth.Live, same Lua VM) while that booth is on screen,
	    else a fixed 120 BPM grid from its Fun_StartedAt. The tile under any character glows brighter
	    (footsteps). PowerLight (the controller dot) turns lime while the music plays
	  * dancing: while the LOCAL character stands on a floor a small bottom-centre "DANCE" button shows (above the
	    hotbar; key G). It toggles a looped R15 dance on the local Animator (507771019 / 507776043 / 507777268, the
	    next one each time it starts; the character's own Animator replicates it to everyone). The dance stops on
	    STOP, walking (MoveDirection > 0.1), jumping, sitting, dying or stepping off the floor. One controller +
	    one GUI serve every floor on this client
	Cleanup restores every tile's Color / Material / Transparency (a broken floor keeps the server's 0.65 fade).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local ButtonFX = nil -- the HUD's press pop; required when the GUI is first built (its SoundController waits on Assets.Sounds)

local player = Players.LocalPlayer

--..Config..--
local BOOTH_BASE = "DJBooth"
local BOOTH_RANGE = 60             -- studs hitbox <-> hitbox
local BOOTH_SCAN = 0.5             -- s between looks for a playing booth
local BPM = 120                    -- fallback beat when the booth's client pulse is not live
local LIVE_MAX_AGE = 0.25          -- s: an older DJBooth.Live entry is stale (that booth's Step is asleep)
local PATTERN_BEATS = 8
local IDLE_SWAP = 2                -- s between the idle checkerboard swaps
local WRITE_HZ = 30                -- tile writes per second at most
local FOOT_SCAN = 0.1              -- s between character-on-floor checks
local BROKEN_T = 0.65              -- BuildHealthService BROKEN_TRANSPARENCY
local GRID = 4
local PITCH = 1.74                 -- authored tile centre -> tile centre
local EDGE = 2.61                  -- authored centre of the outer tiles
local TILE_REACH = 3.45            -- authored |x|,|z| still over the tile field
local STAND_REACH = 3.9            -- authored |x|,|z| still on the floor (the frame rails count)
local TILE_TOP = 0.34              -- authored walking surface
local CYCLE_HUES = {330 / 360, 275 / 360, 195 / 360, 95 / 360} -- the prop's CYCLE: neon pink, purple, cyan, lime
local GLOW = { -- the prop's shipped lit hexes, same CYCLE order (kept deep: brighter Neon washes out)
	Color3.fromHex("731e46"), Color3.fromHex("512973"), Color3.fromHex("1c5f76"), Color3.fromHex("477323"),
}
local DARK = Color3.fromHex("070911")
local POWER_ON = Color3.fromHSV(95 / 360, 0.8, 0.9)
local DANCES = {"rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268"}
local DANCE_KEY = Enum.KeyCode.G
local DANCE_ACTION = "FunDanceFloorDance"

--..GUI look (the HUD's buttons)..--
local GREEN = ColorSequence.new(Color3.fromRGB(69, 255, 0), Color3.fromRGB(157, 255, 36))
local RED = ColorSequence.new(Color3.fromRGB(230, 30, 30), Color3.fromRGB(255, 84, 60))
local OUTLINE = Color3.fromRGB(22, 24, 30)
local BUTTON_W, BUTTON_H = 150, 52 -- px before the UIScale
local HOTBAR_BOTTOM, HOTBAR_GAP = 10, 14 -- HotbarClient: bar 10 px off the bottom, slots clamp(7.5 % of height, 44, 64)

local B = {}
B.StepRange = 200

--..DJ booths (one list shared by every floor, rescanned at most once a second)..--
local boothList, boothScanAt = {}, -math.huge
local function Booths()
	if os.clock() - boothScanAt < 1 then return boothList end
	boothScanAt = os.clock()
	table.clear(boothList)
	for _, m in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do
		if m:IsA("Model") and m:IsDescendantOf(workspace) and Kit.Split(Kit.Key(m)) == BOOTH_BASE then
			table.insert(boothList, m)
		end
	end
	return boothList
end

--.. the DJBooth client module (its Live table carries each on-screen booth's loudness pulse); looked up lazily,
--.. the folder may deliver it after this one
local DJ, djLookAt = nil, -math.huge
local function DJModule()
	if DJ then return DJ end
	if os.clock() - djLookAt < 2 then return nil end
	djLookAt = os.clock()
	local m = script.Parent and script.Parent:FindFirstChild(BOOTH_BASE)
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then DJ = mod end
	end
	return DJ
end

--.. beats since the booth's track started + a 0..1 pulse
local function BeatOf(booth, now)
	local dj = DJModule()
	local live = dj and type(dj.Live) == "table" and dj.Live[booth]
	if live and os.clock() - (live.At or 0) < LIVE_MAX_AGE then return live.Beat, live.Pulse end
	local beat = (now - (tonumber(Kit.State(booth, "StartedAt")) or 0)) * BPM / 60
	return beat, math.exp(-(beat % 1) * 5)
end

--..Dancing (one controller + one GUI for every floor: the local character stands on one floor at a time)..--
local Dance = {
	Floors = {},   -- [floor model] = true while the local character stands on it
	Index = 0,     -- the DANCES entry played last
	Track = nil,   -- the playing AnimationTrack
	Conns = {},
	Gui = nil, Holder = nil, Button = nil, Label = nil, Gradient = nil, Scale = nil,
	Bound = false,
}

local function OnAnyFloor()
	return next(Dance.Floors) ~= nil
end

local RefreshGui -- (forward)

local function StopDance()
	for _, c in ipairs(Dance.Conns) do c:Disconnect() end
	table.clear(Dance.Conns)
	local track = Dance.Track
	Dance.Track = nil
	if track then
		pcall(function() track:Stop(0.25) end)
		task.delay(0.5, function() pcall(function() track:Destroy() end) end)
	end
	RefreshGui()
end

local function StartDance()
	if Dance.Track then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	Dance.Index = Dance.Index % #DANCES + 1
	local animation = Instance.new("Animation")
	animation.AnimationId = DANCES[Dance.Index]
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		warn("[DanceFloor] dance " .. DANCES[Dance.Index] .. " failed to load: " .. tostring(track))
		return
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.25)
	Dance.Track = track
	--.. walking, jumping, sitting, dying or leaving the floor ends it
	table.insert(Dance.Conns, RunService.Heartbeat:Connect(function()
		if not humanoid.Parent or humanoid.Health <= 0 or humanoid.MoveDirection.Magnitude > 0.1
			or humanoid.Jump or humanoid.SeatPart ~= nil or not OnAnyFloor() then
			StopDance()
		end
	end))
	table.insert(Dance.Conns, humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then StopDance() end
	end))
	RefreshGui()
end

local function ToggleDance()
	if Dance.Button and ButtonFX then pcall(ButtonFX.Press, Dance.Button) end
	if Dance.Track then StopDance() else StartDance() end
end

local function LayoutGui()
	if not Dance.Holder then return end
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local slot = math.clamp(math.floor(size.Y * 0.075), 44, 64)
	Dance.Holder.Position = UDim2.new(0.5, 0, 1, -(HOTBAR_BOTTOM + slot + HOTBAR_GAP))
	Dance.Scale.Scale = math.clamp(math.min(size.X / 1100, size.Y / 640), 0.75, 1.25)
end

local function BuildGui()
	if Dance.Gui and Dance.Gui.Parent then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "FunDanceGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = false

	--.. the holder carries the viewport UIScale; the button inside is free for ButtonFX's own press scale
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local button = Instance.new("TextButton")
	button.Name = "Dance"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = OUTLINE
	stroke.Thickness = 3
	stroke.Parent = button
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = GREEN
	gradient.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "DANCE"
	label.TextSize = 28
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = button
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = OUTLINE
	textStroke.Thickness = 2.5
	textStroke.Parent = label

	--.. the keyboard hint in the corner
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(1, 0)
	key.Position = UDim2.new(1, -6, 0, 4)
	key.Size = UDim2.fromOffset(18, 16)
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.FredokaOne
	key.Text = "G"
	key.TextSize = 14
	key.TextColor3 = Color3.new(1, 1, 1)
	key.Visible = UserInputService.KeyboardEnabled
	key.Parent = button
	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = OUTLINE
	keyStroke.Thickness = 1.5
	keyStroke.Parent = key

	button.Activated:Connect(ToggleDance)
	local fxModule = Modules:FindFirstChild("ButtonFX")
	if fxModule and not ButtonFX then
		local ok, mod = pcall(require, fxModule)
		if ok and type(mod) == "table" then ButtonFX = mod end
	end
	if ButtonFX then pcall(ButtonFX.Prepare, button) end

	Dance.Gui, Dance.Holder, Dance.Button, Dance.Label, Dance.Gradient, Dance.Scale = gui, holder, button, label, gradient, scale
	LayoutGui()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(LayoutGui) end
	gui.Parent = playerGui
end

local function BindKey(on)
	if on == Dance.Bound then return end
	Dance.Bound = on
	if on then
		ContextActionService:BindAction(DANCE_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then ToggleDance() end
			return Enum.ContextActionResult.Sink
		end, false, DANCE_KEY)
	else
		ContextActionService:UnbindAction(DANCE_ACTION)
	end
end

RefreshGui = function()
	local on = OnAnyFloor()
	if on then BuildGui() end
	BindKey(on)
	if not Dance.Gui then return end
	Dance.Gui.Enabled = on
	local dancing = Dance.Track ~= nil
	Dance.Label.Text = dancing and "STOP" or "DANCE"
	Dance.Gradient.Color = dancing and RED or GREEN
end

local function SetOnFloor(model, on)
	on = on and true or nil
	if Dance.Floors[model] == on then return end
	Dance.Floors[model] = on
	RefreshGui()
end

--..Tile patterns (playing)..--
local function PatternColour(tile, beat, pulse, pattern)
	if pattern == 1 then -- checker swap
		local b = math.floor(beat)
		if (tile.R + tile.C) % 2 ~= b % 2 then return DARK end
		local hue = CYCLE_HUES[(tile.R + tile.C + math.floor(b / 2)) % 4 + 1]
		return Color3.fromHSV(hue, 0.85, 0.5 + 0.5 * pulse)
	elseif pattern == 2 then -- rainbow wave, rolling diagonally
		return Color3.fromHSV((beat * 0.125 - (tile.R + tile.C) * 0.08) % 1, 0.8, 0.45 + 0.5 * pulse)
	end
	-- ripple: a ring running out from the centre on every beat (cell distances 0.71 / 1.58 / 2.12)
	local ring = (beat % 1) * 2.6
	local k = math.max(0, 1 - math.abs(tile.D - ring) * 1.5)
	return Color3.fromHSV((math.floor(beat) * 0.21) % 1, 0.85, 0.08 + 0.92 * k * (0.6 + 0.4 * pulse))
end

--..Behaviour..--
function B.Client(model, ctx)
	local s = ctx.Scale
	local hitbox = Kit.Hitbox(model)
	local origin = Kit.Origin(model)
	local onT = tonumber(model:GetAttribute("State_On")) or 0
	local dimT = tonumber(model:GetAttribute("State_Dim")) or 0.45

	local function Settle(t)
		if Kit.IsBroken(model) and t < 1 then return math.max(t, BROKEN_T) end
		return t
	end

	--..Tiles..--
	local tiles = {}
	local byCell = {}
	for r = 0, GRID - 1 do
		for c = 0, GRID - 1 do
			local p = Kit.Part(model, string.format("Tile_r%d_c%d", r, c))
			if p then
				local tile = {
					Part = p, R = r, C = c,
					Color = p.Color, Material = p.Material, T = p.Transparency,
					Glow = GLOW[(r + c) % 4 + 1],
					Hue = CYCLE_HUES[(r + c) % 4 + 1],
					D = math.sqrt((r - 1.5) ^ 2 + (c - 1.5) ^ 2),
				}
				table.insert(tiles, tile)
				byCell[r * GRID + c] = tile
			end
		end
	end
	local power = Kit.Part(model, "PowerLight")
	local powerColour = power and power.Color

	local function Write(tile, colour, t)
		if tile.LastColor ~= colour then
			tile.Part.Color = colour
			tile.LastColor = colour
		end
		if tile.LastT ~= t then
			tile.Part.Transparency = t
			tile.LastT = t
		end
	end

	--..The nearest playing booth..--
	local booth = nil
	local function Scan()
		local best, bestD = nil, BOOTH_RANGE
		for _, m in ipairs(Booths()) do
			if m.Parent and Kit.State(m, "Playing") == true and not Kit.IsBroken(m) then
				local hb = Kit.Hitbox(m)
				local d = hb and (hb.Position - hitbox.Position).Magnitude
				if d and d <= bestD then best, bestD = m, d end
			end
		end
		booth = best
	end
	Scan()
	ctx:Every(BOOTH_SCAN, Scan)

	--..Who stands where (footstep glow + the local dance button)..--
	local occupied = {} -- [tile] = true
	local function FootScan()
		table.clear(occupied)
		local localOn = false
		if not Kit.IsBroken(model) then
			for _, other in ipairs(Players:GetPlayers()) do
				local character = other.Character
				local humanoid, root = Kit.CharacterParts(character)
				if humanoid and root and humanoid.Health > 0 then
					local lp = origin:PointToObjectSpace(root.Position)
					local ax, az = lp.X / s, lp.Z / s
					local above = lp.Y - TILE_TOP * s -- studs over the tile tops
					local reach = humanoid.HipHeight + root.Size.Y * 0.5 + 1.5
					if math.abs(ax) <= STAND_REACH and math.abs(az) <= STAND_REACH and above > -0.5 and above <= reach then
						if math.abs(ax) <= TILE_REACH and math.abs(az) <= TILE_REACH then
							local c = math.clamp(math.floor((EDGE - ax) / PITCH + 0.5), 0, GRID - 1)
							local r = math.clamp(math.floor((EDGE - az) / PITCH + 0.5), 0, GRID - 1)
							local tile = byCell[r * GRID + c]
							if tile then occupied[tile] = true end
						end
						if other == player and humanoid.FloorMaterial ~= Enum.Material.Air and not humanoid.SeatPart then
							localOn = true
						end
					end
				end
			end
		end
		SetOnFloor(model, localOn)
	end
	ctx:Every(FOOT_SCAN, FootScan)

	--..Frame..--
	local lastWrite = 0
	local powerLit = false
	ctx:Step(function(_, now)
		if Kit.IsBroken(model) then return end
		local clock = os.clock()
		if clock - lastWrite < 1 / WRITE_HZ then return end
		lastWrite = clock

		local src = booth
		if src and (not src.Parent or Kit.State(src, "Playing") ~= true) then src = nil end
		if src then
			local beat, pulse = BeatOf(src, now)
			local pattern = math.floor(beat / PATTERN_BEATS) % 3 + 1
			for _, tile in ipairs(tiles) do
				local colour = PatternColour(tile, beat, pulse, pattern)
				if occupied[tile] then colour = colour:Lerp(Color3.new(1, 1, 1), 0.3) end
				Write(tile, colour, onT)
			end
			if power then
				power.Color = POWER_ON:Lerp(Color3.new(1, 1, 1), 0.3 * pulse)
				powerLit = true
			end
		else
			--.. idle: the shipped checkerboard, dim, its lit half swapping slowly; a tile someone stands on lights up
			local phase = math.floor(now / IDLE_SWAP) % 2
			for _, tile in ipairs(tiles) do
				if occupied[tile] then
					Write(tile, Color3.fromHSV(tile.Hue, 0.75, 0.85), onT)
				else
					Write(tile, (tile.R + tile.C) % 2 == phase and tile.Glow or DARK, dimT)
				end
			end
			if power and powerLit then
				power.Color = powerColour
				powerLit = false
			end
		end
	end)

	return function()
		SetOnFloor(model, false)
		for _, tile in ipairs(tiles) do
			if tile.Part.Parent then
				tile.Part.Color = tile.Color
				tile.Part.Material = tile.Material
				tile.Part.Transparency = Settle(tile.T)
			end
		end
		if power and power.Parent then power.Color = powerColour end
	end
end

return B

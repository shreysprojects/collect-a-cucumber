--[[
	VendingMachine  (behaviour, client half)  ReplicatedStorage.FunBehavioursClient.VendingMachine  2026-09-24
	Everything anyone SEES of the snack machine (the server half only takes presses and welds the snack):
	  * always: the NeonText sign ("SNACKS" + the 1.50 price) hums and now and then stutters like a real tube,
	    driven by server time so every client flickers together
	  * "Vend" {Player, Snack, Seed, T0} from the server, replayed from T0 on every client:
	      0.00  Coin sound, two keypad buttons blink (Click on the second)
	      0.20  the snack (a runtime part copy of the stocked can / crisp bag at a matching slot) is pushed
	            forward off its shelf behind the glass, tumbles down in front of the shelves, disappears into
	            the cabinet and lands in the delivery chute at Pivot_DropPoint with a bounce (CanDrop thunk)
	      1.00  the DeliveryFlap swings open about Pivot_FlapHinge (authored X axis) to State_FlapOpen
	      1.18  the snack slides out of the chute and flies into the buyer's right hand (Whoosh), where the
	            server's welded snack takes over (HAND_AT)
	      1.45  the flap is let go: it swings shut against the frame (DoorClose clack) and settles back to its
	            modelled rest angle State_FlapAjar
	      1.70  the buyer raises the snack to the mouth three times (Gulp each time): every client blends the
	            buyer's RightShoulder / RightElbow / RightWrist / Neck toward SIP_POSE (joint Transform, in
	            RunService.Stepped like CucumberLiftClient) and swings the snack's weld so it runs from the fist
	            to the lips
	      4.30  Burp + a puff of green bubbles from the mouth; the snack vanishes (the server destroys it at 4.9)
	  * the local buyer's prompt reads "Out of coins, wait a sec" until their cooldown is over
	  * a far client (camera beyond StepRange: the Step sleeps) only keeps a small record per vend, pruned on the
	    next vend; the drop copy is built on the Step's first awake frame. Per-vend parts / sounds / the burp puff
	    are tracked by the behaviour itself (not ctx:Add, whose list only empties when the ctx stops)
	  * R6 (no RightUpperArm joint): no pose, the snack stays in its plain hold; gulps + burp still play
	Machine geometry is AUTHORED-frame (props/build_vending_machine.py, Blender (x, y, z) -> (x, z, -y)) and is
	mapped with Kit.CFrameToWorld / multiplied by ctx.Scale. The arm pose comes from fun-builds/models/vend_pose.py.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local FunAssets = require(Modules:WaitForChild("FunAssets"))

local LocalPlayer = Players.LocalPlayer

local B = {}
B.Keys = {"VendingMachine"}
B.StepRange = 160

--..Timeline (seconds after the server's T0; HAND_AT / GONE_AT match the server half)..--
local COOLDOWN = 8
local KEY_TIMES = {0, 0.16}
local KEY_FLASH = 0.11
local PUSH_AT, FALL_AT = 0.2, 0.55
local GRAVITY = 48                   -- authored studs / s^2 (the world fall is x Scale)
local FLAP_OPEN_AT, FLAP_OPEN_TIME = 1.0, 0.18
local TAKE_AT, FLY_AT, HAND_AT = 1.18, 1.3, 1.42
local HAND_WAIT = 0.5                -- the flying snack waits on the hand this long at most for the server's
local FLAP_RELEASE_AT = 1.45
local FLAP_DAMP, FLAP_W = 3.0, 2 * math.pi / 0.55
local FLAP_SETTLE = 1.6
local SIP_START, SIP_LEN, SIPS = 1.7, 0.8, 3
local SIP_RAISE, SIP_HOLD = 0.26, 0.26 -- then lower for the rest of SIP_LEN
local SIP_LOW = 0.35                 -- between sips the arm only drops this far (weight)
local GULP_AT = 0.3                  -- into each sip
local BURP_AT = 4.3
local LATE = 0.3                     -- a one-shot sound more than this late (the Step slept) is skipped

--..Machine geometry (authored frame, scale 1)..--
local BAY_FLOOR_Y = 1.94             -- the sill top: below it the snack is inside the cabinet (hidden)
local HIDDEN_Y = 1.62                -- by here it is over the chute (the move happens inside the sill / apron)
local CHUTE_FLOOR_Y = 0.90
local CHUTE_MOUTH = Vector3.new(0, 1.20, -0.98) -- x = the drop point's; just outside the apron face (z -0.76)
local STOCK_FRONT_Z = -0.50          -- every stocked item's front face
local FALL_FRONT_Z = -0.60           -- the falling snack's front face: in front of the shelf lips (-0.58), behind the glass (-0.64)
local KEY_PITCH = 0.26
local KEY_SIZE = 0.2
--.. the stock slots whose colour matches each snack (props/build_vending_machine.py, rng 20260909):
--.. cans stand on shelves 1 / 3 (tops 2.02 / 3.74), crisp bags on shelf 4 (4.60)
local SPOTS = {
	Soda = {{X = 0.350, Y = 2.02, R = 0.088, H = 0.378}, {X = 0.460, Y = 3.74, R = 0.100, H = 0.343}},   -- green cans
	Cola = {{X = 0.570, Y = 2.02, R = 0.088, H = 0.343}, {X = 0.724, Y = 3.74, R = 0.100, H = 0.316}},   -- orange cans
	Chips = {{X = 0.724, Y = 4.60, W = 0.242, H = 0.327, D = 0.168}},                                     -- the yellow bag
}
local GROW = 0.006                   -- the runtime copy is this much bigger than the stock item it covers

--..Looks..--
local WHITE = Color3.fromRGB(242, 240, 234)
local TIN = Color3.fromRGB(196, 203, 212)
local RED = Color3.fromRGB(217, 68, 60)
local YELLOW = Color3.fromRGB(242, 193, 61)
local CAN_COLOR = {Soda = Color3.fromRGB(86, 196, 64), Cola = Color3.fromRGB(200, 32, 40)}
local KEY_GLOW = Color3.fromRGB(157, 255, 36)
local NEON_GATE, NEON_BUZZ, NEON_DIM = 0.35, 0.25, 0.6 -- sign stutter: raise the thresholds for fewer blinks
local BUBBLE_TEXTURE = "rbxassetid://241594314" -- the soft dot the portal effects use
local UP = CFrame.Angles(0, 0, math.rad(90))    -- a Cylinder's axis (local X) turned onto +Y
local FACE = CFrame.Angles(0, math.rad(90), 0)  -- a Cylinder's axis turned onto -Z

--..The sip (fun-builds/models/vend_pose.py variant "a": the fist up-right of the face, the snack angled into
--..the mouth). Part1 name of the joint -> Transform; w, x, y, z quaternions from the R15Rig solve..--
local ITEM_NAME = "FunSnack"
local PROMPT_NAME = "VendPrompt"
local BUY_TEXT, WAIT_TEXT = "Get a snack", "Out of coins, wait a sec"
local SIP_POSE = {
	RightUpperArm = CFrame.new(0, 0, 0, 0.7793, 0.2134, 0.1444, 0.5712),
	RightLowerArm = CFrame.new(0, 0, 0, 0.4082, 0, 0, 0.9129),
	RightHand = CFrame.identity,
	Head = CFrame.new(0, 0, 0, 0.1045, 0, 0, 0.9945), -- the head tips back 12 degrees
}
local FIST_REACH = 0.35              -- the snack's bottom sits this far from the fist centre, toward the lips (x char scale)

--..Helpers..--
local function Smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function Once(sound, late)
	if sound and late >= 0 and late < LATE then sound:Play() end
end

--.. the part a joint (Motor6D or AnimationConstraint) moves
local function JointPart1(joint)
	if joint:IsA("Motor6D") then return joint.Part1 end
	local ok, att = pcall(function() return joint.Attachment1 end)
	return ok and att and att.Parent or nil
end

local function SipJoints(character)
	local map = {}
	for joint in pairs(Kit.Joints(character)) do
		local p1 = JointPart1(joint)
		if p1 and SIP_POSE[p1.Name] then map[p1.Name] = joint end
	end
	return map
end

local function CharScale(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and math.clamp(root.Size.Y / 2, 0.6, 3) or 1
end

local function HandOf(character)
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	return hand and hand:IsA("BasePart") and hand or nil
end

--.. the lips in the world: a quarter down the head, just in front of the face
local function MouthOf(head, s)
	return head.CFrame * Vector3.new(0, -0.25 * head.Size.Y, -(0.5 * head.Size.Z + 0.06 * s))
end

--.. the snack's weight in the sip pose at time t (0 = the arm is its own, 1 = snack at the lips) and which sip
local function SipWeight(t)
	local u = t - SIP_START
	if u < 0 or u >= SIP_LEN * SIPS then return 0, nil end
	local i = math.floor(u / SIP_LEN)
	local k = u - i * SIP_LEN
	local from = i == 0 and 0 or SIP_LOW
	local to = i == SIPS - 1 and 0 or SIP_LOW
	if k < SIP_RAISE then return from + (1 - from) * Smooth(k / SIP_RAISE), i end
	if k < SIP_RAISE + SIP_HOLD then return 1, i end
	return 1 - (1 - to) * Smooth((k - SIP_RAISE - SIP_HOLD) / (SIP_LEN - SIP_RAISE - SIP_HOLD)), i
end

--..Behaviour..--
function B.Client(model, ctx)
	local scale = ctx.Scale
	local hitbox = Kit.Hitbox(model)
	local flap = Kit.Part(model, "DeliveryFlap")
	local neon = Kit.Part(model, "NeonText")
	local function Authored(name, fallback)
		local v = model:GetAttribute("Pivot_" .. name)
		return typeof(v) == "Vector3" and v or fallback
	end
	local keypad = Authored("KeypadCentre", Vector3.new(-0.88, 4.40, -0.92))
	local drop = Authored("DropPoint", Vector3.new(0.47, 1.05, -0.36))
	local hinge = Authored("FlapHinge", Vector3.new(0.47, 1.58, -0.70))
	local cash = Authored("CashSlot", Vector3.new(-0.87, 3.47, -0.90))
	local restAngle = tonumber(model:GetAttribute("State_FlapAjar")) or -22
	local OPEN = (tonumber(model:GetAttribute("State_FlapOpen")) or -78) - restAngle -- relative to the modelled pose
	local SHUT = (tonumber(model:GetAttribute("State_FlapShut")) or 0) - restAngle

	--..Per-vend throwaway instances (drop copies, one-shot sounds, the burp puff) are NOT ctx-registered: the
	--..ctx's list only empties when it stops, and a machine vends for hours. They live in `owned`, leave it when
	--..they are destroyed, and the cleanup destroys whatever is left..--
	local owned = {} -- [Instance] = true
	local function Own(inst)
		owned[inst] = true
		return inst
	end
	local function Free(inst)
		owned[inst] = nil
		inst:Destroy()
	end

	--.. a local-only visual part like ctx:Part (anchored, no collide / query / touch), in the camera
	local function LocalPart(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		p.Parent = workspace.CurrentCamera
		return Own(p)
	end

	--.. a one-shot sound on `parent` that cleans itself up
	local function OneShot(parent, id, props)
		local ok, s = pcall(Kit.MakeSound, id, props)
		if not ok or not s then return end
		s.Parent = parent
		Own(s)
		s:Play()
		task.delay(4, Free, s)
	end

	--..Sound anchors + the keypad blink (local helper parts)..--
	local function Anchor(name, authored)
		return ctx:Part({Name = name, Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(Kit.ToWorld(model, authored))})
	end
	local keyFX = Anchor("VendKeypadFX", keypad)
	local chuteFX = Anchor("VendChuteFX", drop)
	local coinSound = ctx:Sound(Anchor("VendCashFX", cash), FunAssets.Sfx.Coin, {Volume = 0.6})
	local clickSound = ctx:Sound(keyFX, FunAssets.Sfx.Click, {Volume = 0.35})
	local dropSound = ctx:Sound(chuteFX, FunAssets.Sfx.CanDrop, {Volume = 0.55, PlaybackSpeed = 1.15})
	local clackSound = ctx:Sound(chuteFX, FunAssets.Sfx.DoorClose, {Volume = 0.5})
	local whooshSound = ctx:Sound(chuteFX, FunAssets.Sfx.Whoosh, {Volume = 0.25, PlaybackSpeed = 1.3})
	local keyFlash = ctx:Part({Name = "VendKeyFlash", Size = Vector3.new(KEY_SIZE, KEY_SIZE, 0.03) * scale, Material = Enum.Material.Neon,
		Color = KEY_GLOW, Transparency = 1, CFrame = CFrame.new(Kit.ToWorld(model, keypad))})
	local keyFlashOn = false
	local function KeyCF(k)
		local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
		return Kit.CFrameToWorld(model, CFrame.new(keypad.X + (col - 1) * KEY_PITCH, keypad.Y + (1.5 - row) * KEY_PITCH, keypad.Z - 0.012))
	end

	--..The flap: posed about its hinge relative to the Hitbox (a move re-runs us; never pose it at a stale spot)..--
	local hingeRel, flapRel, flapAngle = nil, nil, 0
	if flap and hitbox then
		local hingeCF = CFrame.new(Kit.ToWorld(model, hinge)) * Kit.Origin(model).Rotation
		hingeRel = hitbox.CFrame:ToObjectSpace(hingeCF)
		flapRel = hingeCF:ToObjectSpace(flap.CFrame)
	end
	local function PoseFlap(delta)
		if not hingeRel or math.abs(delta - flapAngle) < 0.05 then return end
		flapAngle = delta
		flap.CFrame = hitbox.CFrame * hingeRel * CFrame.Angles(math.rad(delta), 0, 0) * flapRel
	end
	local function FlapDelta(t)
		if t < FLAP_OPEN_AT then return 0 end
		if t < FLAP_OPEN_AT + FLAP_OPEN_TIME then
			local u = (t - FLAP_OPEN_AT) / FLAP_OPEN_TIME
			return OPEN * (1 - (1 - u) * (1 - u))
		end
		if t < FLAP_RELEASE_AT then return OPEN end
		local tr = t - FLAP_RELEASE_AT
		if tr >= FLAP_SETTLE then return 0 end
		--.. a damped swing about the rest angle; the frame stops it at "shut" (the clack)
		return math.min(OPEN * math.exp(-FLAP_DAMP * tr) * math.cos(FLAP_W * tr), SHUT)
	end

	--..The sign..--
	local neonBase = neon and neon.Color
	local neonLevel = 1
	--.. a slow hum, and a few times a minute a "bad moment" (NEON_GATE) in which the tube stutters (NEON_BUZZ):
	--.. with Perlin noise that is ~4.5 bursts / ~18 blinks a minute, dimmed ~2 % of the time
	local function NeonLevel(now)
		local level = 0.93 + 0.07 * math.clamp(math.noise(now * 0.7, 1.37, 4.21) * 2, -1, 1)
		if math.noise(now * 0.35, 3.1, 9.7) > NEON_GATE and math.noise(now * 9.3, 7.73, 2.19) > NEON_BUZZ then
			level = NEON_DIM
		end
		return level
	end

	--..Snack copies for the drop (local parts, authored sizes x Scale)..--
	--.. the copy's half height, half depth (toward the glass) and half length lying down, authored
	local function DropDims(kind, spot)
		if kind == "Chips" then
			local w, h, d = spot.W + 2 * GROW, spot.H + 2 * GROW, spot.D + 2 * GROW
			return h * 0.5, d * 0.5, w * 0.5
		end
		local r, h = spot.R + GROW, spot.H + 2 * GROW
		return h * 0.5, r, r
	end

	local function BuildDropItem(kind, spot)
		local parts = {}
		local function add(shape, size, rel, color, material)
			local p = LocalPart({Name = "VendSnack", Size = size * scale, Color = color, Material = material or Enum.Material.SmoothPlastic})
			if shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
				p.Size = size * scale -- after the Shape, so nothing resizes it
			elseif shape == "Ellipsoid" then
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = p
			end
			table.insert(parts, {Part = p, Rel = CFrame.new(rel.Position * scale) * rel.Rotation})
		end
		if kind == "Chips" then
			local w, h, d = spot.W + 2 * GROW, spot.H + 2 * GROW, spot.D + 2 * GROW
			add("Block", Vector3.new(w, h * 0.86, d * 0.7), CFrame.new(), YELLOW)
			add("Ellipsoid", Vector3.new(w * 0.98, h * 0.8, d), CFrame.new(), YELLOW)
			add("Block", Vector3.new(w * 1.04, 0.035, d * 0.55), CFrame.new(0, h * 0.5 - 0.0175, 0), RED)
			add("Block", Vector3.new(w * 1.04, 0.035, d * 0.55), CFrame.new(0, -(h * 0.5 - 0.0175), 0), RED)
			add("Cylinder", Vector3.new(0.012, w * 0.42, w * 0.42), CFrame.new(0, 0.01, -d * 0.5) * FACE, RED)
		else
			local r, h = spot.R + GROW, spot.H + 2 * GROW
			add("Cylinder", Vector3.new(h, 2 * r, 2 * r), UP, CAN_COLOR[kind])
			add("Cylinder", Vector3.new(h * 0.38, 2 * r + 0.008, 2 * r + 0.008), CFrame.new(0, 0.005, 0) * UP, WHITE)
			if kind == "Cola" then
				add("Cylinder", Vector3.new(0.025, 2 * r + 0.012, 2 * r + 0.012), CFrame.new(0, 0.005, 0) * UP, CAN_COLOR.Cola)
			end
			add("Cylinder", Vector3.new(0.02, 1.7 * r, 1.7 * r), CFrame.new(0, h * 0.5 + 0.004, 0) * UP, TIN, Enum.Material.Metal)
		end
		return {Parts = parts}
	end

	local function PlaceItem(item, worldCF)
		for _, row in ipairs(item.Parts) do row.Part.CFrame = worldCF * row.Rel end
	end

	local function HideItem(item)
		for _, row in ipairs(item.Parts) do row.Part.Transparency = 1 end
	end

	--.. the snack's AUTHORED CFrame at time t (nil once it has left the machine)
	local function DropCF(v, t)
		local x0, dx, dz = v.Spot.X, drop.X, drop.Z
		if t < PUSH_AT then return CFrame.new(x0, v.Y0, v.Z0) end
		if t < FALL_AT then --.. the spiral pushes it off the shelf edge
			local u = (t - PUSH_AT) / (FALL_AT - PUSH_AT)
			local yaw = math.sin(u * math.pi * 3) * math.rad(5) * (1 - u)
			local tip = math.rad(-8) * math.clamp((u - 0.6) / 0.4, 0, 1)
			return CFrame.new(x0, v.Y0, v.Z0 + (v.Z1 - v.Z0) * Smooth(u)) * CFrame.Angles(tip, yaw, 0)
		end
		if t < v.LandT then --.. falls in front of the shelves, then (hidden in the sill) moves over the chute and lies down
			local tf = t - FALL_AT
			local y = math.max(v.Y0 - 0.5 * GRAVITY * tf * tf, v.RestY)
			local p = math.clamp((BAY_FLOOR_Y - y) / (BAY_FLOOR_Y - HIDDEN_Y), 0, 1)
			local roll = (1 - p) * math.min(tf / 0.3, 1) * 28 + p * 90
			return CFrame.new(x0 + (dx - x0) * p, y, v.Z1 + (dz - v.Z1) * p) * CFrame.Angles(math.rad(-8) * (1 - p), 0, math.rad(roll * v.Roll))
		end
		if t < TAKE_AT then --.. landed: a hop and a wobble
			local u = t - v.LandT
			local hop = 0
			if u < 0.16 then
				hop = 0.07 * math.sin(math.pi * u / 0.16)
			elseif u < 0.26 then
				hop = 0.022 * math.sin(math.pi * (u - 0.16) / 0.1)
			end
			local wob = u < 0.3 and math.sin(u * 40) * math.rad(6) * (1 - u / 0.3) or 0
			return CFrame.new(dx, v.RestY + hop, dz) * CFrame.Angles(wob, 0, math.rad(90 * v.Roll))
		end
		if t < FLY_AT then --.. out of the chute under the open flap, standing up
			local u = (t - TAKE_AT) / (FLY_AT - TAKE_AT)
			local pos = Vector3.new(dx, v.RestY, dz):Lerp(Vector3.new(dx, CHUTE_MOUTH.Y, CHUTE_MOUTH.Z), Smooth(u))
			return CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90 * v.Roll) * (1 - Smooth((u - 0.4) / 0.6)))
		end
		return nil
	end

	--..Vends in flight..--
	local vends = {} -- [v] = true
	local sippers = {} -- [s] = true
	local promptStamp = 0

	--.. the server's snack for this vend in the buyer's character, if it is there yet
	local function ServerSnack(buyer, t0)
		local character = buyer and buyer.Character
		local item = character and character:FindFirstChild(ITEM_NAME)
		if item and math.abs((tonumber(item:GetAttribute("SnackT0")) or -1) - t0) < 0.01 then return item end
		return nil
	end

	local function StepVend(v, t)
		--.. sounds + keypad
		if not v.Coin and t >= 0 then v.Coin = true Once(coinSound, t) end
		if not v.Click and t >= KEY_TIMES[2] then v.Click = true Once(clickSound, t - KEY_TIMES[2]) end
		if not v.Thunk and t >= v.LandT then v.Thunk = true Once(dropSound, t - v.LandT) end
		if not v.Whoosh and t >= FLY_AT then v.Whoosh = true Once(whooshSound, t - FLY_AT) end
		local clackAt = FLAP_RELEASE_AT + math.pi / FLAP_W - 0.03
		if not v.Clack and t >= clackAt then v.Clack = true Once(clackSound, t - clackAt) end
		--.. the snack: its parts are built here, on the first frame the Step is awake for this vend (the Step
		--.. sleeps beyond StepRange: a far camera never builds them); too late to see the drop = no copy at all
		if v.ItemDone then return end
		if not v.Item then
			if t >= FLY_AT then
				v.ItemDone = true
				return
			end
			v.Item = BuildDropItem(v.Kind, v.Spot)
		end
		local cf = DropCF(v, t)
		if cf then
			PlaceItem(v.Item, Kit.CFrameToWorld(model, cf))
			return
		end
		v.FlyFrom = v.FlyFrom or Kit.CFrameToWorld(model, CFrame.new(drop.X, CHUTE_MOUTH.Y, CHUTE_MOUTH.Z))
		local hand = HandOf(v.Buyer and v.Buyer.Character)
		if not hand then
			HideItem(v.Item)
			v.ItemDone = true
			return
		end
		local target = (hand.CFrame * CFrame.new(0, 0, -(hand.Size.Z * 0.5 + 0.2))).Position
		local u = math.clamp((t - FLY_AT) / (HAND_AT - FLY_AT), 0, 1)
		local e = 1 - (1 - u) * (1 - u)
		local pos = v.FlyFrom.Position:Lerp(target, e) + Vector3.yAxis * math.sin(math.pi * u) * 0.8 * scale
		PlaceItem(v.Item, CFrame.new(pos) * v.FlyFrom.Rotation)
		if u >= 1 and (ServerSnack(v.Buyer, v.T0) or t > HAND_AT + HAND_WAIT) then
			HideItem(v.Item)
			v.ItemDone = true
		end
	end

	local function EndVend(v)
		vends[v] = nil
		if v.Item then
			for _, row in ipairs(v.Item.Parts) do Free(row.Part) end
			v.Item = nil
		end
	end

	ctx:Step(function(_, now)
		--.. the sign hums
		if neon and neonBase then
			local level = NeonLevel(now)
			if math.abs(level - neonLevel) > 0.015 then
				neonLevel = level
				neon.Color = Color3.new(neonBase.R * level, neonBase.G * level, neonBase.B * level)
			end
		end
		if next(vends) == nil then
			if keyFlashOn then keyFlashOn = false keyFlash.Transparency = 1 end
			PoseFlap(0)
			return
		end
		local flapDelta, keyAt = 0, nil
		for v in pairs(vends) do
			local t = now - v.T0
			if t > FLAP_RELEASE_AT + FLAP_SETTLE and v.ItemDone then
				EndVend(v)
			else
				StepVend(v, math.max(t, 0))
				local d = FlapDelta(math.max(t, 0))
				if math.abs(d) > math.abs(flapDelta) then flapDelta = d end
				for j, at in ipairs(KEY_TIMES) do
					if t >= at and t < at + KEY_FLASH then keyAt = v.Keys[j] end
				end
			end
		end
		PoseFlap(flapDelta)
		if keyAt then
			keyFlash.CFrame = KeyCF(keyAt)
			if not keyFlashOn then keyFlashOn = true keyFlash.Transparency = 0.05 end
		elseif keyFlashOn then
			keyFlashOn = false
			keyFlash.Transparency = 1
		end
	end)

	--..The buyer's drink (every client poses that character; RunService.Stepped = after the Animator)..--
	--.. a joint is blended from the Animator's value of THIS frame; if the Animator skipped the joint (it still
	--.. holds what we wrote) we blend from its last real value instead, so nothing ever stacks, and we hand
	--.. that value back when the sip ends
	local function Same(a, b)
		return a == b or a:FuzzyEq(b, 1e-4)
	end

	local function PoseJoint(s, name, joint, pose, w)
		local cur = joint.Transform
		local base = (s.Wrote[name] and Same(cur, s.Wrote[name])) and s.Base[name] or cur
		s.Base[name] = base
		local out = base:Lerp(pose, w)
		joint.Transform = out
		s.Wrote[name] = out
	end

	local function ReleaseJoints(s)
		for name, wrote in pairs(s.Wrote) do
			local joint = s.Joints and s.Joints[name]
			if joint and joint.Parent and s.Base[name] and Same(joint.Transform, wrote) then joint.Transform = s.Base[name] end
		end
		table.clear(s.Wrote)
	end

	local function Unbind(s)
		ReleaseJoints(s)
		if s.Weld and s.Weld.Parent and s.C0Idle then s.Weld.C0 = s.C0Idle end
	end

	local function Bind(s, item)
		local weld = item:FindFirstChild("SnackWeld")
		local character = s.Buyer.Character
		local head = character and character:FindFirstChild("Head")
		if not (weld and weld:IsA("Weld") and head) then return false end
		s.Item, s.Weld, s.C0Idle, s.Head = item, weld, weld.C0, head
		s.Hand = weld.Part0
		s.Char = character
		s.Scale = CharScale(character)
		s.Length = tonumber(item:GetAttribute("SnackLength")) or 0.8 * s.Scale
		s.Joints = SipJoints(character)
		--.. SIP_POSE is an R15 pose: without an upper-arm joint (R6: "Right Arm" + a Neck in another frame) the
		--.. body is left alone and the snack stays in its plain hold; the gulps and the burp still play
		s.Pose = s.Joints.RightUpperArm ~= nil
		if not s.Pose then s.Joints = {} end
		return true
	end

	local function Burp(s)
		local head = s.Head
		if head and head.Parent then
			OneShot(head, FunAssets.Sfx.Burp, {Volume = 0.9, PlaybackSpeed = 0.8})
			local att = Own(Instance.new("Attachment"))
			att.Name = "VendBurp"
			att.Position = Vector3.new(0, -0.25 * head.Size.Y, -0.5 * head.Size.Z)
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = BUBBLE_TEXTURE
			pe.Color = ColorSequence.new(Color3.fromRGB(140, 235, 80), Color3.fromRGB(205, 255, 160))
			pe.LightEmission = 0.35
			pe.LightInfluence = 0.4
			pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.16 * s.Scale), NumberSequenceKeypoint.new(0.6, 0.3 * s.Scale),
				NumberSequenceKeypoint.new(1, 0.06 * s.Scale)})
			pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.75, 0.35), NumberSequenceKeypoint.new(1, 1)})
			pe.Lifetime = NumberRange.new(0.7, 1.3)
			pe.Speed = NumberRange.new(2.5 * s.Scale, 4.5 * s.Scale)
			pe.SpreadAngle = Vector2.new(35, 35)
			pe.Acceleration = Vector3.new(0, 3 * s.Scale, 0)
			pe.Drag = 2.5
			pe.RotSpeed = NumberRange.new(-60, 60)
			pe.EmissionDirection = Enum.NormalId.Front
			pe.Rate = 0
			pe.Enabled = false
			pe.Parent = att
			att.Parent = head
			pcall(pe.Emit, pe, 16)
			task.delay(2.5, Free, att)
		end
		--.. the snack is finished: gone on every client now, the server destroys it shortly
		if s.Item and s.Item.Parent then
			for _, d in ipairs(s.Item:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
			end
		end
	end

	local function StepSip(s, now)
		local t = now - s.T0
		if t > BURP_AT + 0.5 or (s.Char and not s.Char.Parent) then
			Unbind(s)
			sippers[s] = nil
			return
		end
		if not s.Item then
			local item = t >= SIP_START - 0.4 and ServerSnack(s.Buyer, s.T0)
			if not (item and Bind(s, item)) then
				if t > SIP_START + 0.6 then sippers[s] = nil end -- no snack arrived (died, left): no drinking
				return
			end
		end
		if not s.Item.Parent then
			--.. the server took the snack away early (machine sold / moved / broken, a new snack): hand the joints back
			pcall(Unbind, s)
			sippers[s] = nil
			return
		end
		--.. the arm (and head) toward the sip pose
		local w, i = SipWeight(t)
		if w > 0 and s.Pose then
			for name, pose in pairs(SIP_POSE) do
				local joint = s.Joints[name]
				if joint and not joint.Parent then
					s.Joints = SipJoints(s.Char) -- a physique upgrade rebuilt the joints
					joint = s.Joints[name]
				end
				if joint then PoseJoint(s, name, joint, pose, w) end
			end
			--.. the snack swings from its at-the-side hold to "fist -> lips"
			local hand, head = s.Hand, s.Head
			if hand and hand.Parent and head.Parent then
				local fist = hand.Position
				local dir = MouthOf(head, s.Scale) - fist
				if dir.Magnitude > 0.05 then
					dir = dir.Unit
					local idle = hand.CFrame * s.C0Idle
					local up = idle.UpVector
					local axis = up:Cross(dir)
					local rot = axis.Magnitude > 1e-4 and CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(up:Dot(dir), -1, 1))) or CFrame.identity
					local target = CFrame.new(fist + dir * (FIST_REACH * s.Scale + s.Length * 0.5)) * rot * idle.Rotation
					s.Weld.C0 = s.C0Idle:Lerp(hand.CFrame:ToObjectSpace(target), w)
				end
			end
			s.Posed = true
		elseif s.Posed then
			s.Posed = false
			Unbind(s)
		end
		--.. gulp on every sip, burp at the end
		if i and not s.Gulps[i] and t - SIP_START - i * SIP_LEN >= GULP_AT then
			s.Gulps[i] = true
			if t - SIP_START - i * SIP_LEN - GULP_AT < LATE and s.Head.Parent then
				OneShot(s.Head, FunAssets.Sfx.Gulp, {Volume = 0.7, PlaybackSpeed = (s.Kind == "Chips" and 1.3 or 1) + i * 0.06})
			end
		end
		if not s.Burped and t >= BURP_AT then
			s.Burped = true
			if t - BURP_AT < LATE then Burp(s) end
		end
	end

	ctx:Connect(RunService.Stepped, function()
		if next(sippers) == nil then return end
		local now = Kit.Now()
		for s in pairs(sippers) do
			local ok, err = pcall(StepSip, s, now)
			if not ok then
				pcall(Unbind, s) -- never leave the arm stuck up (ReleaseJoints only restores joints still holding our value)
				sippers[s] = nil
				warn("[VendingMachine] sip: " .. tostring(err))
			end
		end
	end)

	--..Server events..--
	ctx.OnVend = function(payload)
		local kind = payload.Snack
		local spots = SPOTS[kind]
		local t0 = tonumber(payload.T0)
		local buyer = payload.Player
		if not (spots and t0) then return end
		local seed = math.floor(tonumber(payload.Seed) or 0)
		local now = Kit.Now()
		local t = now - t0
		--.. vends the Step never finished (it sleeps while the camera is beyond StepRange) end here, so a far
		--.. client that hears every vend holds at most the last few seconds of them
		for old in pairs(vends) do
			if now - old.T0 > FLAP_RELEASE_AT + FLAP_SETTLE then EndVend(old) end
		end
		--.. the machine (skipped when we hear about it too late to matter): only a record here, the Step builds
		--.. the drop copy once it is awake for it
		if t < FLAP_RELEASE_AT + FLAP_SETTLE then
			local spot = spots[(math.floor(seed / 144) % #spots) + 1]
			local half, depth, lying = DropDims(kind, spot)
			local v = {Kind = kind, Spot = spot, T0 = t0, Buyer = buyer,
				Keys = {seed % 12 + 1, math.floor(seed / 12) % 12 + 1}, Roll = (math.floor(seed / 1000) % 2 == 0) and 1 or -1}
			v.Y0 = spot.Y + half
			v.RestY = CHUTE_FLOOR_Y + lying
			v.Z0 = STOCK_FRONT_Z + (depth - GROW) - 0.008 -- over the stock item, a hair in front of it
			v.Z1 = FALL_FRONT_Z + depth
			v.LandT = FALL_AT + math.sqrt(2 * math.max(v.Y0 - v.RestY, 0) / GRAVITY)
			vends[v] = true
		end
		--.. the buyer's drink
		if typeof(buyer) == "Instance" and buyer:IsA("Player") and t < BURP_AT then
			sippers[{Buyer = buyer, T0 = t0, Kind = kind, Gulps = {}, Wrote = {}, Base = {}}] = true
		end
		--.. our own purchase: the prompt tells us to wait
		if buyer == LocalPlayer and hitbox then
			local prompt = hitbox:FindFirstChild(PROMPT_NAME, true)
			if prompt and prompt:IsA("ProximityPrompt") then
				promptStamp += 1
				local stamp = promptStamp
				prompt.ActionText = WAIT_TEXT
				task.delay(math.max(COOLDOWN - t, 0), function()
					if stamp == promptStamp and prompt.Parent then prompt.ActionText = BUY_TEXT end
				end)
			end
		end
	end

	--..Cleanup: put back everything of the build we touched..--
	return function()
		promptStamp += 1
		for s in pairs(sippers) do pcall(Unbind, s) end
		table.clear(sippers)
		table.clear(vends)
		for inst in pairs(owned) do inst:Destroy() end
		table.clear(owned)
		if neon and neonBase and neon.Parent then neon.Color = neonBase end
		if hingeRel and flap.Parent and hitbox.Parent and flapAngle ~= 0 then
			flap.CFrame = hitbox.CFrame * hingeRel * flapRel
		end
		local prompt = hitbox and hitbox:FindFirstChild(PROMPT_NAME, true)
		if prompt and prompt:IsA("ProximityPrompt") and prompt.ActionText == WAIT_TEXT then prompt.ActionText = BUY_TEXT end
	end
end

function B.OnEvent(model, action, payload, ctx)
	if action == "Vend" and type(payload) == "table" and ctx.OnVend then ctx.OnVend(payload) end
end

return B

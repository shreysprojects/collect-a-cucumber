--[[
	VendingMachine  (behaviour, server half)  ServerStorage.FunBehaviours.VendingMachine  2026-09-24
	A working snack machine (free, cosmetic - no Cash, no Strength, no boosts).
	  * prompt "Get a snack" (hold 0.3 s) at the keypad (Pivot_KeypadCentre), anyone may use it
	  * one snack per player every COOLDOWN seconds (across every machine: "out of coins, wait a sec") -
	    extra presses are simply ignored
	  * a press picks a random snack (Cucumber Soda / Cola / Chips) and fires "Vend" to every client:
	    {Player, Snack, Seed, T0 = server time}. The clients play the machine (keypad blink + Coin, the snack
	    tips off its shelf behind the glass, drops into the chute with a CanDrop thunk, the DeliveryFlap swings
	    open and shut, the snack flies into the buyer's hand) - behaviours/client/VendingMachine.lua
	  * HAND_AT seconds after T0 the server welds a small part-built snack (massless, no collide / touch /
	    query) to the buyer's RightHand, parented to the character: an invisible root "FunSnack" (+Y = the
	    snack's top, attributes SnackKind / SnackLength / SnackT0) plus its visible parts. Every client then
	    animates the drink / eat sequence on that character (3 sips with Gulp sounds, a burp with green
	    bubbles, the snack vanishes locally) and the server destroys the snack at GONE_AT.
	The hold offset and snack sizes are at character scale 1 and grow with the character
	(HumanoidRootPart.Size.Y / 2, like CucumberLiftClient). R6 bodies hold it on "Right Arm".
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

local B = {}
B.Keys = {"VendingMachine"}

--..Config..--
local PROMPT_NAME = "VendPrompt"     -- the client finds it by this name (local "wait a sec" text)
local PROMPT_DISTANCE = 8
local COOLDOWN = 8                   -- s per player, shared by every machine (client: COOLDOWN)
local HAND_AT = 1.4                  -- s after T0: the drop animation is over, the snack is in the hand (client: HAND_AT)
local GONE_AT = 4.9                  -- s after T0: the snack is destroyed (client burps at BURP_AT = 4.3)
local ITEM_NAME = "FunSnack"
local HOLD_Y = -0.05                 -- snack centre below the hand centre (x character scale)
local HOLD_GAP = 0.04                -- the snack sinks this far into the fist's front face
local KINDS = {"Soda", "Cola", "Chips"}

local WHITE = Color3.fromRGB(242, 240, 234)
local TIN = Color3.fromRGB(196, 203, 212)
local RED = Color3.fromRGB(217, 68, 60)

--..Snacks..--
--.. one entry per kind at character scale 1, in the snack's own frame: origin = its centre, +Y = its top,
--.. -Z = its front (the label faces away from the fist). Length = size along +Y, Depth = size along Z.
--.. Part rows: {Name, Shape ("Cylinder" axis X / "Block" / "Ellipsoid"), Size, CFrame, Color, Material}
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis (local X) turned onto +Y
local SNACKS = {
	Soda = { -- Cucumber Soda: a green can with a white band and a little cucumber on it
		Length = 0.80, Depth = 0.44,
		Parts = {
			{"Can", "Cylinder", Vector3.new(0.80, 0.44, 0.44), UP, Color3.fromRGB(86, 196, 64), Enum.Material.SmoothPlastic},
			{"Band", "Cylinder", Vector3.new(0.30, 0.452, 0.452), CFrame.new(0, 0.02, 0) * UP, WHITE, Enum.Material.SmoothPlastic},
			{"Lid", "Cylinder", Vector3.new(0.04, 0.37, 0.37), CFrame.new(0, 0.41, 0) * UP, TIN, Enum.Material.Metal},
			{"Rim", "Cylinder", Vector3.new(0.04, 0.37, 0.37), CFrame.new(0, -0.41, 0) * UP, TIN, Enum.Material.Metal},
			{"Tab", "Block", Vector3.new(0.08, 0.03, 0.13), CFrame.new(0, 0.435, -0.05), TIN, Enum.Material.Metal},
			{"Logo", "Ellipsoid", Vector3.new(0.10, 0.24, 0.06), CFrame.new(0, 0.02, -0.228) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(47, 107, 44), Enum.Material.SmoothPlastic},
		},
	},
	Cola = { -- Cola: a red can, white band with a red stripe through it
		Length = 0.80, Depth = 0.44,
		Parts = {
			{"Can", "Cylinder", Vector3.new(0.80, 0.44, 0.44), UP, Color3.fromRGB(200, 32, 40), Enum.Material.SmoothPlastic},
			{"Band", "Cylinder", Vector3.new(0.30, 0.452, 0.452), CFrame.new(0, 0.02, 0) * UP, WHITE, Enum.Material.SmoothPlastic},
			{"Stripe", "Cylinder", Vector3.new(0.07, 0.458, 0.458), CFrame.new(0, 0.02, 0) * UP, Color3.fromRGB(200, 32, 40), Enum.Material.SmoothPlastic},
			{"Lid", "Cylinder", Vector3.new(0.04, 0.37, 0.37), CFrame.new(0, 0.41, 0) * UP, TIN, Enum.Material.Metal},
			{"Rim", "Cylinder", Vector3.new(0.04, 0.37, 0.37), CFrame.new(0, -0.41, 0) * UP, TIN, Enum.Material.Metal},
			{"Tab", "Block", Vector3.new(0.08, 0.03, 0.13), CFrame.new(0, 0.435, -0.05), TIN, Enum.Material.Metal},
		},
	},
	Chips = { -- Chips: a puffy yellow bag, red crimped ends, a white-and-red banner and a couple of chips
		Length = 0.84, Depth = 0.32,
		Parts = {
			{"Bag", "Block", Vector3.new(0.56, 0.70, 0.12), CFrame.new(), Color3.fromRGB(242, 193, 61), Enum.Material.SmoothPlastic},
			{"Puff", "Ellipsoid", Vector3.new(0.55, 0.66, 0.32), CFrame.new(), Color3.fromRGB(242, 193, 61), Enum.Material.SmoothPlastic},
			{"CrimpTop", "Block", Vector3.new(0.58, 0.07, 0.09), CFrame.new(0, 0.385, 0), RED, Enum.Material.SmoothPlastic},
			{"CrimpBottom", "Block", Vector3.new(0.58, 0.07, 0.09), CFrame.new(0, -0.385, 0), RED, Enum.Material.SmoothPlastic},
			{"Banner", "Ellipsoid", Vector3.new(0.40, 0.22, 0.06), CFrame.new(0, 0.08, -0.15), WHITE, Enum.Material.SmoothPlastic},
			{"BannerInk", "Ellipsoid", Vector3.new(0.30, 0.11, 0.06), CFrame.new(0, 0.08, -0.162), RED, Enum.Material.SmoothPlastic},
			{"ChipA", "Ellipsoid", Vector3.new(0.14, 0.10, 0.04), CFrame.new(-0.07, -0.19, -0.135) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(255, 226, 122), Enum.Material.SmoothPlastic},
			{"ChipB", "Ellipsoid", Vector3.new(0.12, 0.09, 0.04), CFrame.new(0.09, -0.21, -0.13) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(233, 196, 90), Enum.Material.SmoothPlastic},
		},
	},
}

--..State shared by every machine..--
local NextVend = setmetatable({}, {__mode = "k"}) -- [Player] = os.clock() when they may buy again

--..Helpers..--
local function NewPart(name, shape, size)
	local p = Instance.new("Part")
	p.Name = name
	if shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Size = size
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function Weld(part0, part1, c0, name)
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.C1 = CFrame.identity
	w.Parent = part1
	return w
end

--.. the character's scale (1 = the ~6-stud default body), from the HumanoidRootPart like CucumberLiftClient
local function CharScale(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and math.clamp(root.Size.Y / 2, 0.6, 3) or 1
end

--.. build the snack (unparented) and weld it in front of the fist; returns the root part
local function MakeSnack(kind, hand, s, t0)
	local spec = SNACKS[kind]
	local root = NewPart(ITEM_NAME, "Block", Vector3.new(spec.Depth, spec.Length, spec.Depth) * s)
	root.Transparency = 1
	root:SetAttribute("SnackKind", kind)
	root:SetAttribute("SnackLength", spec.Length * s)
	root:SetAttribute("SnackT0", t0)
	--.. R15: in front of the RightHand, centred on it; R6: the fist is the bottom of "Right Arm"
	local y = hand.Name == "RightHand" and HOLD_Y * s or -hand.Size.Y * 0.36
	local hold = CFrame.new(0, y, -(hand.Size.Z * 0.5 + (spec.Depth * 0.5 - HOLD_GAP) * s))
	root.CFrame = hand.CFrame * hold
	for _, row in ipairs(spec.Parts) do
		local name, shape, size, cf, color, material = row[1], row[2], row[3], row[4], row[5], row[6]
		local p = NewPart(name, shape, size * s)
		p.Color = color
		p.Material = material
		p.CastShadow = true
		local rel = CFrame.new(cf.Position * s) * cf.Rotation
		p.CFrame = root.CFrame * rel
		Weld(root, p, rel)
		p.Parent = root
	end
	Weld(hand, root, hold, "SnackWeld")
	return root
end

--.. HAND_AT: the snack lands in the buyer's hand. `snacks` is the machine's own set of live snacks (its cleanup
--.. destroys them: a sold / moved / broken machine takes its snacks with it) - not ctx:Add, whose list only
--.. empties when the ctx stops while a machine vends for hours
local function GiveSnack(ctx, snacks, player, kind, t0)
	local humanoid = ctx:HumanoidOf(player)
	local character = player.Character
	if not humanoid or not character then return end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then return end
	local old = character:FindFirstChild(ITEM_NAME)
	if old then old:Destroy() end
	local ok, root = pcall(MakeSnack, kind, hand, CharScale(character), t0)
	if not ok then
		warn("[VendingMachine] snack: " .. tostring(root))
		return
	end
	root.Parent = character
	snacks[root] = true
	task.delay(GONE_AT - HAND_AT, function()
		snacks[root] = nil
		if root.Parent then root:Destroy() end
	end)
end

--..Behaviour..--
function B.Server(model, ctx)
	local snacks = {} -- [FunSnack root] = true while it is in someone's hand
	local hitbox = Kit.Hitbox(model)
	local keypad = Kit.Pivot(model, "KeypadCentre") or hitbox.Position
	local prompt = ctx:Prompt(hitbox, {
		Action = "Get a snack",
		Object = "Snack Machine",
		Hold = 0.3,
		Distance = PROMPT_DISTANCE,
		Name = PROMPT_NAME,
		Offset = hitbox.CFrame:PointToObjectSpace(keypad),
	})
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() or not ctx:HumanoidOf(player) then return end
		local now = os.clock()
		if (NextVend[player] or 0) > now then return end -- out of coins, wait a sec
		NextVend[player] = now + COOLDOWN
		local kind = KINDS[math.random(#KINDS)]
		local t0 = Kit.Now()
		ctx:Fire("Vend", {Player = player, Snack = kind, Seed = math.random(1, 1000000), T0 = t0})
		task.delay(HAND_AT, function()
			if ctx:Alive() then GiveSnack(ctx, snacks, player, kind, t0) end
		end)
	end)

	--..Cleanup: the snacks still in hands go with the machine..--
	return function()
		for root in pairs(snacks) do root:Destroy() end
		table.clear(snacks)
	end
end

return B

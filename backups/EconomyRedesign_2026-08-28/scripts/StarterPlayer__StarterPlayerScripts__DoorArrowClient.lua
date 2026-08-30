--[[
	DoorArrowClient
	Once you've banked enough COINS to actually unlock the NEXT room, a white
	arrow appears on the ground under your feet and points at that gate. It hides
	as soon as a UI panel is open (the unlock prompt included) and while you can't
	afford / aren't allowed through the gate ahead.

	Purely LOCAL: built by this LocalScript and parented to workspace on the client,
	so it never replicates -- no other player sees it.

	GOTCHA (this bit me): Roblox CFrames face along their **-Z** axis
	(CFrame.LookVector == -ZVector). So the arrow geometry below is modelled with
	its TIP at NEGATIVE Z. Build it tip-forward at +Z and CFrame.lookAt() will aim
	the arrow 180 degrees away from the target while every "does the CFrame face
	the door" check still passes.

	"Can actually unlock" must mirror BOTH gates the server checks in
	DoorService.PromptPurchase, or we'd point at a door that refuses to open:
	  * coins >= Stats.Price  (doors charge COINS since the 2026-08-26 economy
	    pass -- this mirror wrongly read Cukes until 2026-08-27, making the
	    arrow + toast fire before the player could actually pay)
	  * rebirths  >= Stats.MinRebirths  (Farm 1, Snow 2, Underwater 3, Volcano 4, Narmek 5)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlayerData = Player:WaitForChild("PlayerData", 30)
local leaderstats = Player:WaitForChild("leaderstats", 30)

local Coins = leaderstats:WaitForChild("Coins")
local Rebirths = leaderstats:WaitForChild("Rebirths")
local OwnedString = PlayerData:WaitForChild("Doors"):WaitForChild("OwnedString")
local DoneTutorial = PlayerData:WaitForChild("DoneTutorial", 10)

--.. every click-open panel. The unlock prompt is Frames.Door; hiding on ANY open
--.. panel is a superset of that, so the arrow can never survive the unlock UI.
local Display = PlayerGui:WaitForChild("Display", 30)
local DisplayFrame = Display and Display:WaitForChild("Frame", 10)
local Frames = DisplayFrame and DisplayFrame:WaitForChild("Frames", 10)
local DoorFrame = Frames and Frames:WaitForChild("Door", 10)

local DoorModels = workspace:WaitForChild("Doors")

local DoorStats = Network:InvokeServer("GetData", "Dictionary", { Name = "Doors" })
if type(DoorStats) ~= "table" then
	warn("[DoorArrowClient] could not fetch the Doors dictionary; no arrow.")
	return
end

--== Config ==================================================================
local GROUND_LIFT = 0.44   -- room for the dark extruded base below the pale top
local FALLBACK_DROP = 2.9  -- HRP -> feet, if the floor raycast misses
--.. The broad arrow spans local z -5.5 (tip) .. +5.0 (tail). Keeping its origin
--.. seven studs ahead puts the tail near the player's feet and the head well past
--.. the avatar silhouette, matching the large, readable reference style.
local FORWARD_OFFSET = 7
--.. the arrow bobs back and forth ALONG the gate direction, so it reads as "go that way"
local BOB_AMPLITUDE = 1.1   -- studs it slides forward/back
local BOB_SPEED = 3.5       -- radians/sec

--== Arrow: chunky pale top with dark extrusion, TIP AT -Z =====================
local arrow = Instance.new("Model")
arrow.Name = "NextDoorArrow"

local TOP_COLOR = Color3.fromRGB(238, 252, 255)
local SIDE_COLOR = Color3.fromRGB(12, 29, 32)
local TOP_THICKNESS = 0.30
local SIDE_THICKNESS = 0.46
local HEAD_LENGTH = 4.5
local HEAD_HALF_WIDTH = 3.8
local HEAD_CENTER_Z = -3.25
local SHAFT_WIDTH = 2.9
local SHAFT_LENGTH = 6.0
local SHAFT_CENTER_Z = 2.0

local function piece(className, name, size, cf, color, material)
	local p = Instance.new(className)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false   -- must not eat the click-to-hit raycast, nor our own floor probe
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Parent = arrow
	return p
end

--.. A WedgePart is triangular in Y/Z. Rotating it 90 degrees around Z lays that
--.. triangle flat; two mirrored halves form the wide, solid arrowhead.
local function makeLayer(prefix, y, thickness, expansion, zOffset, color, material)
	local halfWidth = HEAD_HALF_WIDTH + expansion
	local headLength = HEAD_LENGTH + expansion
	local headCenterZ = HEAD_CENTER_Z + zOffset

	piece("Part", prefix .. "Shaft",
		Vector3.new(SHAFT_WIDTH + expansion * 2, thickness, SHAFT_LENGTH + expansion),
		CFrame.new(0, y, SHAFT_CENTER_Z + zOffset), color, material)

	piece("WedgePart", prefix .. "HeadL",
		Vector3.new(thickness, halfWidth, headLength),
		CFrame.new(-halfWidth / 2, y, headCenterZ) * CFrame.Angles(0, 0, math.rad(90)),
		color, material)
	piece("WedgePart", prefix .. "HeadR",
		Vector3.new(thickness, halfWidth, headLength),
		CFrame.new(halfWidth / 2, y, headCenterZ) * CFrame.Angles(0, 0, math.rad(-90)),
		color, material)
end

--.. Build the dark layer first. Its slight oversize and rearward offset leave a
--.. crisp outline/extruded edge around the white top from the gameplay camera.
makeLayer("Side", -0.20, SIDE_THICKNESS, 0.18, 0.12, SIDE_COLOR, Enum.Material.SmoothPlastic)
makeLayer("Top", 0, TOP_THICKNESS, 0, 0, TOP_COLOR, Enum.Material.SmoothPlastic)

--.. A crisp dark silhouette keeps the pale arrow readable on snow, sand, and bright grass.
local outline = Instance.new("Highlight")
outline.Name = "DarkOutline"
outline.Adornee = arrow
outline.FillTransparency = 1
outline.OutlineColor = SIDE_COLOR
outline.OutlineTransparency = 0
outline.DepthMode = Enum.HighlightDepthMode.Occluded
outline.Parent = arrow

--.. invisible root so PivotTo() pivots about the arrow's origin, not its bounding box
local root = piece("Part", "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(),
	TOP_COLOR, Enum.Material.SmoothPlastic)
root.Transparency = 1
arrow.PrimaryPart = root

--== "You can afford it!" celebration (2026-08-22) ===========================
--.. A real ad-cohort player farmed 13k cucumbers, never bought the 10k door, and
--.. left. The floor arrow alone was too quiet. One loud toast per door per session
--.. the moment it first becomes affordable.
local celebrated = {}
local function affordToast(doorName)
	local pg = Player:FindFirstChild("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DoorAffordToast"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 42
	gui.Parent = pg
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.16, 0)
	label.Size = UDim2.new(0.85, 0, 0.07, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ("\u{1F389} YOU CAN AFFORD %s! FOLLOW THE ARROW!"):format(string.upper(doorName))
	label.TextColor3 = Color3.fromRGB(150, 255, 150)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(25, 45, 25)
	stroke.Parent = label
	task.delay(7, function() gui:Destroy() end)
end

--== Which gate should we point at? ==========================================
local function nextUnlockableDoor()
	local owned = {}
	for _, name in ipairs(string.split(OwnedString.Value, " # ")) do
		owned[name] = true
	end
	local coins, stars = Coins.Value, Rebirths.Value

	local best, bestOrder, bestKey, bestName
	for key, data in pairs(DoorStats) do
		local price = data.Stats and data.Stats.Price or 0
		if price > 0 and not owned[key] then
			local model = DoorModels:FindFirstChild(key)  -- purchased doors are destroyed
			local order = data.ClientSided and data.ClientSided.Order or math.huge
			if model and (not bestOrder or order < bestOrder) then
				--.. both server gates must pass, else it won't open for us anyway
				if coins >= price and stars >= (data.Stats.MinRebirths or 0) then
					best, bestOrder, bestKey, bestName = model, order, key, data.Name or key
				end
			end
		end
	end
	if bestKey and not celebrated[bestKey] then
		celebrated[bestKey] = true
		affordToast(bestName)
	end
	return best
end

--.. while carrying a cucumber the compass flips to YOUR vault stall: teleports
--.. are carry-blocked, so the walk home is the route that matters. Resolved
--.. fresh every check -- BankBuilder rebuilds replace the stall instances.
--.. Tutorial-gated: the bank arc drives its own arrows for first-timers.
local function myVaultStall()
	local id = Player:GetAttribute("VaultStallId")
	if not id then return nil end
	local bank = workspace:FindFirstChild("CucumberBank")
	local stalls = bank and bank:FindFirstChild("Stalls")
	return stalls and stalls:FindFirstChild("Stall_" .. tostring(id)) or nil
end

local function anyPanelOpen()
	if DoorFrame and DoorFrame.Visible then return true end -- the unlock prompt
	if Frames then
		for _, f in ipairs(Frames:GetChildren()) do      -- ...and any other panel
			if f:IsA("GuiObject") and f.Visible then return true end
		end
	end
	return false
end

--.. the egg reveal takes the whole screen over; a floor compass bobbing through
--.. the cinematic looks broken. Same "Hatching" attribute the egg system uses.
local function hatchInProgress()
	local playerGui = Player:FindFirstChildOfClass("PlayerGui")
	local eggUi = playerGui and playerGui:FindFirstChild("EggUi")
	local bb = eggUi and eggUi:FindFirstChild("BillboardGui")
	return bb ~= nil and bb:GetAttribute("Hatching") == true
end

--== Drive it ================================================================
local shown = false
local target, nextCheck = nil, 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function setShown(v)
	if v == shown then return end
	shown = v
	arrow.Parent = v and workspace or nil
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now >= nextCheck then
		nextCheck = now + 0.25
		if Player:GetAttribute("CarryingCucumber") ~= nil and DoneTutorial and DoneTutorial.Value == true then
			target = myVaultStall() -- carrying: walk it home to your vault
		else
			target = nextUnlockableDoor()
		end
	end

	local char = Player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	--.. check the cheap nil-tests before anyPanelOpen()'s per-frame Frames scan, so the
	--.. scan is skipped entirely in the common case where no door is pending.
	if Player:GetAttribute("InStarterObby") or Player:GetAttribute("InSnowAvalanche") or Player:GetAttribute("InLavaRun") or Player:GetAttribute("InDesertHunt") or Player:GetAttribute("InVoidBloxout") or not target or not target.Parent or not hrp or hatchInProgress() or anyPanelOpen() then
		setShown(false)
		return
	end

	local doorPos = target:GetPivot().Position
	local flatDir = Vector3.new(doorPos.X - hrp.Position.X, 0, doorPos.Z - hrp.Position.Z)
	if flatDir.Magnitude < 0.5 then         -- standing on the gate: lookAt would be undefined
		setShown(false)
		return
	end
	flatDir = flatDir.Unit

	--.. sit the arrow on the floor AHEAD of the player (toward the gate), not inside them,
	--.. bobbing back and forth along that direction to draw the eye
	local bob = math.sin(now * BOB_SPEED) * BOB_AMPLITUDE
	local spot = hrp.Position + flatDir * (FORWARD_OFFSET + bob)
	rayParams.FilterDescendantsInstances = { char, arrow }
	local hit = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), rayParams)
	local groundY = hit and (hit.Position.Y + GROUND_LIFT) or (hrp.Position.Y - FALLBACK_DROP)

	local from = Vector3.new(spot.X, groundY, spot.Z)
	local to = Vector3.new(doorPos.X, groundY, doorPos.Z)   -- flatten: lies flat, reads as a compass

	setShown(true)
	--.. lookAt aims the CFrame's -Z at the gate, and the TIP is at -Z, so the
	--.. arrowhead genuinely points at the door (build it at +Z and it aims backwards)
	arrow:PivotTo(CFrame.lookAt(from, to))
end)

Player.CharacterRemoving:Connect(function() setShown(false) end)

print("[DoorArrowClient] next-door arrow ready (white, on the floor, tip at -Z).")

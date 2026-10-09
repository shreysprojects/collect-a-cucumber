--[[
	PortalArrowClient
	A white floor arrow (same style as the next-door arrow) that appears under the
	player and points at the nearest ACTIVITY PORTAL once that portal's cooldown is
	up ("READY"). The map is zoned -- one portal per area -- so it only guides you to
	a ready portal you are actually near (MAX_RANGE), i.e. the portal in your zone,
	never across the map at another zone's portal.

	Priority: the next-door arrow always wins. DoorArrowClient parents its
	"NextDoorArrow" to workspace only while its gate is unlockable, so the mere
	presence of that arrow means "the next door is ready" -- and this portal arrow
	hides, so the two never fight for the player's eye.

	Purely LOCAL, like the door arrow: built here and parented to workspace on the
	client, so it never replicates -- no other player sees it.

	GOTCHA (same as the door arrow): Roblox CFrames face along -Z
	(LookVector == -Z). The arrow is modelled tip-at-negative-Z so
	CFrame.lookAt(from, portal) makes the head point AT the portal.

	Readiness mirrors each *PortalClient: GetStatus/StatusChanged return
	{ remaining, unavailable }; READY = not unavailable and remaining counted to 0.
	We LISTEN to StatusChanged AND re-poll GetStatus on a slow timer, because
	StatusChanged only fires on cooldown events -- a single join-time invoke can miss
	the profile-load availability flip and leave a portal stuck "not ready".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--.. mirror DoorArrowClient: hide while ANY click-open panel is up
local Display = PlayerGui:WaitForChild("Display", 30)
local DisplayFrame = Display and Display:WaitForChild("Frame", 10)
local Frames = DisplayFrame and DisplayFrame:WaitForChild("Frames", 10)

local Portals = workspace:WaitForChild("Portals")

--== Config ==================================================================
local GROUND_LIFT = 0.44   -- room for the dark extruded base below the pale top
local FALLBACK_DROP = 2.9  -- HRP -> feet, if the floor raycast misses
local FORWARD_OFFSET = 7   -- sit the arrow ahead of the player, tail near the feet
local BOB_AMPLITUDE = 1.1  -- studs it slides forward/back along the portal direction
local BOB_SPEED = 3.5      -- radians/sec
--.. zoned map: only point at a ready portal within this range (the one in your area),
--.. never across the map at a portal in another zone (nearest ready one still wins)
local MAX_RANGE = 200
local POLL_INTERVAL = 3    -- seconds between GetStatus re-polls per portal
--.. while you're inside any activity there is nothing to guide you toward
local OBBY_ATTRS = { "InStarterObby", "InSnowAvalanche", "InLavaRun", "InDesertHunt", "InVoidBloxout" }

--== Arrow: chunky pale top with dark extrusion, TIP AT -Z (matches next-door arrow)
local arrow = Instance.new("Model")
arrow.Name = "PortalArrow"

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
	p.CanQuery = false   -- must not eat any raycast, nor our own floor probe
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Parent = arrow
	return p
end

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

makeLayer("Side", -0.20, SIDE_THICKNESS, 0.18, 0.12, SIDE_COLOR, Enum.Material.SmoothPlastic)
makeLayer("Top", 0, TOP_THICKNESS, 0, 0, TOP_COLOR, Enum.Material.SmoothPlastic)

local outline = Instance.new("Highlight")
outline.Name = "DarkOutline"
outline.Adornee = arrow
outline.FillTransparency = 1
outline.OutlineColor = SIDE_COLOR
outline.OutlineTransparency = 0
outline.DepthMode = Enum.HighlightDepthMode.Occluded
outline.Parent = arrow

local root = piece("Part", "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(),
	TOP_COLOR, Enum.Material.SmoothPlastic)
root.Transparency = 1
arrow.PrimaryPart = root

--== Portal readiness: one tracker per portal (keyed by name so streaming in/out
--== reuses the same tracker), fed by that portal's own remotes =================
--.. "Starter Portal" -> "StarterPortalRemotes", "Snow Portal" -> "SnowPortalRemotes", ...
local function remotesNameFor(portalName)
	return (portalName:gsub("%s+", "")) .. "Remotes"
end

local trackers = {}  -- [portalName] = { model, deadline, unavailable }

local function trackPortal(model)
	local name = model.Name
	local tracker = trackers[name]
	if not tracker then
		tracker = { deadline = 0, unavailable = true }
		trackers[name] = tracker
	end
	tracker.model = model

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(remotesNameFor(name), 30)
		if not remotes then return end
		local getStatus = remotes:WaitForChild("GetStatus", 10)
		local statusChanged = remotes:WaitForChild("StatusChanged", 10)

		local function apply(status)
			if type(status) ~= "table" then return end
			--.. guard against a stale task from a previous streamed-in instance
			if trackers[name] ~= tracker then return end
			tracker.deadline = os.clock() + math.max(0, tonumber(status.remaining) or 0)
			tracker.unavailable = status.unavailable == true
			tracker.cucumbersRemaining = math.max(0, math.floor(tonumber(status.cucumbersRemaining) or 0))
		end

		if statusChanged then statusChanged.OnClientEvent:Connect(apply) end
		if not getStatus then return end

		--.. LISTEN + POLL: re-poll on a slow timer so readiness self-heals even when
		--.. StatusChanged doesn't fire (e.g. the join-time availability flip)
		while tracker.model == model and model.Parent do
			local ok, status = pcall(function() return getStatus:InvokeServer() end)
			if ok then apply(status) end
			task.wait(POLL_INTERVAL)
		end
	end)
end

for _, model in ipairs(Portals:GetChildren()) do
	if model:IsA("Model") then trackPortal(model) end
end
Portals.ChildAdded:Connect(function(child)
	if child:IsA("Model") then trackPortal(child) end
end)

local function isReady(tracker)
	return (not tracker.unavailable) and (os.clock() >= tracker.deadline) and (tracker.cucumbersRemaining or 0) <= 0
end

--== Suppression checks =======================================================
local function inAnyObby()
	for _, attr in ipairs(OBBY_ATTRS) do
		if Player:GetAttribute(attr) then return true end
	end
	return false
end

local function anyPanelOpen()
	if Frames then
		for _, f in ipairs(Frames:GetChildren()) do
			if f:IsA("GuiObject") and f.Visible then return true end
		end
	end
	return false
end

--.. the next-door arrow always wins: it's on the floor only while its gate is
--.. unlockable, so its presence means "the next door is ready" -> we yield
local function doorArrowShown()
	return workspace:FindFirstChild("NextDoorArrow") ~= nil
end

--.. the egg reveal takes the screen over; no floor compass belongs in it. Same
--.. "Hatching" attribute gate as DoorArrowClient — without this, hiding the door
--.. arrow during hatches just let THIS arrow surface in its place (user report).
local function hatchInProgress()
	local eggUi = PlayerGui:FindFirstChild("EggUi")
	local bb = eggUi and eggUi:FindFirstChild("BillboardGui")
	return bb ~= nil and bb:GetAttribute("Hatching") == true
end

--== Pick the nearest READY portal we're near ================================
local function nearestReadyPortal(hrpPos)
	local best, bestDist
	for _, tracker in pairs(trackers) do
		local model = tracker.model
		if model and model.Parent and isReady(tracker) then
			local pos = model:GetPivot().Position
			local flat = Vector3.new(pos.X - hrpPos.X, 0, pos.Z - hrpPos.Z)
			local dist = flat.Magnitude
			if dist <= MAX_RANGE and (not bestDist or dist < bestDist) then
				best, bestDist = model, dist
			end
		end
	end
	return best
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
	local char = Player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	--.. cheap gates first; door priority + hatch + obby + panels short-circuit the portal scan
	if not hrp or doorArrowShown() or hatchInProgress() or inAnyObby() or anyPanelOpen() then
		setShown(false)
		return
	end

	if now >= nextCheck then
		nextCheck = now + 0.25
		target = nearestReadyPortal(hrp.Position)
	end

	if not target or not target.Parent then
		setShown(false)
		return
	end

	local portalPos = target:GetPivot().Position
	local flatDir = Vector3.new(portalPos.X - hrp.Position.X, 0, portalPos.Z - hrp.Position.Z)
	if flatDir.Magnitude < 0.5 then         -- standing on the portal: lookAt undefined
		setShown(false)
		return
	end
	flatDir = flatDir.Unit

	--.. sit the arrow on the floor AHEAD of the player (toward the portal), bobbing
	local bob = math.sin(now * BOB_SPEED) * BOB_AMPLITUDE
	local spot = hrp.Position + flatDir * (FORWARD_OFFSET + bob)
	rayParams.FilterDescendantsInstances = { char, arrow }
	local hit = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), rayParams)
	local groundY = hit and (hit.Position.Y + GROUND_LIFT) or (hrp.Position.Y - FALLBACK_DROP)

	local from = Vector3.new(spot.X, groundY, spot.Z)
	local to = Vector3.new(portalPos.X, groundY, portalPos.Z)   -- flatten: reads as a compass

	setShown(true)
	--.. lookAt aims -Z at the portal, and the TIP is at -Z, so the head points at it
	arrow:PivotTo(CFrame.lookAt(from, to))
end)

Player.CharacterRemoving:Connect(function() setShown(false) end)

print("[PortalArrowClient] portal arrow ready (yields to the next-door arrow).")

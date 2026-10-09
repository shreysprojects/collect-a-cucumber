--[[
	BarbellClient  (LocalScript, StarterPlayerScripts)
	Every Barbell model (tag "Barbell", attributes Held / Holder / RackCFrame set by
	BenchServer) is placed by this script on each client. All barbell parts are ANCHORED
	(no welds, no physics -- nothing can fall off); the bar is the PrimaryPart and every
	other part carries a BarOffset attribute (its CFrame relative to the bar, stamped by
	BenchServer), so the whole set is moved rigidly from one bar CFrame:
	  * Held = true  -> every frame the bar's centre sits at the midpoint of the holder's
	    two hands (GRIP_OFFSET toward the fingertips) with its axis running hand to hand,
	    kept level, so it rides the press exactly with the hands. The first GRAB_BLEND
	    seconds after the grab blend from where the bar was (the rack) to the hands, so
	    short-armed avatars whose hands stop under the bar see it slide down into their grip.
	  * Held = false -> the set eases back to RackCFrame over RETURN_TIME, then the server's
	    replicated rest pose takes over again.
	Followers: any model tagged "BarFollower" holding an ObjectValue "ServerBar" (the bar it
	rides) and parts with their own BarOffset attributes is posed in the same step, from the
	same bar CFrame -- BenchTierClient's themed barbell copies use this, so they can never
	trail the bar by a frame.
	The parts stay server-owned; the moves here are local overrides.
]]
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local GRIP_OFFSET = 0.15 -- keep in step with BenchServer
local RETURN_TIME = 0.35
local GRAB_BLEND = 0.2 -- seconds: rack -> hands slide right after the grab
local FOLLOWER_TAG = "BarFollower"

--.. [barbell] = {Mode = "held" | "return", From = bar CFrame at the start of the blend, T0 = os.clock()}
local Active = {}
local Followers = {} -- [model] = true, models tagged BarFollower (see header)

for _, m in ipairs(CollectionService:GetTagged(FOLLOWER_TAG)) do Followers[m] = true end
CollectionService:GetInstanceAddedSignal(FOLLOWER_TAG):Connect(function(m) Followers[m] = true end)
CollectionService:GetInstanceRemovedSignal(FOLLOWER_TAG):Connect(function(m) Followers[m] = nil end)

local function PoseParts(container, root, barCF)
	for _, p in ipairs(container:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local off = p:GetAttribute("BarOffset")
			if typeof(off) == "CFrame" then p.CFrame = barCF * off end
		end
	end
end

--.. bar + every BarOffset part + every follower of this bar, from one bar CFrame
local function SetPose(barbell, barCF)
	local root = barbell.PrimaryPart
	if not root then return end
	root.CFrame = barCF
	PoseParts(barbell, root, barCF)
	for m in pairs(Followers) do
		local ref = m:FindFirstChild("ServerBar")
		if ref and ref.Value == root then PoseParts(m, nil, barCF) end
	end
end

local function HandsCFrame(barbell)
	local holderName = barbell:GetAttribute("Holder")
	local character = holderName and holderName ~= "" and workspace:FindFirstChild(holderName)
	local rh = character and character:FindFirstChild("RightHand")
	local lh = character and character:FindFirstChild("LeftHand")
	if not (rh and lh) then return nil end
	local axis = (rh.Position - lh.Position)
	if axis.Magnitude < 0.05 then return nil end
	axis = axis.Unit
	local up = axis:Cross(Vector3.yAxis):Cross(axis)
	if up.Magnitude < 0.05 then return nil end
	up = up.Unit
	local pos = (rh.Position + lh.Position) * 0.5 - (rh.CFrame.UpVector + lh.CFrame.UpVector) * 0.5 * GRIP_OFFSET
	return CFrame.fromMatrix(pos, axis, up) -- cylinder axis = X = hand to hand
end

local function Step(barbell, s)
	local root = barbell.PrimaryPart
	if not root then Active[barbell] = nil return end
	if s.Mode == "held" then
		local target = HandsCFrame(barbell)
		if not target then return end
		local alpha = (os.clock() - s.T0) / GRAB_BLEND
		SetPose(barbell, alpha < 1 and s.From:Lerp(target, math.max(alpha, 0)) or target)
	else -- returning to the rack
		local rack = barbell:GetAttribute("RackCFrame")
		if typeof(rack) ~= "CFrame" then Active[barbell] = nil return end
		local alpha = math.clamp((os.clock() - s.T0) / RETURN_TIME, 0, 1)
		local eased = 1 - (1 - alpha) * (1 - alpha) -- quad out
		SetPose(barbell, s.From:Lerp(rack, eased))
		if alpha >= 1 then Active[barbell] = nil end
	end
end

local function Watch(barbell)
	local function update()
		local root = barbell.PrimaryPart
		if barbell:GetAttribute("Held") then
			local s = Active[barbell]
			if not s or s.Mode ~= "held" then
				Active[barbell] = {Mode = "held", From = root and root.CFrame or CFrame.new(), T0 = os.clock()}
			end
		elseif Active[barbell] and Active[barbell].Mode == "held" then
			Active[barbell] = {Mode = "return", From = root and root.CFrame or CFrame.new(), T0 = os.clock()}
		end
	end
	barbell:GetAttributeChangedSignal("Held"):Connect(update)
	update()
	barbell.AncestryChanged:Connect(function()
		if not barbell:IsDescendantOf(workspace) then Active[barbell] = nil end
	end)
end

for _, b in ipairs(CollectionService:GetTagged("Barbell")) do Watch(b) end
CollectionService:GetInstanceAddedSignal("Barbell"):Connect(Watch)

local function PlaceAll()
	for barbell, s in pairs(Active) do
		Step(barbell, s)
	end
end
--.. ONE placement per frame. RenderStepped (just before the frame renders) gives the frame-exact
--.. fit; Heartbeat only fills in on frames where RenderStepped did not run (Studio stops
--.. RenderStepped while its window is unfocused).
local placedThisFrame = false
RunService:BindToRenderStep("BarbellPlacement", Enum.RenderPriority.Last.Value, function()
	placedThisFrame = true
	PlaceAll()
end)
RunService.Heartbeat:Connect(function()
	if placedThisFrame then
		placedThisFrame = false -- RenderStepped already placed the bars this frame
		return
	end
	PlaceAll()
end)

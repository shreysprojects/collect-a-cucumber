--[[
	PetRoamClient  (LocalScript, StarterPlayerScripts)
	Animates every plot pet (models tagged "PlotPet" by PetHatchService) for this client.
	The pets are ANCHORED on the server and never move there; the server only plans roaming legs
	as attributes (RoamFrom / RoamTo world points on the plot top, RoamStart / RoamEnd on the
	server clock, RoamGroundY). Every client replays the same plan from
	workspace:GetServerTimeNow(), so all players see the same walk, perfectly smooth, at zero
	network cost per frame.

	Movement feel = the Zombie Cucumber Game's PetController.Movement: the visible artwork is
	planted on the ground (rootToVisibleBottom), a procedural step bounce
	|sin(t * WALK_STEP_RATE + phase)| * WALK_BOUNCE_HEIGHT while walking, a spring-like settle
	toward the planned point (the BodyPosition feel) and a smooth turn toward the direction of
	travel (the BodyGyro feel). Pets do NOT follow the player -- they wander their owner's base.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "PlotPet"
local WALK_STEP_RATE = 9 -- zombie Movement.WALK_STEP_RATE
local WALK_BOUNCE_HEIGHT = 0.7 -- zombie Movement.WALK_BOUNCE_HEIGHT
local SETTLE_RATE = 10 -- 1/s: how briskly the pet homes on the planned point
local TURN_RATE = 8 -- 1/s: yaw smoothing
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local pets = {} -- [model] = state

--.. zombie Movement.rootToVisibleBottom (+ the local collision strip it does)
local function RootToVisibleBottom(pet, root)
	local bottom = math.huge
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			if d.Transparency < 0.95 then
				local cf, half = d.CFrame, d.Size * 0.5
				local yExtent = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
				bottom = math.min(bottom, d.Position.Y - yExtent)
			end
		end
	end
	if bottom == math.huge then
		local cf, size = pet:GetBoundingBox()
		bottom = cf.Position.Y - size.Y * 0.5
	end
	return root.Position.Y - bottom
end

local function YawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function GroundY(model)
	local y = tonumber(model:GetAttribute("RoamGroundY"))
	if y then return y end
	local plot = PLOTS:FindFirstChild(tostring(model:GetAttribute("Plot")))
	if plot and plot:IsA("BasePart") then return plot.Position.Y + plot.Size.Y * 0.5 end
	return model:GetPivot().Position.Y
end

local function Attach(model)
	if pets[model] or not model:IsA("Model") then return end
	pets[model] = false -- reserved while the parts stream in
	task.spawn(function()
		local root = model.PrimaryPart or model:WaitForChild("Root", 10)
		if not root then pets[model] = nil return end
		--.. streaming: wait until the whole model is here before measuring it
		local wanted = tonumber(model:GetAttribute("PartCount")) or 0
		local deadline = os.clock() + 5
		while os.clock() < deadline do
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
			if n >= wanted then break end
			task.wait(0.1)
		end
		if not model.Parent or pets[model] ~= false then return end
		local p = root.Position
		pets[model] = {
			Root = root;
			RootToBottom = RootToVisibleBottom(model, root);
			Yaw = YawOf(root.CFrame);
			TargetYaw = YawOf(root.CFrame);
			Phase = tonumber(model:GetAttribute("RoamPhase")) or math.random() * math.pi * 2;
			Pos = Vector3.new(p.X, 0, p.Z);
		}
	end)
end

local function Detach(model)
	pets[model] = nil
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Attach(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Attach)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Detach)

local function ShortestAngle(a)
	return (a + math.pi) % (math.pi * 2) - math.pi
end

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	local settle = 1 - math.exp(-dt * SETTLE_RATE)
	local turn = 1 - math.exp(-dt * TURN_RATE)
	for model, s in pairs(pets) do
		if s then
			if not model.Parent or not s.Root.Parent then
				Detach(model)
			else
				local from = model:GetAttribute("RoamFrom")
				local to = model:GetAttribute("RoamTo")
				local t0 = tonumber(model:GetAttribute("RoamStart"))
				local t1 = tonumber(model:GetAttribute("RoamEnd"))
				local target, walking
				if typeof(from) == "Vector3" and typeof(to) == "Vector3" and t0 and t1 and t1 > t0 then
					local a = (now - t0) / (t1 - t0)
					if a <= 0 then
						target = from
					elseif a >= 1 then
						target = to
					else
						target = from:Lerp(to, a)
						walking = true
						local d = to - from
						if d.X * d.X + d.Z * d.Z > 0.04 then s.TargetYaw = math.atan2(-d.X, -d.Z) end
					end
				elseif typeof(to) == "Vector3" then
					target = to
				else
					target = s.Pos
				end
				s.Pos = s.Pos:Lerp(Vector3.new(target.X, 0, target.Z), settle)
				s.Yaw += ShortestAngle(s.TargetYaw - s.Yaw) * turn
				local step = walking and math.abs(math.sin(now * WALK_STEP_RATE + s.Phase)) * WALK_BOUNCE_HEIGHT or 0
				model:PivotTo(CFrame.new(s.Pos.X, GroundY(model) + s.RootToBottom + step, s.Pos.Z) * CFrame.Angles(0, s.Yaw, 0))
			end
		end
	end
end)

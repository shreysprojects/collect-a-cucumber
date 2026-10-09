--[[
	PetRoamClient  (LocalScript, StarterPlayerScripts)
	Animates every plot pet (models tagged "PlotPet" by PetService) for this client -- the ONLY
	script that PivotTo's a pet model.
	The pets are ANCHORED on the server and never move there; the server only plans roaming legs
	as attributes on the pet model, and every client replays the same plan from
	workspace:GetServerTimeNow(), so all players see the same walk, perfectly smooth, at zero
	network cost per frame.

	Movement feel = the Zombie Cucumber Game's PetController.Movement: the visible artwork is
	planted on the ground (rootToVisibleBottom), a procedural step bounce
	|sin(t * WALK_STEP_RATE + phase)| * WALK_BOUNCE_HEIGHT while walking and a smooth turn toward
	the direction of travel (the BodyGyro feel). Pets do NOT follow the player -- they wander their
	owner's base.

	SHARED MOTION (2026-09-22, pet-system polish): rewritten around ReplicatedStorage.Modules.PetMotion.
	  * PetService publishes every leg as RoamFrom / RoamTo / RoamStart / RoamEnd / RoamGroundY and
	    then RoamSeq LAST. A pet's segment cache changes only when RoamSeq changes AND
	    PetMotion.ReadSegment returns a complete segment; otherwise the last complete segment keeps
	    playing, so a half-replicated update never makes a pet jump. (A model without RoamSeq -- an
	    older server -- is re-read every frame.)
	  * Position = PetMotion.Sample(segment, workspace:GetServerTimeNow()) directly: the same point the
	    server uses for range checks, shot origins and saved positions. The old SETTLE_RATE low-pass
	    (it trailed the plan by ~0.5-0.8 studs) is gone; legs start ROAM_LEAD in the future on the
	    server, so a new leg arrives before it begins.
	  * Facing = the segment heading, or FxAimAt while FxAimUntil is still ahead (client-local
	    attributes PetEffectsClient writes when this pet shoots). After FxShotAt a SHOT_TIME squash:
	    the pet dips as if squashed to SHOT_SQUASH of its height and springs back, with a small recoil
	    lean -- pivot offset only, the model is never scaled.
	  * Streaming: when a pet's Root streams out the pet is detached but WATCHED (model.DescendantAdded);
	    when the Root comes back while the tag is still there it is re-attached (it used to stay frozen
	    at the server pivot for the rest of the session). The watch also checks once when it starts,
	    so a Root that streamed back in before the watch existed is not missed.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TAG = "PlotPet"
local WALK_STEP_RATE = 9 -- zombie Movement.WALK_STEP_RATE
local WALK_BOUNCE_HEIGHT = 0.7 -- zombie Movement.WALK_BOUNCE_HEIGHT
local TURN_RATE = 8 -- 1/s: yaw smoothing
local SHOT_TIME = 0.15 -- s: the shooting squash after FxShotAt
local SHOT_SQUASH = 0.85 -- the squash starts at 85 % of the height and springs back to 100 %
local SHOT_LEAN = math.rad(8) -- recoil lean (tilted back) at the start of the squash
local AIM_MIN = 0.2 -- studs (XZ) the aim point must be away before the pet turns to it
local PART_WAIT = 5 -- s the streaming guard waits for PartCount parts

--..Pure helpers (2026-09-22): the unit tests load this source with loadstring(src)("__core")..--
local Core = {}

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.Finite = Finite

function Core.ShortestAngle(a)
	return (a + math.pi) % (math.pi * 2) - math.pi
end

--.. the segment cache. The server writes RoamSeq LAST, so a changed RoamSeq means "the segment is
--.. complete": only then is it re-read, and only a complete read replaces the cache (a failed read
--.. keeps the last complete segment and retries next frame). seq == nil (no RoamSeq at all) re-reads
--.. every call. read(arg) = PetMotion.ReadSegment(model). Returns true when the cache changed.
function Core.RefreshSegment(state, seq, read, arg)
	if seq ~= nil and seq == state.Seq and state.Segment ~= nil then return false end
	local seg = read(arg)
	if type(seg) ~= "table" then return false end
	state.Segment = seg
	state.Seq = seq
	return true
end

--.. the yaw that faces `target` from `pos` (nil when the target is too close to give a direction)
function Core.YawTowards(pos, target)
	local dx, dz = target.X - pos.X, target.Z - pos.Z
	if dx * dx + dz * dz <= AIM_MIN * AIM_MIN then return nil end
	return math.atan2(-dx, -dz)
end

--.. the shooting squash at `now` for a shot at `shotAt`: dip (studs, <= 0) + lean (radians)
function Core.ShotPose(now, shotAt, rootToBottom)
	if not Finite(now) or not Finite(shotAt) then return 0, 0 end
	local t = now - shotAt
	if t < 0 or t >= SHOT_TIME then return 0, 0 end
	local k = t / SHOT_TIME
	local scaleY = SHOT_SQUASH + (1 - SHOT_SQUASH) * k -- 0.85 -> 1
	local height = Finite(rootToBottom) and math.max(rootToBottom, 0) or 0
	return -(1 - scaleY) * height, SHOT_LEAN * (1 - k)
end

if ... == "__core" then return Core end -- unit tests only: a LocalScript is never started with arguments

local PetMotion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetMotion"))

local pets = {} -- [model] = state, or false while reserved (parts streaming in)
local tokens = {} -- [model] = the reservation of the Attach that owns pets[model] == false
local watchers = {} -- [model] = DescendantAdded connection while a tagged pet waits for its Root

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

local function RootOf(model)
	local root = model.PrimaryPart
	if root and root.Parent then return root end
	root = model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then return root end
	return nil
end

local Attach

local function Unwatch(model)
	local conn = watchers[model]
	if conn then
		watchers[model] = nil
		conn:Disconnect()
	end
end

local function Reattach(model)
	if watchers[model] and pets[model] == nil and CollectionService:HasTag(model, TAG) and RootOf(model) then
		Unwatch(model)
		Attach(model)
	end
end

--.. the Root streamed out but the model (and its tag) stayed: re-attach once the Root is back
local function Watch(model)
	if watchers[model] or not model.Parent or not CollectionService:HasTag(model, TAG) then return end
	watchers[model] = model.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") then return end
		task.defer(Reattach, model) -- the PrimaryPart reference resolves after the part itself arrives
	end)
	--.. a replacement Root may already be here (it streamed back in before anyone was watching,
	--.. e.g. during Attach's PartCount wait): its DescendantAdded is gone, so check once now
	task.defer(Reattach, model)
end

function Attach(model)
	if pets[model] ~= nil or not model:IsA("Model") then return end
	Unwatch(model)
	local token = {}
	pets[model] = false -- reserved while the parts stream in
	tokens[model] = token
	task.spawn(function()
		local root = RootOf(model) or model:WaitForChild("Root", 10)
		if tokens[model] ~= token then return end
		if not root or not root:IsA("BasePart") then
			pets[model], tokens[model] = nil, nil
			Watch(model)
			return
		end
		--.. streaming: wait until the whole model is here before measuring it
		local wanted = tonumber(model:GetAttribute("PartCount")) or 0
		local deadline = os.clock() + PART_WAIT
		while os.clock() < deadline do
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
			if n >= wanted then break end
			task.wait(0.1)
		end
		if tokens[model] ~= token then return end
		tokens[model] = nil
		if not model.Parent or not root.Parent then
			pets[model] = nil
			Watch(model)
			return
		end
		pets[model] = {
			Root = root;
			RootToBottom = RootToVisibleBottom(model, root);
			Yaw = YawOf(root.CFrame);
			TargetYaw = YawOf(root.CFrame);
			Phase = tonumber(model:GetAttribute("RoamPhase")) or math.random() * math.pi * 2;
			Seq = nil; -- RoamSeq of the cached segment
			Segment = nil; -- the last COMPLETE PetMotion segment
		}
	end)
end

--.. keepWatching: the Root streamed out while the tag stayed (watch for its return)
local function Detach(model, keepWatching)
	pets[model] = nil
	tokens[model] = nil
	if keepWatching then Watch(model) else Unwatch(model) end
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Attach(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Attach)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model) Detach(model, false) end)

local function Step(model, s, now, turn)
	Core.RefreshSegment(s, model:GetAttribute("RoamSeq"), PetMotion.ReadSegment, model)
	local pos, walking, heading = PetMotion.Sample(s.Segment, now)
	if not pos then return end -- no complete segment yet: the pet stays where the server put it
	if heading then s.TargetYaw = math.atan2(-heading.X, -heading.Z) end
	--.. shooting: face the target while the aim holds (PetEffectsClient's local attributes)
	local aimUntil = model:GetAttribute("FxAimUntil")
	if Finite(aimUntil) and aimUntil > now then
		local aimAt = model:GetAttribute("FxAimAt")
		if typeof(aimAt) == "Vector3" then
			local yaw = Core.YawTowards(pos, aimAt)
			if yaw then s.TargetYaw = yaw end
		end
	end
	s.Yaw += Core.ShortestAngle(s.TargetYaw - s.Yaw) * turn
	local step = walking and math.abs(math.sin(now * WALK_STEP_RATE + s.Phase)) * WALK_BOUNCE_HEIGHT or 0
	local dip, lean = Core.ShotPose(now, model:GetAttribute("FxShotAt"), s.RootToBottom)
	local cf = CFrame.new(pos.X, pos.Y + s.RootToBottom + step + dip, pos.Z) * CFrame.Angles(0, s.Yaw, 0)
	if lean ~= 0 then cf *= CFrame.Angles(lean, 0, 0) end
	model:PivotTo(cf)
end

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	local turn = 1 - math.exp(-dt * TURN_RATE)
	for model, s in pairs(pets) do
		if s then
			if not model.Parent or not s.Root.Parent then
				Detach(model, true)
			else
				Step(model, s, now, turn)
			end
		end
	end
end)

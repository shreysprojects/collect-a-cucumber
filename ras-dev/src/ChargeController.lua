--[[---------------------------------------DESCRIPTION------------------------------------------
	Client visual animation controller. Use one controller per character at a time.
	Contains NO damage/projectile authority and sends NO remotes automatically.
	Run on every observing client if using procedural playback in a multiplayer game.

	local controller = ChargeController.new(character, launcherId, {
		OnFire = function(chargePercent, id, origin, direction) end, -- the ball leaves the launcher
	})
	controller:BeginCharge()             -- once: the ready pose (launcher carried on the pad)
	controller:SetChargePercent(percent) -- 0 - 100, every frame while the player HOLDS to charge
	controller:SetHolding(bool)          -- optional: holding without a charge value yet
	controller:Release()                 -- once, when the shot goes out
	controller:Cancel()                  -- stop without firing
	controller:Destroy()                 -- unequip / switch / cleanup

	Two ways to animate, chosen per launcher:
	  * CLIPS (SnowballAnimations/LauncherClips/Lnn, authored in Blender, see ClipPlayer): Ready loop
	    while carried, ChargeLo/ChargeHi loops blended by the live charge while holding, Fire
	    once on release. The whole body is posed (legs too, unless the character is walking or
	    in the air) plus the launcher in the hand (LauncherGrip). LauncherBall shows the snowball
	    in / leaving the launcher; OnFire gets the world point it left from. Launchers that touch
	    the snow (a Tip point and Tip tracks in the clip: the shovel, the scoop) are tilted in the
	    hand so the tip keeps the authored height above the floor on any avatar's proportions.
	  * PROCEDURAL (AnimationMath + Profiles), the upper body only, for any launcher without clips.

--------------------------------------------------------------------------------------------]]--

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Math = require(script.Parent.AnimationMath)
local ClipPlayer = require(script.Parent.ClipPlayer)
local LauncherBall = require(script.Parent.LauncherBall)

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()

local Controller = {}
Controller.__index = Controller

local active = setmetatable({}, { __mode = "k" })

-- Body joints a clip may drive (by the part each joint moves). The launcher grip is extra.
local CLIP_JOINTS = {
	"LowerTorso", "UpperTorso", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
local LOWER_BODY = {
	LowerTorso = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
local HOLD_BLEND = 0.2 -- ready <-> charge loops
local RELEASE_BLEND = 0.08 -- charge pose -> fire clip
local FADE_TIME = 0.25
local LEGS_BLEND = 0.15
local STANDARD_HIP = 3.0 -- clips are authored on a HipHeight 2 rig: floor 3 studs under the root
local TIP_CONTACT = 0.8 -- the floor-contact correction works while the authored tip is lower than this (studs)
local TIP_GAIN = 0.5 -- share of the remaining tip-height error removed per frame
local TIP_MAX = 0.5 -- radians the launcher may be tilted in the hand for it

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function mix(a, b, t, names)
	local r = {}
	for _, name in ipairs(names) do
		local ca, cb = a[name], b[name]
		if ca and cb then
			r[name] = ca:Lerp(cb, t)
		else
			r[name] = cb or ca
		end
	end
	return r
end

local function finite(x)
	return type(x) == "number" and x == x and math.abs(x) < math.huge
end

-- Avatar Joint Upgrade (the Studio default) puts AnimationConstraints on R15
-- characters instead of Motor6Ds. Part1 is a read-only alias on those.
local function drivenPart(joint)
	if joint:IsA("Motor6D") then
		return joint.Part1
	end
	local attachment = joint.Attachment1
	if attachment then
		return attachment.Parent
	end
	return joint.Part1
end

local function collectJoints(character, names)
	local wanted = {}
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part then
			wanted[part] = name
		end
	end

	local joints = {}
	local launcherName = mountainConfig.LAUNCHER.InstanceName
	for _, d in character:GetDescendants() do
		if not (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) then
			continue
		end
		if d.Name == "LauncherGrip" or d:FindFirstAncestor(launcherName) then
			continue
		end
		local name = wanted[drivenPart(d)]
		if not name then
			continue
		end
		if not joints[name] or d:IsA("AnimationConstraint") then
			joints[name] = d
		end
	end
	return joints
end

local function jointsLive(joints, names)
	for _, name in ipairs(names) do
		local joint = joints[name]
		if not (joint and joint.Parent) then
			return false
		end
	end
	return true
end

-- Heartbeat may try to bind before appearance finishes replacing the dummy R15.
function Controller.Ready(character)
	if not (character and character.Parent) then
		return false, "loading"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "loading"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "An R15 character is required"
	end
	local joints = collectJoints(character, Math.Joints)
	if not jointsLive(joints, Math.Joints) then
		return false, "loading"
	end
	return true
end

function Controller.new(character, launcherId, options)
	assert(RunService:IsClient(), "ChargeController runs on a client")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid and humanoid.RigType == Enum.HumanoidRigType.R15, "An R15 character is required")
	assert(Math.Profiles[launcherId], "Launcher ID must be 1-30")
	assert(not active[character], "Destroy the previous controller before creating another")

	local self = setmetatable({}, Controller)
	self.Character, self.Humanoid, self.Options = character, humanoid, options or {}
	self.State, self.Phase, self.Weight, self.Charge, self.TargetCharge = "idle", 0, 0, 0, 0
	self.Base, self.Connections = {}, {}
	self.Clip = ClipPlayer.Load(launcherId)

	if self.Clip then
		local clip = self.Clip
		self.Names = CLIP_JOINTS
		self.Joints = collectJoints(character, CLIP_JOINTS)
		-- ChargeController users read Profile.id / fireAt / duration
		self.Profile = {
			id = launcherId,
			name = clip.Name,
			family = "clip",
			fireAt = clip.FireAt,
			duration = ClipPlayer.Length(clip, "Fire"),
			period = ClipPlayer.Length(clip, "ChargeLo"),
		}
		self.ReadyTime, self.ChargeTime, self.HoldBlend, self.LegWeight = 0, 0, 0, 1
		self.TipCorrection = 0
		self.Ball = LauncherBall.new(character, clip)
		self.Samples = { Ready = {}, Lo = {}, Hi = {}, Fire = {} }
	else
		self.Names = Math.Joints
		self.Joints = collectJoints(character, Math.Joints)
		self.Profile = Math.Profiles[launcherId]
	end
	for _, name in ipairs(Math.Joints) do
		assert(self.Joints[name], "Missing R15 joint for " .. name)
	end

	active[character] = self
	self.Pose = if self.Clip then self:_clipPose(0) else Math.Charge(self.Profile, 0, 0)

	-- Restore the last Animator input before it evaluates again: prevents accumulating
	-- our own offset when the Animator isn't writing a particular joint this frame.
	table.insert(self.Connections, RunService.PreAnimation:Connect(function()
		for name, value in pairs(self.Base) do
			local joint = if name == "Launcher" then self.Grip else self.Joints[name]
			if joint and joint.Parent then
				joint.Transform = value
			end
		end
	end))
	table.insert(self.Connections, RunService.PreSimulation:Connect(function(dt)
		self:_step(dt)
	end))
	if self.Ball then
		-- after the simulation has moved the parts to this frame's pose
		table.insert(self.Connections, RunService.PreRender:Connect(function(dt)
			self:_ballStep(dt)
		end))
	end
	table.insert(self.Connections, humanoid.Died:Connect(function()
		self:Destroy()
	end))
	table.insert(self.Connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:Destroy()
		end
	end))

	return self
end

function Controller:BeginCharge()
	-- a press while the last pose is still fading out picks the charge up from there
	if self.Destroyed or (self.State ~= "idle" and self.State ~= "fading") then
		return false
	end
	self.State, self.TargetCharge, self.Charge, self.Phase = "charging", 0, 0, 0
	self.Elapsed = 0
	self.StartWeight = self.Weight -- 0 from idle, part way when picked up while fading
	self.Holding, self.HoldStart = false, nil
	return true
end

function Controller:SetHolding(holding)
	if self.State ~= "charging" then
		return
	end
	holding = holding == true
	if holding and not self.Holding then
		self.HoldStart = os.clock()
		self.ChargeTime = 0
	end
	self.Holding = holding
end

function Controller:SetChargePercent(percent)
	if not finite(percent) then
		return
	end
	if self.State == "charging" then
		if not self.Holding then
			self:SetHolding(true)
		end
		self.TargetCharge = math.clamp(percent / 100, 0, 1)
	end
end

-- expectedBall: observers that only learnt about the shot from the ride ball pass it here, so the
-- visual ball hands over to it instead of treating it as the previous ride.
function Controller:Release(expectedBall)
	if self.Destroyed or self.State ~= "charging" then
		return false
	end
	self.State, self.Elapsed, self.DidFire = "firing", 0, false
	if self.Ball then
		self.Ball:Arm(expectedBall)
	end
	-- a copy: clip samples reuse their tables every frame
	self.ReleasePose, self.ReleaseCharge = table.clone(self.Pose), self.TargetCharge
	-- Start with the displayed charge so a rapid final input change cannot snap the arms.
	self.VisualReleaseCharge = self.Charge
	return true
end

function Controller:Cancel()
	if self.Destroyed or self.State == "idle" then
		return
	end
	self.State, self.Elapsed = "fading", 0
	self.FadeWeight = self.Weight
	self.Holding = false
end

-- The launcher currently in the hand and its grip joint (the model is replaced on re-equip).
function Controller:_grip()
	local launcher = self.Character:FindFirstChild(mountainConfig.LAUNCHER.InstanceName)
	local grip = launcher and launcher:FindFirstChild("LauncherGrip", true)
	if grip ~= self.Grip then
		self.Grip = grip
		self.Base.Launcher = nil
		self.GripFrame = nil
		if grip and grip:IsA("Motor6D") and grip.Part1 then
			-- clips pose the launcher about its grip pivot; the weld may be built about the part
			self.GripFrame = grip.C1:Inverse() * grip.Part1.PivotOffset
		end
	end
	return grip
end

function Controller:_legScale()
	local root = self.Character:FindFirstChild("HumanoidRootPart")
	local hip = self.Humanoid.HipHeight + (if root then root.Size.Y / 2 else 1)
	return math.clamp(hip / STANDARD_HIP, 0.4, 2.5)
end

-- Authored tip height above the floor for the pose _clipPose just built (nil = no Tip tracks).
function Controller:_expectedTip()
	local clip = self.Clip
	if not (clip.Meta and clip.Meta.Tip) then
		return nil
	end
	if self.State == "firing" then
		return ClipPlayer.Track(clip, "Fire", "Tip", self.Elapsed)
	end
	local ready = ClipPlayer.Track(clip, "Ready", "Tip", self.ReadyTime)
	if not ready then
		return nil
	end
	local k = smooth(self.HoldBlend)
	if k <= 0 then
		return ready
	end
	local lo = ClipPlayer.Track(clip, "ChargeLo", "Tip", self.ChargeTime) or ready
	local hi = ClipPlayer.Track(clip, "ChargeHi", "Tip", self.ChargeTime) or lo
	local q = smooth(self.Charge)
	return ready + ((lo + (hi - lo) * q) - ready) * k
end

function Controller:_clipPose(dt)
	local clip = self.Clip
	local s = self.Samples
	local pose
	if self.State == "firing" then
		pose = ClipPlayer.Sample(clip, "Fire", self.Elapsed, s.Fire)
		local blend = smooth(self.Elapsed / RELEASE_BLEND)
		if blend < 1 and self.ReleasePose then
			pose = mix(self.ReleasePose, pose, blend, self.Names)
			pose.Launcher = (self.ReleasePose.Launcher or pose.Launcher):Lerp(s.Fire.Launcher, blend)
		end
		return pose
	end
	self.ReadyTime += dt
	local ready = ClipPlayer.Sample(clip, "Ready", self.ReadyTime, s.Ready)
	local target = if self.Holding then 1 else 0
	local step = dt / HOLD_BLEND
	self.HoldBlend = math.clamp(self.HoldBlend + (if target > self.HoldBlend then step else -step), 0, 1)
	if self.HoldBlend <= 0 then
		return ready
	end
	self.ChargeTime += dt
	local lo = ClipPlayer.Sample(clip, "ChargeLo", self.ChargeTime, s.Lo)
	local hi = ClipPlayer.Sample(clip, "ChargeHi", self.ChargeTime, s.Hi)
	local names = self.Names
	local charged = mix(lo, hi, smooth(self.Charge), names)
	charged.Launcher = lo.Launcher:Lerp(hi.Launcher, smooth(self.Charge))
	local k = smooth(self.HoldBlend)
	pose = mix(ready, charged, k, names)
	pose.Launcher = ready.Launcher:Lerp(charged.Launcher, k)
	return pose
end

function Controller:_fire()
	self.DidFire = true
	local origin, direction
	if self.Ball then
		origin, direction = self.Ball:Launch(self.Options.PredictSpeed and self.Options.PredictSpeed(self.ReleaseCharge) or nil)
	end
	if self.Options.OnFire then
		-- User code can't interrupt pose cleanup or cause a duplicate release.
		local ok, err = pcall(self.Options.OnFire, self.ReleaseCharge * 100, self.Profile.id, origin, direction)
		if not ok then
			warn("Snowball OnFire callback: " .. tostring(err))
		end
	end
end

function Controller:_step(dt)
	if self.Destroyed then
		return
	end
	if self.State == "idle" then
		return
	end
	self.Elapsed = (self.Elapsed or 0) + dt

	if self.State == "charging" then
		local from = self.StartWeight or 0
		self.Weight = from + (1 - from) * smooth(self.Elapsed / 0.2)
		self.Charge += (self.TargetCharge - self.Charge) * (1 - math.exp(-dt / 0.10))
		if self.Clip then
			self.Pose = self:_clipPose(dt)
			self.ExpectedTip = self:_expectedTip()
		else
			-- Integrated phase: changing charge never restarts the cycle.
			self.Phase = (self.Phase + dt / self.Profile.period) % 1
			self.Pose = Math.Charge(self.Profile, self.Phase, self.Charge)
		end
	elseif self.State == "firing" then
		self.Weight = math.min(1, self.Weight + dt / 0.12)
		if self.Clip then
			self.Pose = self:_clipPose(dt)
			self.ExpectedTip = self:_expectedTip()
		else
			local target = Math.Fire(self.Profile, self.Elapsed, self.VisualReleaseCharge)
			self.Pose = mix(self.ReleasePose, target, smooth(self.Elapsed / 0.075), self.Names)
		end
		if not self.DidFire and self.Elapsed >= self.Profile.fireAt then
			self:_fire()
		end
		if self.Destroyed then
			return
		end
		if self.State == "firing" and self.Elapsed >= self.Profile.duration then
			self.State, self.Elapsed, self.FadeWeight = "fading", 0, self.Weight
		end
	elseif self.State == "fading" then
		self.Weight = self.FadeWeight * (1 - smooth(self.Elapsed / FADE_TIME))
		if self.Elapsed >= FADE_TIME then
			self.State, self.Weight = "idle", 0
		end
	end

	-- Legs: walking or airborne on the pad hands the lower body back to the Animator
	-- (only while just carrying the launcher; charging and firing keep the stance).
	local legTarget = 1
	if self.Clip then
		local walking = self.Humanoid.MoveDirection.Magnitude > 0.1
		local airborne = self.Humanoid.FloorMaterial == Enum.Material.Air
		if (walking and not self.Holding and self.State ~= "firing") or airborne then
			legTarget = 0
		end
		local rate = dt / LEGS_BLEND
		self.LegWeight = math.clamp(self.LegWeight + (if legTarget > self.LegWeight then rate else -rate), 0, 1)
	end

	local legScale = if self.Clip then self:_legScale() else 1
	for name, joint in pairs(self.Joints) do
		if joint and joint.Parent then
			local target = self.Pose[name]
			if target then
				self.Base[name] = joint.Transform
				local weight = self.Weight
				if LOWER_BODY[name] then
					weight *= self.LegWeight
				end
				if name == "LowerTorso" and legScale ~= 1 then
					target = target - target.Position + target.Position * legScale
				end
				joint.Transform = self.Base[name]:Lerp(target, weight)
			end
		end
	end
	if self.Clip then
		local grip = self:_grip()
		local target = self.Pose.Launcher
		if grip and grip.Parent and target and self.GripFrame then
			if self.TipCorrection ~= 0 and self.TipAxis then
				target = target * CFrame.fromAxisAngle(self.TipAxis, self.TipCorrection)
			end
			local want = self.GripFrame * target * self.GripFrame:Inverse()
			self.Base.Launcher = CFrame.identity
			grip.Transform = CFrame.identity:Lerp(want, self.Weight)
		end
	end
end

-- Floor contact: after the simulation has placed this frame's pose, compare the launcher tip's
-- height above the floor with the authored one and tilt the launcher in the hand (about the
-- grip, in the vertical plane through the tip) to close the gap over a few frames. Longer legs
-- or shorter arms than the authoring rig would otherwise leave a shovel scraping the air.
function Controller:_tipStep(dt)
	local expected = self.ExpectedTip
	local ball = self.Ball
	local active = expected ~= nil and expected < TIP_CONTACT and self.Weight > 0.5 and self.LegWeight > 0.5
		and (self.State == "charging" or self.State == "firing")
	local tipCF = active and ball:PointCFrame("Tip")
	local launcher = tipCF and self.Character:FindFirstChild(mountainConfig.LAUNCHER.InstanceName)
	local root = launcher and self.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		-- ease back to the authored grip
		self.TipCorrection *= math.exp(-dt / 0.15)
		if math.abs(self.TipCorrection) < 1e-3 then
			self.TipCorrection = 0
		end
		return
	end
	local pivot = launcher:GetPivot()
	local floorY = root.Position.Y - (self.Humanoid.HipHeight + root.Size.Y / 2)
	local err = (tipCF.Position.Y - floorY) - expected
	local v = tipCF.Position - pivot.Position
	local axis = v:Cross(Vector3.yAxis)
	local reach = Vector3.new(v.X, 0, v.Z).Magnitude
	if axis.Magnitude < 1e-3 or reach < 0.5 then
		return
	end
	local w = math.clamp(1 - expected / TIP_CONTACT, 0, 1)
	local turn = -err / reach * TIP_GAIN * w
	self.TipCorrection = math.clamp(self.TipCorrection + turn, -TIP_MAX, TIP_MAX)
	self.TipAxis = pivot:VectorToObjectSpace(axis.Unit)
end

-- Ball in the launcher before the shot, the flying copy after it.
function Controller:_ballStep(dt)
	local ball = self.Ball
	if not ball or self.Destroyed then
		return
	end
	self:_tipStep(dt)
	if ball:IsFlying() then
		ball:ChargeFx(false)
		ball:Step(dt)
		return
	end
	if self.State == "firing" and not self.DidFire then
		ball:WatchEarly()
	end
	local show = self.Clip.Ball and self.Clip.Ball.Show or "Never"
	local visible = false
	if self.State == "charging" or (self.State == "firing" and not self.DidFire) then
		if show == "Always" then
			visible = true
		elseif show == "Charge" then
			visible = self.Holding or self.State == "firing"
		elseif show == "Fire" then
			visible = self.State == "firing" and self.Elapsed >= (self.Clip.BallAppearAt or self.Profile.fireAt)
		end
	end
	local holdingFor = if self.Holding and self.HoldStart then os.clock() - self.HoldStart else nil
	if self.State == "firing" and not self.DidFire then
		holdingFor = math.huge
	end
	ball:Seat(visible and self.Weight > 0.5, holdingFor)
	ball:ChargeFx(self.Holding and self.State == "charging", self.Charge)
end

function Controller:IsLive()
	return not self.Destroyed and jointsLive(self.Joints, Math.Joints)
end

function Controller:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	for name, transform in pairs(self.Base) do
		local joint = if name == "Launcher" then self.Grip else self.Joints[name]
		if joint and joint.Parent then
			joint.Transform = transform
		end
	end
	if self.Ball then
		local ball = self.Ball
		if ball:IsFlying() then
			-- let the copy finish handing over to the real ball
			local connection
			connection = RunService.PreRender:Connect(function(dt)
				ball:Step(dt)
				if not ball:IsFlying() then
					connection:Disconnect()
					ball:Destroy()
				end
			end)
		else
			ball:Destroy()
		end
	end
	if active[self.Character] == self then
		active[self.Character] = nil
	end
	self.State = "destroyed"
end

return Controller

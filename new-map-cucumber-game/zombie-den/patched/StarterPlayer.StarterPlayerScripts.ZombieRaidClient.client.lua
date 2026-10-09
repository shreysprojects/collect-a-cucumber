--[[
	ZombieRaidClient  (LocalScript, StarterPlayerScripts)  2026-09-10
	The client half of the night raid: the den cutscene and the raid notifications.

	  Cutscene   {Kind = "Cutscene", Focus, Seconds}: fade to black, Scriptable camera on the ZOMBIE
	             NIGHT door (the arch on the night wall at the lobby entrance) from inside the lobby,
	             starting wide and high enough to read the sign and pushing in to the doorway (A -> B
	             over Seconds, look point 12 -> 5 studs up, FOV 62 -> 54, a shake while the first rows
	             step out), "THE ZOMBIES ARE COMING!", then fade, camera back to the character, fade
	             in. Ends on "CutsceneEnd" or by itself after Seconds + 1.5 (a watchdog, so a lost
	             event never strands the camera).
	  Messages   RaidStart / Grabbed / Stolen / Saved / BuildBroken / ZombiesWin ("The zombies win.")
	             / Survived / Dawn -> ReplicatedStorage.Modules.Notify, the one notification style.
	  Hostile    {Kind = "Hostile"}: the raid has turned on you (you hit one of them) - a warning.
	  Co-op      (2026-09-24) HelpBlocked (your own wave is not done) / HelperJoined {Name} / Helping {Name} /
	             Teamwork {With, Seconds} (the wave was won together: 2x cash + strength for Seconds) -> toasts.
	  Hit        {Kind = "Hit", Direction, Distance, Seconds}: a hostile zombie's blow landed. The
	             character's physics is ours, so the knockback runs here: a LinearVelocity on the root
	             flies the character Distance studs along Direction on a real parabola over Seconds
	             (along speed D/T, up speed g*T/2, updated per Heartbeat), then goes away.
	Everything is Heartbeat-stepped (no TweenService), so it also runs with Studio unfocused.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Notify = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Notify"))
local ZombieCatalog = require(ReplicatedStorage.Modules:WaitForChild("ZombieCatalog"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(ZombieCatalog.REMOTE)
local camera = workspace.CurrentCamera

--..Config..--
--.. the focus is the ground in front of the ZOMBIE NIGHT arch on the night wall (lobby entrance, facing +X):
--.. start wide and high enough to read the sign (the letters sit ~30 studs above the floor), push in to the door
local CAMERA_A = Vector3.new(40, 16, -12) -- start offset from the door focus (into the lobby, up, a little north)
local CAMERA_B = Vector3.new(21, 7, 9)    -- end offset
local LOOK_UP_FROM, LOOK_UP_TO = 12, 5    -- the look point rides down the wall from the sign to the doorway
local FOV_FROM, FOV_TO = 62, 54
local SHAKE = 0.35
local SHAKE_FROM, SHAKE_LEN = 1.2, 1.2    -- while the first rows step out (server DOOR_FIRST)
local FADE = 0.25
local WATCHDOG = 1.5

--..Fade overlay..--
local gui = Instance.new("ScreenGui")
gui.Name = "ZombieCutscene"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1500
gui.ResetOnSpawn = false
gui.Enabled = false
local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function animate(seconds, fn)
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		fn(a)
		if a >= 1 then return end
		RunService.Heartbeat:Wait()
	end
end

local function fade(toBlack)
	gui.Enabled = true
	local from = black.BackgroundTransparency
	local to = toBlack and 0 or 1
	animate(FADE, function(a) black.BackgroundTransparency = from + (to - from) * a end)
	if not toBlack then gui.Enabled = false end
end

--..Cutscene..--
local token = 0
local function restoreCamera()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then camera.CameraSubject = humanoid end
	camera.FieldOfView = 70
end

local function endCutscene(myToken)
	if myToken ~= token then return end
	token += 1
	task.spawn(function()
		fade(true)
		restoreCamera()
		fade(false)
	end)
end

local function runCutscene(focus, seconds)
	token += 1
	local myToken = token
	seconds = tonumber(seconds) or 6
	task.spawn(function()
		fade(true)
		if myToken ~= token then return end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(focus + CAMERA_A, focus + Vector3.new(0, LOOK_UP_FROM, 0))
		camera.FieldOfView = FOV_FROM
		fade(false)
		SoundController.PlayFX("Drama Sting", {Volume = 0.8})
		task.delay(0.15, function() if myToken == token then Notify.Warn("THE ZOMBIES ARE COMING!", 2.6) end end)
		local rng = Random.new()
		local t0 = os.clock()
		while myToken == token do
			local t = os.clock() - t0
			local a = math.clamp(t / seconds, 0, 1)
			local eased = a * a * (3 - 2 * a)
			local pos = focus + CAMERA_A:Lerp(CAMERA_B, eased)
			local look = focus + Vector3.new(0, LOOK_UP_FROM + (LOOK_UP_TO - LOOK_UP_FROM) * eased, 0)
			local shakeAmount = 0
			if t > SHAKE_FROM and t < SHAKE_FROM + SHAKE_LEN then shakeAmount = SHAKE * (1 - (t - SHAKE_FROM) / SHAKE_LEN) end
			local shake = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shakeAmount
			camera.CFrame = CFrame.lookAt(pos + shake, look + shake * 0.5)
			camera.FieldOfView = FOV_FROM + (FOV_TO - FOV_FROM) * eased
			if t >= seconds + WATCHDOG then
				endCutscene(myToken)
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

--..Knockback (a hostile zombie's blow)..--
local KNOCK_DISTANCE, KNOCK_TIME = 10, 0.35
local knock
local function knockback(direction, distance, seconds)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 then return end
	local flat = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or Vector3.zero
	if flat.Magnitude < 0.05 then flat = Vector3.new(-root.CFrame.LookVector.X, 0, -root.CFrame.LookVector.Z) end
	if flat.Magnitude < 0.05 then return end
	flat = flat.Unit
	distance = tonumber(distance) or KNOCK_DISTANCE
	seconds = math.max(0.15, tonumber(seconds) or KNOCK_TIME)
	if knock then
		knock:Destroy()
		knock = nil
	end
	local att = root:FindFirstChild("RootAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "RootAttachment"
		att.Parent = root
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "ZombieKnockback"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	knock = lv
	local g = workspace.Gravity
	local along = flat * (distance / seconds)
	local up = g * seconds * 0.5
	local t0 = os.clock()
	task.spawn(function()
		while knock == lv and lv.Parent do
			local t = os.clock() - t0
			if t >= seconds then break end
			lv.VectorVelocity = along + Vector3.new(0, up - g * t, 0)
			RunService.Heartbeat:Wait()
		end
		if knock == lv then
			knock = nil
			lv:Destroy()
			if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
		end
	end)
end

--..Messages..--
local HANDLERS = {
	Cutscene = function(p) runCutscene(p.Focus, p.Seconds) end,
	CutsceneEnd = function() endCutscene(token) end,
	RaidStart = function(p)
		if (p.Cucumbers or 0) == 0 then
			Notify.Warn(("Zombie raid! Threat level %d - no cucumbers to steal, smash them!"):format(p.Level or 1), 3.5)
		else
			Notify.Warn(("Zombie raid! Threat level %d - %d zombies want your cucumbers"):format(p.Level or 1, p.Count or 0), 3.5)
		end
		SoundController.PlayFX("Alarm Bell", {Volume = 0.7})
	end,
	Grabbed = function(p) Notify.Warn(("A %s grabbed your %s!"):format(p.Zombie or "zombie", p.Name or "cucumber"), 2) end,
	Grappled = function(p) Notify.Warn(("A %s hooked your %s!"):format(p.Zombie or "zombie", p.Name or "cucumber"), 2) end,
	Digging = function(p) Notify.Warn(("A %s is burrowing toward your cucumbers!"):format(p.Zombie or "zombie"), 2.5) end,
	Split = function(p) Notify.Warn(("The %s burst into %d %ss!"):format(p.Zombie or "zombie", p.Count or 3, p.Child or "spawnling"), 2.5) end,
	Stolen = function(p)
		Notify.Error(("The zombies stole your %s! (%d/%d)"):format(p.Name or "cucumber", p.Stolen or 0, p.Limit or ZombieCatalog.STEAL_LIMIT), 2.5)
	end,
	Saved = function(p) Notify.Success(("You saved your %s! It dropped where the %s fell."):format(p.Name or "cucumber", p.Zombie or "zombie"), 2.5) end,
	BuildBroken = function(p) Notify.Error(("The zombies broke your %s! It mends by morning."):format(p.Name or "build"), 2.5) end,
	ZombiesWin = function()
		Notify.Error("The zombies win.", 4)
		SoundController.PlayFX("Sad Trombone", {Volume = 0.9})
	end,
	Survived = function(p)
		if (p.Stolen or 0) > 0 then
			Notify.Success(("The raid is over! You lost %d cucumber%s."):format(p.Stolen, p.Stolen == 1 and "" or "s"), 3.5)
		else
			Notify.Success("You survived the night!", 3.5)
		end
		SoundController.PlayFX("Victory Sting", {Volume = 0.9})
	end,
	Dawn = function(p)
		local n = p.Stolen or 0
		if n > 0 then
			Notify.Info(("The night is over. You lost %d cucumber%s."):format(n, n == 1 and "" or "s"), 3.5)
		else
			Notify.Info("Dawn! The zombies burn away.", 3)
		end
	end,
	Hostile = function() end, -- 2026-09-23 (user): no "turned on you" toast; the hostility itself is unchanged
	Hit = function(p)
		knockback(p.Direction, p.Distance, p.Seconds)
		-- 2026-09-18 (user): a guardian's catch sends Silent = true - no "knocked you back!" toast
		-- while taking a cucumber; zombie hits still announce themselves
		if not p.Silent then Notify.Error(("A %s knocked you back!"):format(p.Zombie or "zombie"), 1.5) end
	end,
	--.. 2026-09-24 co-op nights
	HelpBlocked = function() Notify.Error("Finish your own wave before helping others!", 2.5) end,
	HelperJoined = function(p) Notify.Info(("%s is helping you fight!"):format(p.Name or "A player"), 2.5) end,
	Helping = function(p) Notify.Info(("You are helping %s! Win the wave together for a boost."):format(p.Name or "them"), 3) end,
	Teamwork = function(p)
		local minutes = math.max(1, math.floor((tonumber(p.Seconds) or 300) / 60 + 0.5))
		Notify.Success(("TEAMWORK with %s! 2x cash + 2x strength for %d min"):format(p.With or "your team", minutes), 4)
		SoundController.PlayFX("Victory Sting", {Volume = 0.9})
	end,
	Thief = function(p) Notify.Warn(("A %s is sneaking toward your base!"):format(p.Zombie or "thief"), 3) end,
	ThiefStole = function(p) Notify.Error(("A thief got away with your %s!"):format(p.Name or "cucumber"), 3) end,
}

Remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local handler = HANDLERS[payload.Kind]
	if handler then
		local ok, err = pcall(handler, payload)
		if not ok then warn("[ZombieRaidClient] " .. tostring(payload.Kind) .. ": " .. tostring(err)) end
	end
end)

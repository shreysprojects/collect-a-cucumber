--[[---------------------------------------DESCRIPTION------------------------------------------
	Launcher arm animation on OTHER players' characters.

	CLIENT_Snowball drives the local player's ChargeController. Joint Transform
	writes never replicate, so without this module everyone else would see the
	server-welded launcher (SERV_Launcher) held in a plain idle arm. Every client
	runs one controller per other player whose character holds the launcher
	(child LAUNCHER.InstanceName; profile = catalog Order of its EquippedName):
	  * ready pose (charge loop held at 0%) while the launcher is in hand,
	  * their hold-to-charge and release, from the player attribute LauncherPose that
	    SERV_Launcher sets when their client reports "hold" / "release" / "idle" (the charge
	    level is not sent: observers run the same bar ping-pong locally), so the launcher clip
	    fires, and the ball leaves the launcher, about when their real ball appears,
	  * fallback (no LauncherPose yet): a short wind-up to the ball's LaunchCharge, then the fire
	    motion, when that player's ball appears in workspace.ActiveSnowballs,
	  * no pose while their ball rides, a fade-out when the launcher goes.

	Hooked from ClientMain (StartLauncherObservers).

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local launcherCatalog = require(ReplicatedStorage.Assets.Modules.Shared.SnowballLaunchers)
local ChargeController = require(ReplicatedStorage.Assets.SnowballAnimations.ChargeController)

local BALL_SUFFIX = "_Snowball" -- SERV_Snowball names each ride ball <Player.Name>_Snowball
local WINDUP = 0.15 -- seconds of visible charge before an observed release

local api = {}

local observed = {} -- [Player] = ChargeController
local poseSeen = {} -- [Player] = last LauncherPose attribute handled
local holdStart = {} -- [Player] = os.clock() of their last "hold"
local warned = false

-- The owner's charge bar (CLIENT_Snowball): fills over FillTime, then ping-pongs over Time.
local function simulatedCharge(elapsed)
	local settings = mountainConfig.LAUNCH.Charge or {}
	local fillTime = math.max(settings.FillTime or 0.28, 0.05)
	local cycleTime = math.max(settings.Time or 0.8, 0.1)
	if elapsed <= fillTime then
		return elapsed / fillTime
	end
	return math.abs(((elapsed - fillTime) / cycleTime) % 2 - 1)
end

local function poseState(player)
	local value = player:GetAttribute("LauncherPose")
	if type(value) ~= "string" then
		return nil, nil
	end
	return string.match(value, "^(%a+)"), value
end

local function getVars(self)
	return self and self.Variables
end

local function launcherId(launcher)
	local name = launcher:GetAttribute("EquippedName")
	local info = if type(name) == "string" then launcherCatalog:GetByName(name) else nil
	return if info then info.Order else 1
end

local function isRiding(player)
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	return folder ~= nil and folder:FindFirstChild(player.Name .. BALL_SUFFIX) ~= nil
end

local function drop(player)
	local controller = observed[player]
	observed[player] = nil
	if controller then
		controller:Destroy()
	end
end

-- Fade out of a running pose before dropping it, so the arms do not snap back.
local function release(player)
	local controller = observed[player]
	if not controller then
		return
	end
	if controller.State == "charging" or controller.State == "firing" then
		controller:Cancel()
	elseif controller.State ~= "fading" then
		drop(player)
	end
end

local function create(character, id)
	local ready, reason = ChargeController.Ready(character)
	if not ready then
		if reason ~= "loading" and not warned then
			warned = true
			warn("[CLIENT]: Observer launcher animation unavailable:", reason)
		end
		return nil
	end
	local ok, result = pcall(ChargeController.new, character, id)
	if not ok then
		if not warned then
			warned = true
			warn("[CLIENT]: Observer launcher animation unavailable:", result)
		end
		return nil
	end
	return result
end

local function step()
	local localPlayer = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		if player == localPlayer then
			continue
		end

		-- A dead character keeps its launcher until it respawns: no pose on the corpse.
		local character = player.Character
		local humanoid = character and character.Parent and character:FindFirstChildOfClass("Humanoid")
		local launcher = humanoid
			and humanoid.Health > 0
			and character:FindFirstChild(mountainConfig.LAUNCHER.InstanceName)
		local controller = observed[player]
		if controller and (controller.Destroyed or controller.Character ~= character or not controller:IsLive()) then
			drop(player)
			controller = nil
		end

		if not launcher then
			release(player)
			continue
		end

		-- Another launcher was equipped: fade the old profile out, rebuild next frames.
		local id = launcherId(launcher)
		if controller and controller.Profile.id ~= id then
			release(player)
			continue
		end

		if not controller then
			controller = create(character, id)
			if not controller then
				continue
			end
			observed[player] = controller
			-- a pose relayed before this controller existed is history, not a new shot
			local _, raw = poseState(player)
			poseSeen[player] = raw
			holdStart[player] = nil
		end

		if controller.State == "idle" and not isRiding(player) then
			controller:BeginCharge()
		end

		-- their hold / release, as relayed by the server
		local state, raw = poseState(player)
		if raw and raw ~= poseSeen[player] then
			poseSeen[player] = raw
			if state == "hold" then
				if controller.State == "idle" and not isRiding(player) then
					controller:BeginCharge()
				end
				holdStart[player] = os.clock()
				controller:SetHolding(true)
			elseif state == "release" then
				holdStart[player] = nil
				if controller.State == "charging" then
					controller:Release()
				end
			elseif state == "idle" then
				holdStart[player] = nil
				if controller.State == "charging" and controller.Holding then
					controller:Cancel()
				end
			end
		end
		local started = holdStart[player]
		if started and controller.State == "charging" then
			controller:SetChargePercent(simulatedCharge(os.clock() - started) * 100)
		end
	end
end

local function onBall(ball)
	local name = ball.Name
	if #name <= #BALL_SUFFIX or string.sub(name, -#BALL_SUFFIX) ~= BALL_SUFFIX then
		return
	end
	local player = Players:FindFirstChild(string.sub(name, 1, -#BALL_SUFFIX - 1))
	if not (player and player:IsA("Player")) or player == Players.LocalPlayer then
		return
	end
	local controller = observed[player]
	if not controller or controller.Destroyed or controller.State ~= "charging" then
		return
	end
	if poseSeen[player] ~= nil and holdStart[player] == nil and not controller.Holding then
		-- the relayed release already played the shot (or is about to)
		return
	end

	local charge = ball:GetAttribute("LaunchCharge")
	charge = if type(charge) == "number" then math.clamp(charge, 0, 1) else 1
	holdStart[player] = nil -- this ball is the shot; the hold that led to it is over
	controller:SetChargePercent(charge * 100)
	task.delay(WINDUP, function()
		if observed[player] == controller then
			-- the ball that triggered this is the shot's own ball: hand over to it
			controller:Release(ball)
		end
	end)
end

function api:StartLauncherObservers()
	local vars = getVars(self)
	if vars then
		if vars.LauncherObserversStarted then
			return
		end
		vars.LauncherObserversStarted = true
	end

	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		drop(player)
		poseSeen[player] = nil
		holdStart[player] = nil
	end)

	-- The server creates the folder with the first ball already inside it.
	local function hookFolder(folder)
		for _, child in folder:GetChildren() do
			onBall(child)
		end
		folder.ChildAdded:Connect(onBall)
	end
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	if folder then
		hookFolder(folder)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "ActiveSnowballs" then
			hookFolder(child)
		end
	end)
end

return api

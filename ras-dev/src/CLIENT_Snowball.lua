--[[---------------------------------------DESCRIPTION------------------------------------------
	Launch pad camera, snowball chase camera, and ride UI. Launch is only
	available while standing on StartPlatform.LaunchPlatform. Entering the
	pad also asks the server to weld the equipped launcher to the hand.

	While riding: Left / Stop / Right on LaunchGui, plus A/D and the left stick.
	If the ball sits still or crawls for a moment, the ride ends the same as Stop.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local launcherCatalog = require(ReplicatedStorage.Assets.Modules.Shared.SnowballLaunchers)
local ChargeController = require(ReplicatedStorage.Assets.SnowballAnimations.ChargeController)

local api = {}

local function getVars(self)
	return self.Variables
end

local function getRoot(snowball)
	if snowball:IsA("BasePart") then
		return snowball
	end
	if snowball:IsA("Model") then
		return snowball.PrimaryPart or snowball:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local STEER_ACTION = "SnowballSteer"
local STEER_PRIORITY = 3000
local STICK_DEADZONE = 0.2

local function refreshSteer(vars)
	if not vars then
		return
	end
	local digital = 0
	if vars.SteerLeftKey or vars.SteerLeftButton then
		digital -= 1
	end
	if vars.SteerRightKey or vars.SteerRightButton then
		digital += 1
	end
	local stick = vars.SteerStick or 0
	if math.abs(stick) < STICK_DEADZONE then
		stick = 0
	end
	if digital ~= 0 then
		vars.Steer = math.clamp(digital, -1, 1)
	else
		vars.Steer = math.clamp(stick, -1, 1)
	end
end

local function sampleGamepadSteer(vars)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				vars.SteerStick = input.Position.X
				return
			end
		end
	end
end

local function unbindSteer(vars)
	if not vars then
		return
	end
	if vars.SteerBoundAction then
		ContextActionService:UnbindAction(STEER_ACTION)
		vars.SteerBoundAction = false
	end
	vars.SteerLeftKey = false
	vars.SteerRightKey = false
	vars.SteerStick = 0
	vars.SteerLeftButton = false
	vars.SteerRightButton = false
	vars.Steer = 0
end

local function bindSteer(vars)
	if not vars or vars.SteerBoundAction then
		return
	end
	vars.SteerBoundAction = true
	vars.SteerLeftKey = UserInputService:IsKeyDown(Enum.KeyCode.A)
	vars.SteerRightKey = UserInputService:IsKeyDown(Enum.KeyCode.D)
	sampleGamepadSteer(vars)
	refreshSteer(vars)
	ContextActionService:BindActionAtPriority(STEER_ACTION, function(_, inputState, input)
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then
			local down = inputState == Enum.UserInputState.Begin
			if input.KeyCode == Enum.KeyCode.A then
				vars.SteerLeftKey = down
			else
				vars.SteerRightKey = down
			end
			refreshSteer(vars)
			return Enum.ContextActionResult.Sink
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			if inputState == Enum.UserInputState.Change or inputState == Enum.UserInputState.Begin then
				vars.SteerStick = input.Position.X
			else
				vars.SteerStick = 0
			end
			refreshSteer(vars)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, STEER_PRIORITY, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Thumbstick1)
end

local function setRideButtons(vars, riding)
	if not vars then
		return
	end
	local onPad = vars.OnLaunchPad == true
	if vars.LaunchButton then
		vars.LaunchButton.Visible = onPad and not riding
	end
	if vars.LaunchSpeedBox then
		vars.LaunchSpeedBox.Visible = onPad and not riding
	end
	if vars.StopButton then
		vars.StopButton.Visible = riding
	end
	if vars.LeftButton then
		vars.LeftButton.Visible = riding
	end
	if vars.RightButton then
		vars.RightButton.Visible = riding
	end
	if riding then
		bindSteer(vars)
	else
		unbindSteer(vars)
	end
	local chargeBar = vars.ChargeBar
	if chargeBar and chargeBar.Hint then
		local panelOpen = vars.PlayerGui and vars.PlayerGui:GetAttribute("PanelOpen") ~= nil
		chargeBar.Hint.Visible = onPad and not riding and not vars.Charging and not panelOpen
	end
end

function api:SetupSteer()
	local vars = getVars(self)
	if not vars or vars.SteerInputBound then
		return
	end
	vars.SteerInputBound = true
	vars.Steer = 0

	local function bindButton(button, isLeft)
		if not (button and button:IsA("GuiButton")) then
			return
		end
		button.MouseButton1Down:Connect(function()
			if isLeft then
				vars.SteerLeftButton = true
			else
				vars.SteerRightButton = true
			end
			refreshSteer(vars)
		end)
		button.MouseButton1Up:Connect(function()
			if isLeft then
				vars.SteerLeftButton = false
			else
				vars.SteerRightButton = false
			end
			refreshSteer(vars)
		end)
	end

	bindButton(vars.LeftButton, true)
	bindButton(vars.RightButton, false)

	UserInputService.InputChanged:Connect(function(input)
		if not vars.SteerBoundAction or input.KeyCode ~= Enum.KeyCode.Thumbstick1 then
			return
		end
		vars.SteerStick = input.Position.X
		refreshSteer(vars)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not vars.SteerLeftButton and not vars.SteerRightButton then
			return
		end
		vars.SteerLeftButton = false
		vars.SteerRightButton = false
		refreshSteer(vars)
	end)
end

----------------------------------------------------------------------------------------------
-- Charge / fire arm animation (ReplicatedStorage.Assets.SnowballAnimations). Profile ids
-- match the catalog Order, 1-30. The controller writes R15 joint transforms on this client
-- only: it is cosmetic, the ball itself is still launched by the server on release.
----------------------------------------------------------------------------------------------

local animationWarned = false

local function equippedLauncherId()
	local name = Players.LocalPlayer:GetAttribute("EquippedLauncher")
	local info = if type(name) == "string" then launcherCatalog:GetByName(name) else nil
	return if info then info.Order else 1
end

local ANIMATION_FADE = 0.25 -- a little longer than the controller's own fade

local function destroyChargeAnimation(vars)
	local controller = vars and vars.ChargeAnimation
	if not controller then
		return
	end
	vars.ChargeAnimation = nil
	controller:Destroy()
end

-- Unequipping: fade out of the pose first, so the arms do not snap back to the
-- avatar animation part way through a charge.
local function fadeChargeAnimation(vars)
	local controller = vars and vars.ChargeAnimation
	if not controller then
		return
	end
	controller:Cancel()
	task.delay(ANIMATION_FADE, function()
		-- Stepping straight back onto the pad picks the same controller up again.
		if vars.ChargeAnimation == controller and controller.State ~= "charging" then
			destroyChargeAnimation(vars)
		end
	end)
end

-- One controller per character, rebuilt on respawn or when another launcher is
-- equipped. Controller.new throws on R6 rigs, missing joints and unknown ids.
local function chargeAnimation(vars)
	local character = Players.LocalPlayer.Character
	if not (character and character.Parent) then
		destroyChargeAnimation(vars)
		return nil
	end

	local launcherId = equippedLauncherId()
	local controller = vars.ChargeAnimation
	local stale = controller
		and (
			controller.Destroyed
			or not controller:IsLive()
			or controller.Character ~= character
			or (controller.Profile.id ~= launcherId and controller.State == "idle")
		)
	if stale then
		destroyChargeAnimation(vars)
		controller = nil
	end
	if controller then
		return controller
	end

	-- Spawn lands on the pad and GiveLauncher runs before the R15 joints
	-- exist (Motor6D or AnimationConstraint). Skip until they do.
	local ready, reason = ChargeController.Ready(character)
	if not ready then
		if reason ~= "loading" and not animationWarned then
			animationWarned = true
			warn("[CLIENT]: Launcher charge animation unavailable:", reason)
		end
		return nil
	end

	local ok, result = pcall(ChargeController.new, character, launcherId)
	if not ok then
		if not animationWarned then
			animationWarned = true
			warn("[CLIENT]: Launcher charge animation unavailable:", result)
		end
		return nil
	end

	vars.ChargeAnimation = result
	return result
end

-- Ready pose: on the pad with the launcher in hand and nothing else running, the
-- charge loop is held at 0% so the launcher is carried instead of hanging at the
-- side. Holding to launch then raises the same loop without restarting it.
local function holdChargeAnimation(vars)
	if not vars.OnLaunchPad or vars.Charging or vars.SnowballCamera then
		return
	end

	local character = Players.LocalPlayer.Character
	if not (character and character:FindFirstChild(mountainConfig.LAUNCHER.InstanceName)) then
		return
	end

	-- Another launcher was equipped: fade out of the old pose, then let the next
	-- frames rebuild the controller on the new profile.
	local controller = vars.ChargeAnimation
	if controller and not controller.Destroyed and controller.Profile.id ~= equippedLauncherId() then
		if controller.State == "charging" then
			fadeChargeAnimation(vars)
		elseif controller.State == "idle" then
			destroyChargeAnimation(vars)
		end
		return
	end

	controller = chargeAnimation(vars)
	if controller and controller.State == "idle" then
		controller:BeginCharge()
	end
end

----------------------------------------------------------------------------------------------
-- Hold-to-launch. Standing on the pad, hold click / touch: the bar (the LoadingProgressGui
-- from RAS - Maps, kept in ReplicatedStorage.Assets.UserInterfaces.ChargeBar) fills to
-- 100% quickly, then ping-pongs 100% ↔ 0% until release. Release fires at the live charge.
----------------------------------------------------------------------------------------------

local function fallbackChargeBar()
	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "ProgressBar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.2845, 0, 0.518, 0)
	bar.Size = UDim2.fromOffset(58, 324)
	bar.BackgroundColor3 = Color3.fromRGB(40, 43, 43)
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(4, 4)
	track.Size = UDim2.new(1, -8, 1, -8)
	track.BackgroundColor3 = Color3.fromRGB(195, 222, 207)
	track.Parent = bar
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 8)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(141, 232, 0)
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill
	local label = Instance.new("TextLabel")
	label.Name = "Percent"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(80, 49)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(24, 24, 24)
	label.TextStrokeTransparency = 0
	label.ZIndex = 10
	label.Parent = bar
	return gui
end

local function buildChargeBar(vars)
	local playerGui = vars.PlayerGui or Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("ChargeBar")
	if old then
		old:Destroy()
	end

	local interfaces = ReplicatedStorage.Assets:FindFirstChild("UserInterfaces")
	local template = interfaces and interfaces:FindFirstChild("ChargeBar")
	local gui = if template then template:Clone() else fallbackChargeBar()
	for _, desc in gui:GetDescendants() do
		if desc:IsA("LuaSourceContainer") then
			desc:Destroy()
		end
	end
	gui.Name = "ChargeBar"
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1002

	local bar = gui:FindFirstChild("ProgressBar")
	local track = bar and bar:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	local label = bar and bar:FindFirstChild("Percent")
	if fill then
		fill.Size = UDim2.fromScale(1, 0)
	end
	if label then
		label.Text = "0%"
	end

	-- "HOLD TO LAUNCH" prompt while standing on the pad (separate gui so it can show
	-- while the bar itself is hidden).
	local hintGui = playerGui:FindFirstChild("ChargeHint")
	if hintGui then
		hintGui:Destroy()
	end
	hintGui = Instance.new("ScreenGui")
	hintGui.Name = "ChargeHint"
	hintGui.ResetOnSpawn = false
	hintGui.IgnoreGuiInset = true
	hintGui.DisplayOrder = 1001
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 0.86, 0) -- above the HUD level bar (y 0.88-0.98)
	hint.Size = UDim2.fromOffset(420, 54)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.FredokaOne
	hint.TextSize = 34
	hint.Text = (mountainConfig.LAUNCH.Charge and mountainConfig.LAUNCH.Charge.HintText) or "HOLD TO LAUNCH"
	hint.TextColor3 = Color3.fromRGB(236, 248, 255)
	hint.Visible = false
	hint.Parent = hintGui
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 3
	hintStroke.Color = Color3.fromRGB(28, 48, 72)
	hintStroke.Parent = hint
	hintGui.Parent = playerGui

	gui.Parent = playerGui
	vars.ChargeBar = {
		Gui = gui,
		Bar = bar,
		Fill = fill,
		Label = label,
		Scale = gui:FindFirstChild("ResponsiveScale"),
		Hint = hint,
	}
	return vars.ChargeBar
end

local function renderCharge(chargeBar, charge)
	if chargeBar.Fill then
		chargeBar.Fill.Size = UDim2.fromScale(1, charge)
	end
	if chargeBar.Label then
		chargeBar.Label.Text = string.format("%d%%", math.floor(charge * 100 + 0.5))
	end
end

local function stopChargeLoop(vars)
	if vars.ChargeLoop then
		vars.ChargeLoop:Disconnect()
		vars.ChargeLoop = nil
	end
end

local function endCharge(self, fire)
	local vars = getVars(self)
	if not vars or not vars.Charging then
		return
	end
	vars.Charging = false
	stopChargeLoop(vars)
	local chargeBar = vars.ChargeBar
	local charge = vars.Charge or 0
	local settings = mountainConfig.LAUNCH.Charge or {}
	local fired = false
	if fire and charge >= (settings.MinCharge or 0.03) and vars.OnLaunchPad and not vars.SnowballCamera then
		ReplicatedStorage.ReEvent:FireServer("Launch", charge)
		fired = true
	end
	local animation = vars.ChargeAnimation
	if animation and not animation.Destroyed then
		if fired then
			animation:Release()
		else
			animation:Cancel()
		end
	end
	if chargeBar then
		if fired then
			-- leave the full bar on screen for a beat, then hide
			task.delay(0.3, function()
				if not vars.Charging and chargeBar.Gui then
					chargeBar.Gui.Enabled = false
				end
			end)
		elseif chargeBar.Gui then
			chargeBar.Gui.Enabled = false
		end
	end
	setRideButtons(vars, vars.SnowballCamera ~= nil)
end

local function beginCharge(self)
	local vars = getVars(self)
	if not vars or vars.Charging or vars.SnowballCamera or not vars.OnLaunchPad then
		return
	end
	-- A HUD panel (Shop / Mountains / ...) is open: clicks belong to it, not the launch.
	if vars.PlayerGui and vars.PlayerGui:GetAttribute("PanelOpen") then
		return
	end
	local chargeBar = vars.ChargeBar or buildChargeBar(vars)
	local settings = mountainConfig.LAUNCH.Charge or {}
	local fillTime = math.max(settings.FillTime or 0.28, 0.05)
	local cycleTime = math.max(settings.Time or 0.8, 0.1)

	vars.Charging = true
	vars.Charge = 0
	vars.ChargeStart = os.clock()
	if chargeBar.Scale then
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(754, 564)
		chargeBar.Scale.Scale = math.clamp(viewport.Y / 564, 0.72, 1.15)
	end
	renderCharge(chargeBar, 0)
	chargeBar.Gui.Enabled = true
	setRideButtons(vars, false)

	local animation = chargeAnimation(vars)
	if animation then
		animation:BeginCharge()
	end

	stopChargeLoop(vars)
	vars.ChargeLoop = vars.RNS.Heartbeat:Connect(function()
		if not vars.Charging then
			return
		end
		local elapsed = os.clock() - (vars.ChargeStart or os.clock())
		local charge
		if elapsed <= fillTime then
			charge = elapsed / fillTime
		else
			-- After the first fill: 100% → 0% → 100%… until release.
			local t = elapsed - fillTime
			charge = math.abs((t / cycleTime) % 2 - 1)
		end
		vars.Charge = math.clamp(charge, 0, 1)
		renderCharge(chargeBar, vars.Charge)
		if vars.ChargeAnimation then
			vars.ChargeAnimation:SetChargePercent(vars.Charge * 100)
		end
		if not vars.OnLaunchPad or vars.SnowballCamera then
			endCharge(self, false)
		end
	end)
end

local function isPressInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function api:BeginCharge()
	beginCharge(self)
end

function api:EndCharge(fire)
	endCharge(self, fire ~= false)
end

function api:SetupChargeLaunch()
	local vars = getVars(self)
	if not vars or vars.ChargeInputBound then
		return
	end
	vars.ChargeInputBound = true
	buildChargeBar(vars)
	setRideButtons(vars, vars.SnowballCamera ~= nil)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isPressInput(input) then
			return
		end
		beginCharge(self)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not isPressInput(input) then
			return
		end
		endCharge(self, true)
	end)

	-- Dev hook: PlayerGui attribute DevChargeHold true/false mirrors press/release.
	local playerGui = vars.PlayerGui
	if playerGui then
		playerGui:GetAttributeChangedSignal("DevChargeHold"):Connect(function()
			if playerGui:GetAttribute("DevChargeHold") then
				beginCharge(self)
			else
				endCharge(self, true)
			end
		end)
		-- HUD panels (PanelOpen attribute) hide the launch hint while they are open.
		playerGui:GetAttributeChangedSignal("PanelOpen"):Connect(function()
			setRideButtons(vars, vars.SnowballCamera ~= nil)
		end)
	end
end

local function restorePlayerCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	elseif character then
		camera.CameraSubject = character
	end
end

local function findLaunchCollision()
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	if not mountain then
		return nil
	end

	local pad = mountainConfig.LAUNCH_PAD
	local startName = mountainConfig.Attachment.StartPlatform
	local root = mountain
	for _, child in mountain:GetChildren() do
		if child:IsA("Model") and (
			child:GetAttribute("AttachmentType") == startName
			or string.sub(child.Name, 1, #startName) == startName
		) then
			root = child
			break
		end
	end

	local model = root:FindFirstChild(pad.Model, true)
	if not model then
		return nil
	end

	local collision = model:FindFirstChild(pad.Collision, true)
	if collision and not collision:IsA("BasePart") then
		collision = collision:FindFirstChildWhichIsA("BasePart", true)
	end
	if not collision then
		collision = model:FindFirstChildWhichIsA("BasePart", true)
	end
	return collision, root
end

local function getRampLook(startPiece, collision)
	if startPiece then
		for _, name in { mountainConfig.SOCKETS.Exit, mountainConfig.SOCKETS.LaunchPoint } do
			for _, desc in startPiece:GetDescendants() do
				if desc:IsA("Attachment") and desc.Name == name then
					local look = Vector3.new(desc.WorldCFrame.LookVector.X, 0, desc.WorldCFrame.LookVector.Z)
					if look.Magnitude > 0.05 then
						return look.Unit
					end
				end
			end
		end
	end

	if collision then
		local look = Vector3.new(collision.CFrame.LookVector.X, 0, collision.CFrame.LookVector.Z)
		if look.Magnitude > 0.05 then
			return look.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

local function setCharacterFacing(character, look)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp then
		return
	end
	if humanoid then
		humanoid.AutoRotate = false
	end
	local position = hrp.Position
	hrp.CFrame = CFrame.lookAt(position, position + look)
end

local function restoreCharacterRotate(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function unbindPadCamera(vars)
	if vars and vars.PadCamera then
		vars.PadCamera:Disconnect()
		vars.PadCamera = nil
	end
	restoreCharacterRotate(Players.LocalPlayer.Character)
end

function api:UnbindPadCamera()
	unbindPadCamera(getVars(self))
end

function api:BindPadCamera()
	local vars = getVars(self)
	if not vars or vars.SnowballCamera then
		return
	end

	unbindPadCamera(vars)

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local launch = mountainConfig.LAUNCH
	local camPos = nil
	local collision, startPiece = findLaunchCollision()
	if collision then
		setCharacterFacing(Players.LocalPlayer.Character, getRampLook(startPiece, collision))
	end

	vars.PadCamera = vars.RNS.RenderStepped:Connect(function(dt)
		if vars.SnowballCamera then
			return
		end

		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local collision, startPiece = findLaunchCollision()
		if not hrp or not collision then
			return
		end

		local forward = getRampLook(startPiece, collision)
		local right = Vector3.new(-forward.Z, 0, forward.X)
		if right.Magnitude < 0.05 then
			right = Vector3.new(1, 0, 0)
		else
			right = right.Unit
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.AutoRotate then
			setCharacterFacing(character, forward)
		end

		local lateral = (hrp.Position - collision.Position):Dot(right)
		local desired = collision.Position - forward * launch.PadCameraDistance + right * lateral + Vector3.yAxis * launch.PadCameraHeight
		if camPos then
			camPos = camPos:Lerp(desired, 1 - math.exp(-10 * dt))
		else
			camPos = desired
		end

		local lookAt = hrp.Position + Vector3.yAxis * 2 + forward * launch.PadLookAhead
		camera.CFrame = CFrame.lookAt(camPos, lookAt, Vector3.yAxis)
	end)
end

function api:WatchLaunchPad()
	local vars = getVars(self)
	if not vars or vars.LaunchPadWatch then
		return
	end

	if not vars.LaunchPadCharacter then
		vars.LaunchPadCharacter = Players.LocalPlayer.CharacterAdded:Connect(function()
			vars.OnLaunchPad = nil
			unbindPadCamera(vars)
			destroyChargeAnimation(vars)
		end)
	end

	setRideButtons(vars, vars.SnowballCamera ~= nil)

	vars.LaunchPadWatch = vars.RNS.Heartbeat:Connect(function()
		holdChargeAnimation(vars)

		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local collision = findLaunchCollision()
		local onPad = hrp and collision and mountainConfig.IsOnLaunchPad(hrp.Position, collision) or false
		local riding = vars.SnowballCamera ~= nil

		if onPad == vars.OnLaunchPad then
			return
		end

		vars.OnLaunchPad = onPad
		setRideButtons(vars, riding)

		if riding then
			return
		end

		if onPad then
			api.BindPadCamera(self)
			ReplicatedStorage.ReEvent:FireServer("EquipLauncher")
		else
			unbindPadCamera(vars)
			restorePlayerCamera()
			fadeChargeAnimation(vars)
			ReplicatedStorage.ReEvent:FireServer("UnequipLauncher")
		end
	end)
end

local function stopSnowballFollow(vars)
	if not vars then
		return
	end
	if vars.SnowballCamera then
		vars.SnowballCamera:Disconnect()
		vars.SnowballCamera = nil
	end
	if vars.SnowballAncestry then
		vars.SnowballAncestry:Disconnect()
		vars.SnowballAncestry = nil
	end
end

function api:UnbindSnowballCamera()
	if self.GUIFramework then
		self.GUIFramework:InvokeUI("HUD", "EndRunReadout")
	end
	local vars = getVars(self)
	if self.StopAirPhysics then
		self:StopAirPhysics()
	end
	stopSnowballFollow(vars)
	setRideButtons(vars, false)
	if vars and vars.OnLaunchPad then
		api.BindPadCamera(self)
	else
		restorePlayerCamera()
		task.defer(restorePlayerCamera)
	end
end

function api:StopRide()
	api.UnbindSnowballCamera(self)
	ReplicatedStorage.ReEvent:FireServer("StopSnowball")
end

function api:StandAtFinish(spawnCF)
	if typeof(spawnCF) ~= "CFrame" then
		return
	end

	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end

	local height = humanoid.HipHeight + (hrp.Size.Y / 2) + (mountainConfig.SPAWN.ExtraHeight or 3)
	character:PivotTo(spawnCF + Vector3.yAxis * height)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Park the ball in front of the finish and keep the chase camera on it.
function api:HoldAtFinish(standCF)
	if typeof(standCF) ~= "CFrame" then
		return
	end

	local folder = workspace:FindFirstChild("ActiveSnowballs")
	local snowball = folder and folder:FindFirstChild(Players.LocalPlayer.Name .. "_Snowball")
	local root = snowball and getRoot(snowball)
	if not snowball or not root then
		return
	end

	local radius = math.max(root.Size.X, root.Size.Y, root.Size.Z) / 2
	local parked = standCF + Vector3.yAxis * (radius + 1)
	snowball:SetAttribute("Finishing", true)
	snowball:SetAttribute("FinishCFrame", parked)
	snowball:SetAttribute("FinishLook", standCF.LookVector)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if snowball:IsA("Model") then
		snowball:PivotTo(parked)
	else
		root.CFrame = parked
	end
end

local function horizontalUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.05 then
		return fallback
	end
	return flat.Unit
end

local function horizontalSpeed(vector)
	return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

local function liftAboveGround(desired, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(desired + Vector3.yAxis * 60, Vector3.new(0, -120, 0), params)
	if not hit then
		return desired
	end

	local minY = hit.Position.Y + (mountainConfig.LAUNCH.CameraClearance or 4)
	if desired.Y < minY then
		return Vector3.new(desired.X, minY, desired.Z)
	end
	return desired
end

local function keepMass(root, baseDensity, scale)
	if not baseDensity then
		return
	end
	local density = baseDensity / math.max(scale ^ 3, 0.05)
	local current = root.CurrentPhysicalProperties
	local launch = mountainConfig.LAUNCH
	root.CustomPhysicalProperties = PhysicalProperties.new(
		density,
		launch.Friction or current.Friction,
		current.Elasticity,
		launch.FrictionWeight or current.FrictionWeight,
		current.ElasticityWeight
	)
end

-- Grow in place. Do not rewrite CFrame; restore velocity last so mass/scale
-- changes cannot eat the roll.
local function applyClientGrow(snowball, root, dt)
	local launch = mountainConfig.LAUNCH
	local target = snowball:GetAttribute("TargetSnowScale") or 1
	local current = snowball:GetAttribute("SnowScale") or 1
	local nextScale = current + (target - current) * (1 - math.exp(-launch.GrowLerp * dt))
	if math.abs(nextScale - current) < 0.002 then
		nextScale = target
	end
	if math.abs(nextScale - current) < 0.001 then
		return current
	end

	local linVel = root.AssemblyLinearVelocity
	local angVel = root.AssemblyAngularVelocity

	if snowball:IsA("Model") then
		snowball:ScaleTo((snowball:GetAttribute("BaseScale") or 1) * nextScale)
	else
		local baseSize = snowball:GetAttribute("BaseSize")
		if typeof(baseSize) == "Vector3" then
			snowball.Size = baseSize * nextScale
		end
	end

	keepMass(root, snowball:GetAttribute("BaseDensity"), nextScale)
	root.AssemblyLinearVelocity = linVel
	root.AssemblyAngularVelocity = angVel
	snowball:SetAttribute("SnowScale", nextScale)
	return nextScale
end

function api:BindSnowballCamera(snowball)
	local vars = getVars(self)
	if vars and vars.Charging then
		endCharge(self, false)
	end
	unbindPadCamera(vars)
	stopSnowballFollow(vars)
	if not snowball then
		if vars and vars.OnLaunchPad then
			api.BindPadCamera(self)
		end
		return
	end
	-- Snapshot coins before the root wait so snow collected while the ball
	-- streams in still counts toward this run.
	if self.GUIFramework then
		self.GUIFramework:InvokeUI("HUD", "BeginRunReadout")
	end
	local root = getRoot(snowball)
	if not root then
		local timeout = os.clock() + 3
		repeat
			task.wait()
			root = getRoot(snowball)
		until root or os.clock() > timeout or not snowball.Parent
	end
	if not root then
		if self.GUIFramework then
			self.GUIFramework:InvokeUI("HUD", "EndRunReadout")
		end
		if vars and vars.OnLaunchPad then
			api.BindPadCamera(self)
		end
		return
	end

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	setRideButtons(vars, true)

	-- Flight physics, tricks, smashing and effects live in CLIENT_SnowballFX.
	if self.StartAirPhysics then
		self:StartAirPhysics(snowball, root)
	end

	local launch = mountainConfig.LAUNCH
	local stopSpeed = launch.StopSpeed or 8
	local stopHold = launch.StopHold or 0.75
	local stopGrace = launch.StopGrace or 1.25
	-- Stay behind this heading for the whole ride. Do not yaw with wobble or reverse.
	local behind = horizontalUnit(root.AssemblyLinearVelocity, Vector3.new(0, 0, -1))
	local camPos = nil
	local followStarted = os.clock()
	local lastFast = os.clock()
	local missingFor = 0
	local lastStream = 0
	local lastPos = root.Position
	local smoothSpeed = horizontalSpeed(root.AssemblyLinearVelocity)
	local holdSnapped = false

	vars.SnowballCamera = vars.RNS.RenderStepped:Connect(function(dt)
		if not root.Parent or not snowball.Parent then
			-- Ball was removed for the place teleport. Stay on the last ball frame
			-- instead of cutting to the character.
			if holdSnapped then
				return
			end
			missingFor += dt
			if missingFor >= 1 then
				api.UnbindSnowballCamera(self)
			end
			return
		end
		missingFor = 0

		local hold = snowball:GetAttribute("FinishCFrame")
		if typeof(hold) == "CFrame" then
			root.Anchored = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if snowball:IsA("Model") then
				snowball:PivotTo(hold)
			else
				root.CFrame = hold
			end
			local look = snowball:GetAttribute("FinishLook")
			if typeof(look) == "Vector3" then
				behind = horizontalUnit(look, behind)
			end
			if not holdSnapped then
				holdSnapped = true
				camPos = nil
			end
		end

		local velocity = root.AssemblyLinearVelocity
		local scale = applyClientGrow(snowball, root, dt)
		if typeof(hold) == "CFrame" then
			if snowball:IsA("Model") then
				snowball:PivotTo(hold)
			else
				root.CFrame = hold
			end
			root.AssemblyLinearVelocity = Vector3.zero
		end
		local position = root.Position
		local moved = 0
		if dt > 0 then
			moved = horizontalSpeed(position - lastPos) / dt
		end
		lastPos = position
		-- Horizontal travel (or reported velocity). Physics jitter on Y should not keep the ride alive.
		local speed = math.max(horizontalSpeed(velocity), moved)
		smoothSpeed += (speed - smoothSpeed) * (1 - math.exp(-10 * math.max(dt, 0)))

		if os.clock() - lastStream >= 0.45 then
			lastStream = os.clock()
			task.spawn(function()
				pcall(function()
					Players.LocalPlayer:RequestStreamAroundAsync(position + velocity * 0.8)
				end)
			end)
		end
		local distance = launch.CameraDistance + math.max(0, scale - 1) * launch.CameraDistance * 0.5
		local height = launch.CameraHeight + math.max(0, scale - 1) * launch.CameraHeight * 0.4
		local desired = position - behind * distance + Vector3.yAxis * height
		if camPos then
			camPos = camPos:Lerp(desired, 1 - math.exp(-10 * dt))
		else
			camPos = desired
		end
		local ignore = { snowball }
		local decor = workspace:FindFirstChild(mountainConfig.PROPS.WorkspaceFolder)
		if decor then
			table.insert(ignore, decor)
		end
		camPos = liftAboveGround(camPos, ignore)
		camera.CFrame = CFrame.lookAt(camPos, position, Vector3.yAxis)
		if self.GetCameraKick then
			camera.CFrame = camera.CFrame * self:GetCameraKick(dt)
		end

		-- The server is moving the rider onto the finish platform.
		if snowball:GetAttribute("Finishing") then
			return
		end

		if smoothSpeed > stopSpeed then
			lastFast = os.clock()
		end

		if os.clock() - followStarted < stopGrace then
			return
		end

		-- Same as pressing Stop: idle or crawling for StopHold ends the ride.
		if os.clock() - lastFast >= stopHold then
			restorePlayerCamera()
			api.StopRide(self)
		end
	end)

	vars.SnowballAncestry = snowball.AncestryChanged:Connect(function(_, parent)
		if parent then
			missingFor = 0
		end
	end)
end

return api


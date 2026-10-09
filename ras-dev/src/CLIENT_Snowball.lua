--[[---------------------------------------DESCRIPTION------------------------------------------
	Launch pad camera, snowball chase camera, and ride UI. Launch is only
	available while standing on StartPlatform.LaunchPlatform.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()

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
	local chargeBar = vars.ChargeBar
	if chargeBar and chargeBar.Hint then
		chargeBar.Hint.Visible = onPad and not riding and not vars.Charging
	end
end

----------------------------------------------------------------------------------------------
-- Hold-to-launch. Standing on the pad, hold click / touch: the bar (the LoadingProgressGui
-- from RAS - Maps, kept in ReplicatedStorage.Assets.UserInterfaces.ChargeBar) fills to
-- 100%, release fires the ball with a speed proportional to the charge.
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
	hint.Position = UDim2.new(0.5, 0, 1, -48)
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
	local chargeBar = vars.ChargeBar or buildChargeBar(vars)
	local settings = mountainConfig.LAUNCH.Charge or {}
	local chargeTime = math.max(settings.Time or 1.5, 0.1)

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

	stopChargeLoop(vars)
	vars.ChargeLoop = vars.RNS.Heartbeat:Connect(function(dt)
		if not vars.Charging then
			return
		end
		vars.Charge = math.min(1, (vars.Charge or 0) + dt / chargeTime)
		renderCharge(chargeBar, vars.Charge)
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

	setRideButtons(vars, vars.SnowballCamera ~= nil)

	vars.LaunchPadWatch = vars.RNS.Heartbeat:Connect(function()
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
		else
			unbindPadCamera(vars)
			restorePlayerCamera()
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

local function horizontalUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.05 then
		return fallback
	end
	return flat.Unit
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
	root.CustomPhysicalProperties = PhysicalProperties.new(
		density,
		current.Friction,
		current.Elasticity,
		current.FrictionWeight,
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
	local root = getRoot(snowball)
	if not root then
		local timeout = os.clock() + 3
		repeat
			task.wait()
			root = getRoot(snowball)
		until root or os.clock() > timeout or not snowball.Parent
	end
	if not root then
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
	-- Stay behind this heading for the whole ride. Do not yaw with wobble or reverse.
	local behind = horizontalUnit(root.AssemblyLinearVelocity, Vector3.new(0, 0, -1))
	local camPos = nil
	local followStarted = os.clock()
	local lastFast = os.clock()
	local missingFor = 0
	local lastStream = 0
	local lastPos = root.Position
	local movingSpeed = math.max((launch.StopSpeed or 0.45) * 8, 4)

	vars.SnowballCamera = vars.RNS.RenderStepped:Connect(function(dt)
		if not root.Parent or not snowball.Parent then
			missingFor += dt
			if missingFor >= 1 then
				api.UnbindSnowballCamera(self)
			end
			return
		end
		missingFor = 0

		local velocity = root.AssemblyLinearVelocity
		local scale = applyClientGrow(snowball, root, dt)
		local position = root.Position
		local moved = 0
		if dt > 0 then
			moved = (position - lastPos).Magnitude / dt
		end
		lastPos = position
		-- Trust travel distance more than AssemblyLinearVelocity; streaming can report 0 while rolling.
		local speed = math.max(velocity.Magnitude, moved)
		local spin = root.AssemblyAngularVelocity.Magnitude

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

		if speed > movingSpeed or spin > (launch.StopSpin or 0.6) * 4 then
			lastFast = os.clock()
		end

		if os.clock() - followStarted < launch.StopGrace then
			return
		end

		-- One hitch or stream stall can report 0 speed while the ball is still flying.
		-- Only return to the player after it has really been slow for StopHold.
		if os.clock() - lastFast < launch.StopHold then
			return
		end
		if speed <= launch.StopSpeed and spin <= (launch.StopSpin or 0.6) then
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


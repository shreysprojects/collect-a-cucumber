local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("MinigameHudRemotes")
local fire = remotes:WaitForChild("DesertFire")
local shot = remotes:WaitForChild("DesertShot")
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "DesertRatProgress", false, 23 -- 2026-09-22: just over MinigameHUD (22), under the menus (was 9001)
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local function label(name, position, size, maxSize)
	local l = Instance.new("TextLabel")
	l.Name, l.Position, l.Size = name, position, size
	l.AnchorPoint = Vector2.new(.5, 0)
	l.BackgroundTransparency, l.Font, l.TextScaled = 1, Enum.Font.FredokaOne, true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Parent = 3, l
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize, constraint.Parent = maxSize, l
	return l
end
local counter = label("Rats", UDim2.fromScale(.5, .225), UDim2.fromScale(.55, .065), 36)
counter.TextColor3 = Color3.fromRGB(255, 225, 70)
-- 2026-09-22: the rat counter sits under the minigame HUD's timer + map name stack, which now starts
-- under the main HUD's counters (PortalHudClient publishes its bottom edge as MinigameHUD.StackBottom)
task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("MinigameHUD", 30)
	if not hud then return end
	local function place()
		local bottom = hud:GetAttribute("StackBottom")
		if typeof(bottom) == "number" then counter.Position = UDim2.new(.5, 0, 0, bottom + 4) end
	end
	hud:GetAttributeChangedSignal("StackBottom"):Connect(place)
	place()
end)
local ammo = label("Ammo", UDim2.fromScale(.83, .78), UDim2.fromScale(.3, .075), 24)
local crosshair = label("Crosshair", UDim2.fromScale(.5, .5), UDim2.fromOffset(26, 26), 26)
crosshair.AnchorPoint = Vector2.new(.5, .5)
crosshair.Text = "+"
local equipped, toolConnection, previousIcon, isActive = nil, nil, nil, false
local requestAfter = 0
local function shoot(center)
	if not isActive or not equipped or equipped.Parent ~= player.Character or player:GetAttribute("PortalTransitioning") then return end
	if os.clock() < requestAfter then return end
	requestAfter = os.clock() + .15
	local aim = mouse.Hit.Position
	if center then
		local camera = workspace.CurrentCamera
		local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {player.Character}
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		aim = hit and hit.Position or ray.Origin + ray.Direction * 500
	end
	fire:FireServer(aim)
end
local function bindTool(tool)
	if not tool:IsA("Tool") or not tool:GetAttribute("DesertHuntWeapon") or equipped == tool then return end
	if toolConnection then toolConnection:Disconnect() end
	equipped = tool
	toolConnection = tool.Activated:Connect(function() shoot(UserInputService.GamepadEnabled and not UserInputService.MouseEnabled) end)
end
local function bindCharacter(character)
	equipped = nil
	if toolConnection then toolConnection:Disconnect() toolConnection = nil end
	character.ChildAdded:Connect(bindTool)
	for _, child in ipairs(character:GetChildren()) do bindTool(child) end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end
local function update()
	local active = player:GetAttribute("InPortalMinigame") == true and player:GetAttribute("MinigameKey") == "DesertHunt"
	gui.Enabled = active
	counter.Text = string.format("Rats: %d / %d", player:GetAttribute("DesertRatsKilled") or 0, player:GetAttribute("DesertRatsTotal") or 10)
	if active == isActive then return end
	isActive = active
	if active then
		previousIcon = mouse.Icon
		mouse.Icon = "rbxassetid://316279304"
		ContextActionService:BindAction("DesertShoot", function(_, state)
			if state == Enum.UserInputState.Begin then shoot(true) end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.ButtonR2)
		ContextActionService:SetTitle("DesertShoot", "Shoot")
		ContextActionService:SetPosition("DesertShoot", UDim2.fromScale(.8, .55))
	else
		ContextActionService:UnbindAction("DesertShoot")
		if previousIcon then mouse.Icon = previousIcon previousIcon = nil end
	end
end
for _, attribute in ipairs({"InPortalMinigame", "MinigameKey", "DesertRatsKilled", "DesertRatsTotal"}) do player:GetAttributeChangedSignal(attribute):Connect(update) end
local function playSound(template)
	if not template or player:GetAttribute("SFXEnabled") == false then return end
	local s = template:Clone()
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end
shot.OnClientEvent:Connect(function(origin, endpoint, killed)
	if not isActive then return end
	local beam = Instance.new("Part")
	beam.Name, beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch = "DesertBullet", true, false, false, false
	beam.Material, beam.Color = Enum.Material.Neon, Color3.fromRGB(255, 226, 80)
	beam.Size = Vector3.new(.1, .1, (endpoint - origin).Magnitude)
	beam.CFrame = CFrame.lookAt((origin + endpoint) / 2, endpoint)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(.18), {Transparency = 1}):Play()
	Debris:AddItem(beam, .2)
	local gun = equipped
	local handle = gun and gun:FindFirstChild("Handle")
	if handle then
		playSound(handle:FindFirstChild("FireSound"))
		task.delay(1, function() if isActive and equipped == gun and handle.Parent then playSound(handle:FindFirstChild("ReloadSound")) end end)
	end
	if killed and player:GetAttribute("SFXEnabled") ~= false then
		local sound = Instance.new("Sound")
		sound.SoundId, sound.Volume, sound.Parent = "rbxassetid://7227567562", .6, SoundService
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end)
RunService.RenderStepped:Connect(function()
	if not isActive then return end
	local left = math.max(0, (player:GetAttribute("DesertReloadUntil") or 0) - workspace:GetServerTimeNow())
	ammo.Text = left > 0 and string.format("Reloading %.1fs", left) or "Revolver  1 / 1"
	crosshair.Visible = UserInputService.TouchEnabled or (UserInputService.GamepadEnabled and not UserInputService.MouseEnabled)
end)
update()
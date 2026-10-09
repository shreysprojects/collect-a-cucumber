-- Original black-hole iris, easing, blur, desaturation, and audio from Zombie Cucumber Game.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("MinigameHudRemotes")
local ready = remotes:WaitForChild("TransitionReady")
local transition = remotes:WaitForChild("Transition")
local gui = Instance.new("ScreenGui")
gui.Name = "PortalTransition"
gui.DisplayOrder = 10000
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = playerGui
local aperture = Instance.new("Frame")
aperture.Name = "HoleTransition"
aperture.AnchorPoint = Vector2.new(.5, .5)
aperture.Position = UDim2.fromScale(.5, .5)
aperture.Size = UDim2.fromScale(3.2, 3.2)
aperture.BackgroundTransparency = 1
aperture.Parent = gui
local hole = Instance.new("ImageLabel")
hole.Name = "Hole"
hole.AnchorPoint = Vector2.new(.5, .5)
hole.Position = UDim2.fromScale(.5, .5)
hole.Size = UDim2.fromScale(1, 1)
hole.BackgroundTransparency = 1
hole.Image = "rbxassetid://1054813334"
hole.Parent = aperture
local function blocker(name, position, size, anchor)
	local part = Instance.new("Frame")
	part.Name, part.Position, part.Size, part.AnchorPoint = name, position, size, anchor
	part.BackgroundColor3 = Color3.new(0, 0, 0)
	part.BorderSizePixel = 0
	part.Parent = hole
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(5000, 1)
	constraint.Parent = part
end
blocker("Top", UDim2.new(.5, 0, 0, -5000), UDim2.new(1, 0, 0, 5000), Vector2.new(.5, 0))
blocker("Left", UDim2.new(0, -5000, 0, 0), UDim2.fromOffset(5000, 5000), Vector2.new(0, .5))
blocker("Right", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(5000, 5000), Vector2.new(0, .5))
blocker("Down", UDim2.new(.5, 0, 1, 0), UDim2.new(1, 0, 0, 5000), Vector2.new(.5, 0))
local blur = Instance.new("BlurEffect")
blur.Name, blur.Size, blur.Parent = "PortalTransitionBlur", 0, Lighting
local color = Instance.new("ColorCorrectionEffect")
color.Name, color.Parent = "PortalTransitionColor", Lighting
local active, version, currentToken = false, 0, nil
local hidden, tweens = {}, {}
local info = TweenInfo.new(.72, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
local function sound(name, volume, speed)
	if player:GetAttribute("SFXEnabled") == false then return end
	local template = ReplicatedStorage.Assets.Sounds:FindFirstChild(name)
	if not template then return end
	local s = template:Clone()
	s.Volume, s.PlaybackSpeed, s.Parent = volume, speed or 1, SoundService
	s:Play()
	Debris:AddItem(s, 8)
end
local function hide(other)
	if not other:IsA("ScreenGui") or other == gui or hidden[other] then return end
	local record = {Enabled = other.Enabled}
	hidden[other] = record
	other.Enabled = false
	record.Connection = other:GetPropertyChangedSignal("Enabled"):Connect(function()
		if record.Writing then return end
		record.Enabled = other.Enabled
		if active and other.Enabled then
			record.Writing = true
			other.Enabled = false
			record.Writing = false
		end
	end)
end
local function restore()
	active = false
	for other, record in pairs(hidden) do
		record.Connection:Disconnect()
		if other.Parent then
			if other.Name == "MinigameHUD" then
				other.Enabled = player:GetAttribute("InPortalMinigame") == true
			elseif other.Name == "DesertRatProgress" then
				other.Enabled = player:GetAttribute("InPortalMinigame") == true and player:GetAttribute("MinigameKey") == "DesertHunt"
			else other.Enabled = record.Enabled end
		end
	end
	table.clear(hidden)
end
playerGui.ChildAdded:Connect(function(child) if active then hide(child) end end)
local function cancel()
	for _, tween in ipairs(tweens) do tween:Cancel() end
	table.clear(tweens)
end
local function tween(object, properties)
	local t = TweenService:Create(object, info, properties)
	table.insert(tweens, t)
	t:Play()
	return t
end
local function play(direction, token)
	if direction == "Out" and currentToken ~= token then return end
	version += 1
	local thisVersion = version
	cancel()
	if direction == "In" then
		currentToken = token
		active = true
		for _, other in ipairs(playerGui:GetChildren()) do hide(other) end
		gui.Enabled = true
		aperture.Size = UDim2.fromScale(3.2, 3.2)
		sound("Whoosh", .5, .8)
		local cover = tween(aperture, {Size = UDim2.fromScale(0, 0)})
		tween(blur, {Size = 22})
		tween(color, {Brightness = -.18, Contrast = .3, Saturation = -.85})
		task.spawn(function()
			if cover.Completed:Wait() == Enum.PlaybackState.Completed and version == thisVersion then ready:FireServer(token) end
		end)
		task.delay(12, function()
			if version ~= thisVersion then return end
			cancel()
			gui.Enabled, blur.Size = false, 0
			color.Brightness, color.Contrast, color.Saturation = 0, 0, 0
			restore()
		end)
	elseif direction == "Out" then
		sound("Whoosh", .4, 1.1)
		sound("Magic Shimmer", .25)
		local open = tween(aperture, {Size = UDim2.fromScale(3.2, 3.2)})
		tween(blur, {Size = 0})
		tween(color, {Brightness = 0, Contrast = 0, Saturation = 0})
		task.spawn(function()
			open.Completed:Wait()
			if version == thisVersion then gui.Enabled = false restore() end
		end)
	end
end
transition.OnClientEvent:Connect(play)
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({hole}) end) end)

local MusicManager = require(ReplicatedStorage.Modules.MusicManager)
local tracks = {}
for key, id in pairs({StarterObby = "1837768494", DesertHunt = "1840347412", SnowAvalanche = "1837768517", LavaRun = "1844711929", VoidBloxout = "1845554017"}) do
	local track = Instance.new("Sound")
	track.Name = "PortalMusic_" .. key
	track.SoundId = "rbxassetid://" .. id
	track.Volume, track.Looped, track.Parent = .35, true, SoundService
	MusicManager.Register(track)
	tracks[key] = track
end
local lobby = SoundService:WaitForChild("Background Music")
local selected, resumeLobby = nil, false
local function updateMusic()
	local key = player:GetAttribute("InPortalMinigame") and player:GetAttribute("MinigameKey") or nil
	local target = tracks[key]
	if selected ~= target then
		if selected then MusicManager.Stop(selected, .5) end
		selected = target
		if target then target.TimePosition = 0 MusicManager.Play(target, .5) end
	end
	if target then
		if lobby.IsPlaying then resumeLobby = true MusicManager.Pause(lobby, .5) end
	elseif resumeLobby then
		resumeLobby = false
		MusicManager.Resume(lobby, .5)
	end
end
player:GetAttributeChangedSignal("InPortalMinigame"):Connect(updateMusic)
player:GetAttributeChangedSignal("MinigameKey"):Connect(updateMusic)
lobby.Played:Connect(function() if selected then task.defer(updateMusic) end end)
lobby.Resumed:Connect(function() if selected then task.defer(updateMusic) end end)
updateMusic()
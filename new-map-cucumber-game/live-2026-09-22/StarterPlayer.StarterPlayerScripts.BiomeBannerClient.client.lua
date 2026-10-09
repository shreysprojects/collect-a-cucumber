--[[
	BiomeBannerClient  (LocalScript, StarterPlayerScripts)
	"Desert 😮"-style banner: whenever the player steps INTO a biome (slab containment,
	the same maths as CucumberSpawner.SlabIndexAt / CucumberStreamClient) the biome's
	name pops in at the top centre -- bold rounded FredokaOne with a blue-to-purple
	gradient and a dark outline -- followed by an emoji that gets scarier the deeper
	the biome is (EMOJI ladder below). Holds HOLD seconds, then fades out.
	Fires only when moving UP: the biome entered ranks higher (ZONES index) than the
	biome the player came from. Walking back down, or across border land and back,
	shows nothing. The first biome after a (re)spawn always counts as a step up.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--.. MUST mirror CucumberSpawner
local ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek", "Toyland", "Neon"}
local SLAB_HALF_X = 70
local SLAB_HALF_Z = 56
local SLAB_MARGIN = 6

--.. display name + emoji per biome tier (index = ZONES index): scarier as you go deeper
local DISPLAY = {
	Spawn = "Spawn", Desert = "Desert", Samurai = "Samurai", Farm = "Farm", Snow = "Snow",
	Underwater = "Underwater", Volcano = "Volcano", Narmek = "Narmek", Toyland = "Toyland", Neon = "Neon",
}
local EMOJI = {"🙂", "😮", "😬", "😰", "😨", "😱", "😈", "👿", "💀", "☠️"}

--..Look..--
local TEXT_SIZE = 56 -- design px at 1920x1080; UIScale shrinks it on smaller screens
local TOP_Y = 0.11 -- fraction of the screen, just under the Roblox topbar
local HOLD = 2.4
local FADE = 0.45
local GRADIENT_TOP = Color3.fromRGB(150, 225, 255)
local GRADIENT_BOTTOM = Color3.fromRGB(165, 95, 235)
local OUTLINE = Color3.fromRGB(35, 18, 70)
local SOUND = "Whoosh"

local SpawnArea = workspace:WaitForChild("SpawnArea")
local SoundController
pcall(function()
	SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))
end)

--..GUI..--
local gui = Instance.new("ScreenGui")
gui.Name = "BiomeBanner"
gui.ResetOnSpawn = false
gui.DisplayOrder = 500
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Position = UDim2.fromScale(0.5, TOP_Y)
holder.Size = UDim2.fromOffset(0, TEXT_SIZE + 12)
holder.AutomaticSize = Enum.AutomaticSize.X
holder.Visible = false
holder.Parent = gui
local deviceScale = Instance.new("UIScale")
deviceScale.Name = "DeviceScale"
deviceScale.Parent = holder

local row = Instance.new("Frame")
row.Name = "Row"
row.BackgroundTransparency = 1
row.AnchorPoint = Vector2.new(0.5, 0.5)
row.Position = UDim2.fromScale(0.5, 0.5)
row.Size = UDim2.fromScale(0, 1)
row.AutomaticSize = Enum.AutomaticSize.X
row.Parent = holder
local popScale = Instance.new("UIScale")
popScale.Name = "PopScale"
popScale.Parent = row
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = row

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "BiomeName"
nameLabel.BackgroundTransparency = 1
nameLabel.AutomaticSize = Enum.AutomaticSize.X
nameLabel.Size = UDim2.fromScale(0, 1)
nameLabel.Font = Enum.Font.FredokaOne
nameLabel.TextSize = TEXT_SIZE
nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
nameLabel.Text = ""
nameLabel.LayoutOrder = 1
nameLabel.Parent = row
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(GRADIENT_TOP, GRADIENT_BOTTOM)
gradient.Rotation = 90
gradient.Parent = nameLabel
local outline = Instance.new("UIStroke")
outline.Thickness = 4
outline.Color = OUTLINE
outline.LineJoinMode = Enum.LineJoinMode.Round
outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
outline.Parent = nameLabel

local emojiLabel = Instance.new("TextLabel")
emojiLabel.Name = "Emoji"
emojiLabel.BackgroundTransparency = 1
emojiLabel.AutomaticSize = Enum.AutomaticSize.X
emojiLabel.Size = UDim2.fromScale(0, 1)
emojiLabel.Font = Enum.Font.FredokaOne
emojiLabel.TextSize = TEXT_SIZE
emojiLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
emojiLabel.Text = ""
emojiLabel.LayoutOrder = 2
emojiLabel.Parent = row

local function fitDevice()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	deviceScale.Scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.5, 1)
end

--..Show / hide..--
local token = 0
local function setTransparency(t)
	nameLabel.TextTransparency = t
	emojiLabel.TextTransparency = t
	outline.Transparency = t
end

local function show(index)
	local zone = ZONES[index]
	if not zone then return end
	token += 1
	local my = token
	fitDevice()
	nameLabel.Text = DISPLAY[zone] or zone
	emojiLabel.Text = EMOJI[index] or EMOJI[#EMOJI]
	setTransparency(0)
	holder.Visible = true
	popScale.Scale = 0.6
	TweenService:Create(popScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	if SoundController then
		pcall(SoundController.PlayFX, SOUND, {Volume = 0.35, Speed = 1.1, Key = "BiomeBanner", MinInterval = 0.5})
	end
	task.delay(HOLD, function()
		if my ~= token then return end
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(nameLabel, info, {TextTransparency = 1}):Play()
		TweenService:Create(emojiLabel, info, {TextTransparency = 1}):Play()
		TweenService:Create(outline, info, {Transparency = 1}):Play()
		task.delay(FADE, function()
			if my == token then holder.Visible = false end
		end)
	end)
end

--..Biome detection (same slab rule as the server)..--
local function slabIndexAt(position)
	local zones = workspace:FindFirstChild("Zones")
	local zoneParts = zones and zones:FindFirstChild("ZoneParts")
	for index, zone in ipairs(ZONES) do
		local slab = zoneParts and zoneParts:FindFirstChild(zone)
		local halfX, halfZ
		if slab and slab:IsA("BasePart") then
			halfX, halfZ = slab.Size.X * 0.5, slab.Size.Z * 0.5
		else
			slab = SpawnArea:FindFirstChild(tostring(index))
			halfX, halfZ = SLAB_HALF_X, SLAB_HALF_Z
		end
		if slab and slab:IsA("BasePart") then
			local lp = slab.CFrame:PointToObjectSpace(position)
			if math.abs(lp.X) <= halfX + SLAB_MARGIN and math.abs(lp.Z) <= halfZ + SLAB_MARGIN and lp.Y >= -15 and lp.Y <= 150 then
				return index
			end
		end
	end
	return nil
end

local lastBiome = nil -- ZONES index of the biome the player last stood inside
task.spawn(function()
	while true do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local inside = slabIndexAt(root.Position)
			if inside and inside ~= lastBiome then
				local movingUp = lastBiome == nil or inside > lastBiome
				lastBiome = inside
				if movingUp then show(inside) end
			end
		end
		task.wait(0.2)
	end
end)
player.CharacterAdded:Connect(function()
	lastBiome = nil -- a fresh spawn starts the ladder over
end)

--.. Studio dev hook: workspace:SetAttribute("BiomeBannerDev", <index>) previews a banner
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("BiomeBannerDev"):Connect(function()
		local index = tonumber(workspace:GetAttribute("BiomeBannerDev"))
		if index then show(index) end
	end)
end

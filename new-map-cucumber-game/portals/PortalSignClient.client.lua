--[[
	PortalSignClient  (LocalScript, StarterPlayerScripts)  2026-09-22
	The sign above every portal, drawn for the local player on the invisible anchor part PortalService
	hangs over each portal (tag "PortalSign", attrs PortalDestination / StrengthRequired):
	  * top line  : this player's cooldown on that portal, "1:00:00" then "59:59" ... "0:01", hidden
	                when the portal is ready (player attribute PortalReadyAt_<destination>, server time)
	  * bottom row: [strength icon] + the strength needed to enter ("560", "1.35B"), green once
	                player.Data.Strength reaches it, red while it is short
	Sized in STUDS like the plot owner badge (user rule): the BillboardGui is SIGN_W x SIGN_H studs,
	its content is laid out in DESIGN px and one UIScale fits it to the billboard's current pixel size,
	so the icon + number stay centred as a pair at every distance. Streaming-safe: the anchor carries
	the gui, and a fresh one is built whenever the anchor streams back in.
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev"))

local player = Players.LocalPlayer

local TAG = "PortalSign"
local COOLDOWN_ATTR = "PortalReadyAt_"
local STRENGTH_ICON = "rbxassetid://15403007921" -- the HUD's strength icon (CucumberHUDDesign.Counters.StrengthIcon)
local DESIGN_W, DESIGN_H = 320, 150 -- px layout, fitted to the billboard by a UIScale
local SIGN_W = 11 -- studs, about a portal's width
local SIGN_H = SIGN_W * DESIGN_H / DESIGN_W
local MAX_DISTANCE = 150 -- studs: about one biome, so the lobby does not see the Spawn portal's sign
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic) -- the HUD counters' face
local OUTLINE = Color3.fromRGB(12, 12, 12) -- the HUD counters' outline
local MET = Color3.fromRGB(65, 235, 20) -- the HUD cash green
local UNMET = Color3.fromRGB(240, 58, 58) -- Notify's red
local STEP = 0.2 -- seconds between refreshes

local signs = {} -- [anchor] = {Gui, Root, Scale, Timer, Value}

-- 3600 -> "1:00:00", 3599 -> "59:59", 42 -> "0:42" (PortalService.FormatTime)
local function formatTime(seconds)
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then return ("%d:%02d:%02d"):format(s // 3600, s % 3600 // 60, s % 60) end
	return ("%d:%02d"):format(s // 60, s % 60)
end

local strengthValue
local function strength()
	if not strengthValue or not strengthValue.Parent then
		local data = player:FindFirstChild("Data")
		strengthValue = data and data:FindFirstChild("Strength")
	end
	return strengthValue and strengthValue.Value or 0
end

local function textLabel(parent, name, size, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Size = size
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 4
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

local function refresh(anchor, sign)
	local key = anchor:GetAttribute("CooldownKey") or anchor:GetAttribute("PortalDestination") -- per-portal key (PortalService.cooldownKey)
	local readyAt = key and player:GetAttribute(COOLDOWN_ATTR .. tostring(key))
	local left = typeof(readyAt) == "number" and readyAt - workspace:GetServerTimeNow() or 0
	sign.Timer.Visible = left > 0
	if left > 0 then sign.Timer.Text = formatTime(left) end
	local required = anchor:GetAttribute("StrengthRequired")
	required = typeof(required) == "number" and required or 0
	sign.Value.Text = NumberAbbrev.Abbrev(required)
	sign.Value.TextColor3 = strength() >= required and MET or UNMET
end

local function fit(sign)
	local width = sign.Gui.AbsoluteSize.X
	if width > 0 then sign.Scale.Scale = width / DESIGN_W end
end

local function build(anchor)
	if signs[anchor] or not anchor:IsA("BasePart") then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PortalSignGui"
	gui.Size = UDim2.fromScale(SIGN_W, SIGN_H) -- scale = studs: shrinks with distance
	gui.SizeOffset = Vector2.new(0, 0.5) -- bottom edge on the anchor, just over the portal's top
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = anchor

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = root

	local timer = textLabel(root, "Cooldown", UDim2.fromOffset(DESIGN_W, 66), 60)
	timer.LayoutOrder = 1
	timer.Visible = false

	local row = Instance.new("Frame")
	row.Name = "Strength"
	row.LayoutOrder = 2
	row.Size = UDim2.fromOffset(DESIGN_W, 70)
	row.BackgroundTransparency = 1
	row.Parent = root
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = row
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromOffset(62, 62)
	icon.BackgroundTransparency = 1
	icon.Image = STRENGTH_ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row
	local value = textLabel(row, "Value", UDim2.fromOffset(0, 70), 60)
	value.LayoutOrder = 2
	value.AutomaticSize = Enum.AutomaticSize.X

	local sign = {Gui = gui, Root = root, Scale = scale, Timer = timer, Value = value}
	signs[anchor] = sign
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() fit(sign) end)
	refresh(anchor, sign)
	gui.Parent = anchor
	fit(sign)
end

local function drop(anchor)
	local sign = signs[anchor]
	if not sign then return end
	signs[anchor] = nil
	sign.Gui:Destroy()
end

for _, anchor in ipairs(CollectionService:GetTagged(TAG)) do build(anchor) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(build)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(drop)

local elapsed = STEP
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < STEP then return end
	elapsed = 0
	for anchor, sign in pairs(signs) do
		if anchor.Parent then refresh(anchor, sign) else drop(anchor) end
	end
end)

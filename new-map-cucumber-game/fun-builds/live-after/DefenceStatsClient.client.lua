--[[
	DefenceStatsClient  (LocalScript, StarterPlayerScripts)  2026-09-24
	User: "above each defense have an overhead ui that shows damage (same symbol as pets damage indicator) and shows
	range (make up some symbol beside it) (both in same line)".
	Every placed defence (tag "PlacedBuild" whose BuildKey names a ReplicatedStorage.PlaceableBuilds.Defences template
	that carries StatDamage - DefenceService stamps StatDamage / StatDamageSuffix / StatRange from the same numbers it
	fires with) gets one BillboardGui over its Hitbox, one line:
	    [Ammo icon] 100      [range glyph] 45
	  * damage: PetCardClient's DAMAGE_ICON (the "Ammo" image) and its Fighter red, NumberAbbrev'd, the suffix after it
	    ("800/s" on the laser gate, which burns per second)
	  * range: a made-up RANGE glyph drawn from frames - a ring with a centre dot and a radius arrow running out to the
	    ring - and the reach in studs, in a sky blue
	Sized in STUDS like every overhead UI here (a BillboardGui's scale units are studs), AlwaysOnTop off, LightInfluence 0,
	MaxDistance MAX_DISTANCE, GAP_ABOVE over the hitbox top; while BuildHealthService's BuildHealthTag is showing (the
	build is damaged) the line lifts above it. Hidden while the build is Broken, and (2026-09-24, user) shown ONLY while
	this player is in build mode. Streaming: built when the (atomic)
	model streams in or is placed, gone with it; a moved build keeps it (it rides the Hitbox).
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev"))

--.. 2026-09-24 (user: "make stats of each defense only show in build mode"): the labels show only while this player is in
--.. build mode = PlayerGui.CucumberHUDDesign attribute BuildMode (set by BuildMenuClient, read the same way by BoostPadClient /
--.. FunBuildClient)
local HUD_NAME = "CucumberHUDDesign"
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local function InBuildMode()
	local hud = playerGui:FindFirstChild(HUD_NAME)
	return hud ~= nil and hud:GetAttribute("BuildMode") == true
end

--..Config..--
local TAG = "PlacedBuild"
local CATEGORY = "Defences"
local GUI_NAME = "DefenceStatsTag"
local HEALTH_TAG = "BuildHealthTag"      -- BuildHealthService's bar over the same Hitbox
local HEALTH_TOP = 0.6 + 1.5              -- studs over the hitbox top the health bar reaches (its BAR_ABOVE + BAR_HEIGHT)
local ROW_H = 1.15                        -- studs: the line's height
local GAP_ABOVE = 0.45                    -- studs between the hitbox top (or the health bar) and the line
local CHAR_W = 0.56                       -- FredokaOne advance per character, in text heights
local ICON = 0.95                         -- icon squares, in row heights
local ITEM_GAP = 0.12                     -- between an icon and its number, in row heights
local GROUP_GAP = 0.55                    -- between the damage and the range groups, in row heights
local MAX_DISTANCE = 80
local FONT = Enum.Font.FredokaOne
local DAMAGE_ICON = "rbxassetid://15403025691" -- = PetCardClient.DAMAGE_ICON (Image asset "Ammo")
local DAMAGE_COLOR = Color3.fromRGB(255, 90, 70) -- = PetCardClient.DAMAGE_COLOR (the Fighter red)
local RANGE_COLOR = Color3.fromRGB(90, 200, 255)
local DARK = Color3.fromRGB(25, 20, 35)          -- = PetCardClient.DARK_STROKE
local STROKE = 2.4

--..Templates..--
local function TemplateFor(key)
	local root = ReplicatedStorage:FindFirstChild("PlaceableBuilds")
	local folder = root and root:FindFirstChild(CATEGORY)
	return folder and folder:FindFirstChild(tostring(key)) or nil
end

--..Drawing..--
local function New(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function Stroke(parent, thickness, color)
	return New("UIStroke", {Thickness = thickness or STROKE, Color = color or DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, parent)
end

local function Round(parent)
	New("UICorner", {CornerRadius = UDim.new(1, 0)}, parent)
end

--.. the made-up range symbol: a ring (dark under blue), a centre dot and an arrow along the radius to the ring
local function RangeGlyph(parent)
	local box = New("Frame", {Name = "RangeIcon", BackgroundTransparency = 1, LayoutOrder = 3}, parent)
	local ring = New("Frame", {
		Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78), BackgroundTransparency = 1,
	}, box)
	Round(ring)
	Stroke(ring, 5, DARK)
	local inner = New("Frame", {
		Name = "RingColour", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	}, ring)
	Round(inner)
	Stroke(inner, 2.4, RANGE_COLOR)
	local dot = New("Frame", {
		Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.2, 0.2), BackgroundColor3 = RANGE_COLOR, BorderSizePixel = 0,
	}, box)
	Round(dot)
	Stroke(dot, 1.5, DARK)
	--.. the radius: a line from the centre up-right to the ring with a bead on the ring - a measuring "reach" mark.
	--.. (GuiObject.Rotation turns about the frame's own centre, so the line is centred halfway along the radius)
	local r, a = 0.39, math.rad(35)
	local dx, dy = math.cos(a), -math.sin(a)
	local shaft = New("Frame", {
		Name = "Radius", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + dx * r * 0.5, 0.5 + dy * r * 0.5),
		Size = UDim2.fromScale(r, 0.09), BackgroundColor3 = RANGE_COLOR, BorderSizePixel = 0, Rotation = -35,
	}, box)
	Stroke(shaft, 1.2, DARK)
	local bead = New("Frame", {
		Name = "Bead", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + dx * r, 0.5 + dy * r),
		Size = UDim2.fromScale(0.2, 0.2), BackgroundColor3 = RANGE_COLOR, BorderSizePixel = 0,
	}, box)
	Round(bead)
	Stroke(bead, 1.5, DARK)
	return box
end

local function Label(name, order, color, parent)
	local label = New("TextLabel", {
		Name = name, LayoutOrder = order, BackgroundTransparency = 1, Font = FONT, TextScaled = true,
		TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	}, parent)
	New("UIStroke", {Thickness = STROKE, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual}, label) -- outlines the TEXT
	return label
end

--..One tag per model..--
local Tags = {} -- [model] = {Gui, Conns}

local function Unbuild(model)
	local rec = Tags[model]
	if not rec then return end
	Tags[model] = nil
	for _, c in ipairs(rec.Conns) do c:Disconnect() end
	if rec.Gui then rec.Gui:Destroy() end
end

local function Build(model)
	if Tags[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then return end
	local key = model:GetAttribute("BuildKey")
	local template = key and TemplateFor(key)
	if not template then return end
	local hitbox = model.PrimaryPart or model:FindFirstChild("Hitbox")
	if not hitbox then return end
	local rec = {Conns = {}}
	Tags[model] = rec

	local gui = New("BillboardGui", {
		Name = GUI_NAME, Adornee = hitbox, AlwaysOnTop = false, LightInfluence = 0, MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false, ClipsDescendants = false,
	})
	rec.Gui = gui
	local row = New("Frame", {Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, gui)
	local list = New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local damageIcon = New("ImageLabel", {
		Name = "DamageIcon", LayoutOrder = 1, BackgroundTransparency = 1, Image = DAMAGE_ICON,
		ScaleType = Enum.ScaleType.Fit,
	}, row)
	local damageText = Label("Damage", 2, DAMAGE_COLOR, row)
	local spacer = New("Frame", {Name = "Gap", LayoutOrder = 3, BackgroundTransparency = 1}, row)
	local rangeIcon = RangeGlyph(row)
	rangeIcon.LayoutOrder = 4
	local rangeText = Label("Range", 5, RANGE_COLOR, row)

	--.. the texts come from the template (DefenceService stamps them a moment after the templates exist)
	local function Render()
		local damage = tonumber(template:GetAttribute("StatDamage"))
		local range = tonumber(template:GetAttribute("StatRange"))
		if not damage then
			gui.Enabled = false
			return
		end
		local dText = NumberAbbrev.Abbrev(damage) .. tostring(template:GetAttribute("StatDamageSuffix") or "")
		local rText = range and NumberAbbrev.Abbrev(math.floor(range + 0.5)) or "" -- whole studs ("5", not "4.75")
		damageText.Text = dText
		rangeText.Text = rText
		--.. widths in row heights, then as fractions of the whole line
		local wIcon, wGap, wGroup = ICON, ITEM_GAP, GROUP_GAP
		local wDmg = #dText * CHAR_W
		local wRng = #rText * CHAR_W
		local showRange = rText ~= ""
		local total = wIcon + wGap + wDmg + (showRange and (wGroup + wIcon + wGap + wRng) or 0)
		local W = total * ROW_H
		gui.Size = UDim2.fromScale(W, ROW_H)
		local function frac(w) return UDim2.fromScale(w / total, 1) end
		damageIcon.Size = UDim2.fromScale(wIcon / total, ICON)
		damageText.Size = frac(wDmg + wGap)
		spacer.Size = frac(wGroup)
		rangeIcon.Size = UDim2.fromScale(wIcon / total, ICON)
		rangeText.Size = frac(wRng + wGap)
		spacer.Visible, rangeIcon.Visible, rangeText.Visible = showRange, showRange, showRange
		list.Padding = UDim.new(0, 0)
		--.. icon-number spacing via the text's own left padding
		local pad = damageText:FindFirstChildOfClass("UIPadding") or New("UIPadding", {}, damageText)
		pad.PaddingLeft = UDim.new(wGap / (wDmg + wGap), 0)
		local rpad = rangeText:FindFirstChildOfClass("UIPadding") or New("UIPadding", {}, rangeText)
		rpad.PaddingLeft = UDim.new(wGap / math.max(wRng + wGap, 1e-3), 0)
	end

	--.. height: over the hitbox, or over the health bar while it shows; hidden while Broken
	local healthTag
	local function Place()
		local lift = hitbox.Size.Y * 0.5 + GAP_ABOVE + ROW_H * 0.5
		if healthTag and healthTag.Parent and healthTag.Enabled then lift += HEALTH_TOP end
		gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
		gui.Enabled = InBuildMode() and model:GetAttribute("Broken") ~= true and tonumber(template:GetAttribute("StatDamage")) ~= nil
	end
	rec.Place = Place
	local function WatchHealth(inst)
		if inst:IsA("BillboardGui") and inst.Name == HEALTH_TAG and inst ~= healthTag then
			healthTag = inst
			table.insert(rec.Conns, inst:GetPropertyChangedSignal("Enabled"):Connect(Place))
			Place()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do WatchHealth(d) end
	table.insert(rec.Conns, model.DescendantAdded:Connect(WatchHealth))
	table.insert(rec.Conns, model:GetAttributeChangedSignal("Broken"):Connect(Place))
	table.insert(rec.Conns, template.AttributeChanged:Connect(function(name)
		if name:sub(1, 4) == "Stat" then Render() Place() end
	end))
	table.insert(rec.Conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then Unbuild(model) end
	end))
	Render()
	Place()
	gui.Parent = hitbox
end

--..Setup: placed / streamed builds (the tag can arrive a moment before the BuildKey attribute and the Hitbox)..--
local function Consider(model)
	if Tags[model] then return end
	task.spawn(function()
		local t0 = os.clock()
		while model.Parent and (not model:GetAttribute("BuildKey") or not (model.PrimaryPart or model:FindFirstChild("Hitbox"))) and os.clock() - t0 < 10 do
			task.wait(0.2)
		end
		--.. the templates may not have replicated yet on a fresh join
		local root = ReplicatedStorage:WaitForChild("PlaceableBuilds", 60)
		if root then root:WaitForChild(CATEGORY, 30) end
		if model.Parent and CollectionService:HasTag(model, TAG) then Build(model) end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(Consider)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Unbuild)
for _, model in ipairs(CollectionService:GetTagged(TAG)) do Consider(model) end

--..Build mode on / off: every label follows (the HUD can arrive after this script starts)..--
local function RefreshAll()
	for _, rec in pairs(Tags) do
		if rec.Place then rec.Place() end
	end
end
task.spawn(function()
	local hud = playerGui:WaitForChild(HUD_NAME, 60)
	if hud then
		hud:GetAttributeChangedSignal("BuildMode"):Connect(RefreshAll)
		RefreshAll()
	end
end)
print("[DefenceStatsClient] ready")

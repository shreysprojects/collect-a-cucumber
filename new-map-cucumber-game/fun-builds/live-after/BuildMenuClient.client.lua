--[[
	BuildMenuClient  (LocalScript, StarterGui.BuildMenu)  2026-09-10
	Build mode (user: "clicking Build hides Build / Manage and the backpack; bottom-middle buttons in the
	HUD style, one per ServerStorage.Builds category; a category shows its builds - title, viewport,
	cost - in a long row at the bottom; clicking a build buys it, it is on your mouse and you place it in
	your base").
	  * Build (LeftMenu.Build.BuildButton) -> Enter: HUD attribute BuildMode = true (BaseHUDController
	    tucks the whole left menu away with its swap motion), the Hotbar ScreenGui is disabled, tools
	    are unequipped and the Categories row pops up: one CategoryButton per PlaceableBuilds subfolder
	    (BuildCatalog.CATEGORIES order + colours, unknown folders after them), a square close button
	    whose only content is a red "X" label, and two square icon buttons: Sell (a price tag; toggles
	    sell mode; a trash can) and Grid (a frame-drawn grid that gains one line each way per press, the
	    size in its corner; cycles the snap size). A Staircase is refused upstairs ("Stairs go on the ground floor").
	  * a category -> the Catalog panel: Bar (Back, title, hint) over a horizontal Row of BuildCards
	    (ViewportFrame of the template, DisplayName, cash cost), cheapest first. Since 2026-09-12 (final
	    form, user: "put the pick a build UI just above the other build buttons at bottom ... get rid of
	    the back button ... the 'pick a build' label ... the category title ... hide the background.
	    essentially itll just show the builds cards") the Catalog is a BARE STRIP OF CARDS: no panel
	    (background, outline and Fill hidden), no Bar (Back / title / hint hidden), the Row fills the
	    frame, the strip is only as wide as its cards (capped at 62 % of the screen, then it scrolls)
	    and sits CATALOG_GAP px above the Categories row, which stays on screen so another category is
	    one click away. Opening a category RISES the strip RISE px into place (Rise, Heartbeat-stepped)
	    while the first cards pop. Cancel while placing brings BOTH the strip and the row back
	    (RestorePanels; the row used to stay hidden - user: "clicking cancel ... hides the build buttons").
	  * THIEF (2026-09-12): a daytime thief getting away with a cucumber (ZombieRaid "ThiefStole") closes
	    build mode ("Build mode closed.").
	  * NIGHT (2026-09-12): build mode cannot be entered while workspace.CyclePhase == "Night" ("You
	    can't build at night") and the moment night falls an open build mode Exits with a toast.
	  * a card -> if the player can afford it, the template's ghost follows the mouse and the catalog
	    HIDES: only the Placing strip stays (a hint line over Rotate / Grid / Collisions / Cancel; the
	    Collisions checkbox, ticked by default, is sent with every placement and move - unticked, builds
	    may intersect each other, see BuildCatalog.Blocks). The ghost is clamped
	    inside the plot on the current grid (the Grid button cycles BuildCatalog.GRID_SIZES: 2 / 1 /
	    0.5 studs since 2026-09-13; a Flooring tile snaps to the nearest grass cell - an edge strip too, stretched to fit -
	    a Staircase so its landing edge lies on a cell boundary) and, whenever it cannot go there, its parts turn RED and a red Highlight covers
	    it; click / tap places it through Remotes.requestBuildPlacement (where the Cash are charged),
	    R / Rotate turns it 90 deg, Cancel drops it and the catalog comes back. There is no Escape
	    keybind (user 2026-09-10) and right-click never cancels (it is the camera orbit). After a
	    placement the same build stays on the mouse so walls tile quickly.
	  * MOVING: in build mode, hovering one of the player's placed builds lights it up; clicking it
	    lifts it onto the mouse (the original goes see-through locally), the same strip shows, a click
	    drops it through Remotes.requestBuildMove (free, same rules), Cancel puts it back.
	  * MOVING CUCUMBERS (2026-09-13, user: "let users be able to move cucumbers around in build mode
	    / make cucumber highlight red when cannot be placed somewhere"): a placed cucumber of yours
	    (tag PlacedCucumber; its PlotHitbox answers the mouse ray) lights up like a build and a click
	    lifts a see-through copy onto the mouse (StartMovingCucumber; the original fades). The copy
	    follows the plot surface on the current grid in its rest pose, R rotates it, and its parts +
	    Highlight go RED whenever it hangs outside the plot or its RestSize box overlaps anything else
	    in Placed (UpdateCucumberPreview: the same test CucumberMoveServer runs). A click sends
	    Remotes.requestCucumberMove(model, TargetCF); Cancel puts it back. Sell mode refuses them.
	  * SELLING (2026-09-10): the Sell button toggles sell mode - the hover glow turns red and clicking a
	    placed build sells it through Remotes.requestBuildSell (BuildCatalog.SELL_REFUND of its Cost
	    comes back, a toast says so). Opening a category or leaving build mode turns it off.
	  * STRENGTH LOCKS (2026-09-23 economy): a template's Unlock attribute (BuildCatalog.UNLOCK_STRENGTH)
	    is the Strength it needs; a card above player.Data.Strength is dimmed by a dark LockShade overlay
	    with a white "🔒 💪3K" label and a click only toasts "Needs 💪3K strength". Re-read on every
	    Strength change and every category open (RefreshLocks); the server refuses the placement too.
	  * RANGE DISC (2026-09-23, user: "show defense range when defense is selected in build mode (like a
	    big circle around it)"): a defence template carries Range / MinRange attributes (DefenceService
	    publishes its own numbers onto RS.PlaceableBuilds.Defences at startup - the server owns them).
	    While such a build is on the mouse - picked from a card or lifted for a move - a flat translucent
	    disc of that radius with a bright Neon rim (model "RangeDisc" in workspace, deliberately NOT
	    inside the ghost so the red OccupiedHighlight leaves it alone) sits on the ghost's floor; a
	    MinRange (catapult / mortar) shows as a red inner dead zone. It hides with the ghost away from
	    the base and goes with StopPlacing. Traps, gates, walls, pads: no Range, no disc.
	  * floors: the ghost lands on the floor the player stands on (BuildCatalog.PlayerLevel); upstairs
	    it aims at that floor's plane. A tile's TOP and a build's BOTTOM both sit at
	    BuildCatalog.SurfaceY(level). Tiles and builds pass each other on the ground (a tile slides
	    under a wall and replaces the grass tile); upstairs anything but a tile needs flooring under
	    its whole footprint ("Needs flooring under it") and a tile must join the floor - edge to edge
	    with a tile already up there, or the cell straight off a staircase landing ("Start at the top
	    of a staircase" / "Place it next to another tile"). Same rules as BuildService.
	  * the X, walking out of the base (HUD BaseMode false), dying or respawning -> Exit: everything
	    hidden, BuildMode false (the left menu slides back), Hotbar enabled again.
	Sizes are computed in pixels from the ScreenGui's AbsoluteSize (Fit) like HotbarClient; motion is
	Heartbeat-stepped (ButtonFX.Animate) so it also plays in an unfocused Studio.
	Dev hook: BuildMenu attribute BuildDev = "enter" | "exit" | "back" | "category:<Name>" |
	"pick:<Key>" | "place" | "place:<x>,<z>" (plot-space target, then place) | "rotate" | "cancel" |
	"move:<placed model name>" | "move:last" | "movecucumber:<name>|last" | "sell" (toggle) | "sellclick:<Name>|last" | "grid" (cycle) |
	"collisions" (toggle) | "aim:<x>,<z>" (hold the ghost at a plot-space spot until "aim:off").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BuildCatalog = require(Modules:WaitForChild("BuildCatalog"))
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))
local Notify = require(Modules:WaitForChild("Notify"))
local CucumberFootprint = require(Modules:WaitForChild("CucumberFootprint")) -- 2026-09-13: a moved cucumber's collision box
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev")) -- 2026-09-23 economy: the "🔒 💪3K" lock labels

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local gui = script.Parent
local Categories = gui:WaitForChild("Categories")
local Catalog = gui:WaitForChild("Catalog")
local Bar = Catalog:WaitForChild("Bar")
local Row = Catalog:WaitForChild("Row")
local Placing = gui:WaitForChild("Placing")
local PlacingHint = Placing:WaitForChild("Hint")
local PlacingButtons = Placing:WaitForChild("Buttons")
local RotateButton = PlacingButtons:WaitForChild("RotateButton")
local StripGrid = PlacingButtons:WaitForChild("GridButton")
local StripCollisions = PlacingButtons:WaitForChild("CollisionsButton")
local CancelButton = PlacingButtons:WaitForChild("CancelButton")
local Templates = gui:WaitForChild("Templates")
local Icons = Templates:WaitForChild("Icons")
local hud = playerGui:WaitForChild("CucumberHUDDesign")
local buildButton = hud:WaitForChild("LeftMenu"):WaitForChild("Build"):WaitForChild("BuildButton")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestBuildPlacement = Remotes:WaitForChild(BuildCatalog.REMOTE)
local requestBuildMove = Remotes:WaitForChild(BuildCatalog.MOVE_REMOTE)
local requestCucumberMove = Remotes:WaitForChild("requestCucumberMove", 30) -- CucumberMoveServer (2026-09-13); nil = no cucumber moving
local CUCUMBER_TAG = "PlacedCucumber"
local requestBuildSell = Remotes:WaitForChild(BuildCatalog.SELL_REMOTE)
local TemplatesFolder = BuildCatalog.TemplatesFolder()
local Lobby = workspace:WaitForChild("Map"):WaitForChild("Lobby")
local Plots = Lobby:WaitForChild("Plots")

--..Config..--
local ROTATION_STEP = 90 -- degrees per R / Rotate
local PREVIEW_TRANSPARENCY = 0.5
local INVALID_COLOR = Color3.fromRGB(255, 60, 60) -- the ghost's parts while it cannot be placed
local COLLISION_SHRINK = 0.96 -- keep in step with BuildService
local AT_BASE_MARGIN = 6 -- keep in step with BuildService / BaseHUDController
local BOUNDS_EPSILON = 0.05
local VIEW_FOV = 35
local VIEW_DIRECTION = Vector3.new(0.85, 0.6, 1).Unit -- card camera: front-top-right of the build
local BUTTON_ASPECT = 2.6 -- the HUD buttons are 122 x 47
local BOTTOM = 14 -- px above the bottom edge
local CATALOG_GAP = 10 -- px between the Categories row and the card strip above it
local RISE = 36 -- px the card strip rises into place when a category opens
local DARK = Color3.fromRGB(12, 12, 12)
local SUPPORT_HINT = "Needs flooring under it"
local FIRST_TILE_HINT = "Start at the top of a staircase"
local NEXT_TILE_HINT = "Place it next to another tile"
local STAIRS_HINT = "Stairs go on the ground floor"
local CASH_GREEN = Color3.fromRGB(65, 235, 20) -- the HUD cash counter's green (2026-09-19: card prices are "$1,200" in it, no cash icon)
--.. RANGE DISC (2026-09-23): a defence's reach drawn on the ground around the ghost while it is on the mouse
local RANGE_COLOR = Color3.fromRGB(120, 205, 255) -- the fill
local RANGE_RIM_COLOR = Color3.fromRGB(55, 170, 255) -- the rim: deeper blue so the Neon glows cyan instead of washing to white
local RANGE_DEAD_COLOR = Color3.fromRGB(255, 90, 80) -- the inner dead zone a catapult / mortar cannot hit
local RANGE_FILL_TRANSPARENCY = 0.78
local RANGE_DEAD_TRANSPARENCY = 0.7
local RANGE_RIM_TRANSPARENCY = 0.1
local RANGE_RIM_WIDTH = 1 -- studs across the rim (0.5 read as a hairline from a build-mode camera)
local RANGE_LIFT = 0.12 -- studs above the ghost's floor: clear of the grass tiles / flooring top, no z-fight

--..State..--
local mode = "off" -- "off" | "categories" | "catalog"
local currentCategory = nil
local cards = {} -- [category] = {card frames in order}
local cardTemplates = {} -- [card] = template model
local placing = nil -- {Template, Card, Moving, Plot, Preview, Hitbox, Highlight, Yaw, TargetCF, Valid, IsFloor, IsStairs, Hint, Colors, Tinted, Hidden, RangeDisc, Connections}
local targetOverride = nil -- dev: plot-space Vector2 instead of the mouse
local aimOverride = nil -- dev: a standing aim (BuildDev "aim:x,z") the place hook does not clear
local layout = {CardW = 120, CardH = 150}
local selling = false
local gridIndex = 1
local collisions = BuildCatalog.DEFAULT_COLLISIONS
local sellButton, gridButton
local OpenCategory, Exit, StopPlacing, Pick, Fit, StartMoving, SetSelling, SetCollisions, StartMovingCucumber

--..Helpers..--
local function MyPlot()
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function Cash()
	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild("Cash")
	return value and tonumber(value.Value) or 0
end

--.. player.Data.Strength, the same value object HUDClient's counter follows (2026-09-23 economy: strength unlocks)
local function Strength()
	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild("Strength")
	return value and tonumber(value.Value) or 0
end

local function Paint(shell, look)
	shell.Fill.ColorGradient.Color = ColorSequence.new(look.Top, look.Bottom)
	shell.Fill.InnerHighlight.Outline.Color = look.Highlight
end

local function PopScale(target)
	local scale = target:FindFirstChild("Pop")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = target
	end
	return scale
end

local popTokens = {}
local function Pop(target, from, seconds)
	local scale = PopScale(target)
	local token = (popTokens[target] or 0) + 1
	popTokens[target] = token
	scale.Scale = from
	task.spawn(function()
		ButtonFX.Animate(seconds or 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function(a)
			scale.Scale = from + (1 - from) * a
		end, function() return target.Parent ~= nil and popTokens[target] == token end)
		if popTokens[target] == token then scale.Scale = 1 end
	end)
end

--.. the card strip slides up RISE px into its place (layout.CatalogY, set by Fit) when a category opens
local riseToken = 0
local function Rise()
	riseToken += 1
	local token = riseToken
	local baseY = layout.CatalogY or -(BOTTOM + 60 + CATALOG_GAP)
	Catalog.Position = UDim2.new(0.5, 0, 1, baseY + RISE)
	task.spawn(function()
		ButtonFX.Animate(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			Catalog.Position = UDim2.new(0.5, 0, 1, baseY + RISE * (1 - a))
		end, function() return riseToken == token and Catalog.Visible end)
		if riseToken == token then Catalog.Position = UDim2.new(0.5, 0, 1, layout.CatalogY or baseY) end
	end)
end

local function Hover(press, target, amount)
	press.MouseEnter:Connect(function() PopScale(target).Scale = amount end)
	press.MouseLeave:Connect(function() PopScale(target).Scale = 1 end)
end

local function SetHotbar(enabled)
	local hotbar = playerGui:FindFirstChild("Hotbar")
	if hotbar and hotbar:IsA("ScreenGui") then hotbar.Enabled = enabled end
end

local function Root()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") or nil
end

local function GridSize()
	return BuildCatalog.GRID_SIZES[gridIndex] or 1
end

local function GridTag()
	local g = GridSize()
	if g == math.floor(g) then return tostring(math.floor(g)) end
	return (tostring(g):gsub("^0", ""))
end
--.. the grid glyph: gridIndex + 1 dark bars each way inside the box (1 stud = 2 = the 3 x 3 look)
local function DrawGrid(box)
	local lines = box and box:FindFirstChild("Lines")
	if not lines then return end
	lines:ClearAllChildren()
	local n = gridIndex + 1
	for i = 1, n do
		local at = i / (n + 1)
		for _, vertical in ipairs({true, false}) do
			local bar = Instance.new("Frame")
			bar.Name = vertical and ("V" .. i) or ("H" .. i)
			bar.BackgroundColor3 = DARK
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = vertical and UDim2.fromScale(at, 0.5) or UDim2.fromScale(0.5, at)
			bar.Size = vertical and UDim2.new(0, 2, 1, 0) or UDim2.new(1, 0, 0, 2)
			bar.ZIndex = 15
			bar.Parent = lines
		end
	end
end
local function UpdateGridButtons()
	local tag = GridTag()
	if gridButton and gridButton.Parent then
		gridButton.Corner.Text = tag
		local glyph = gridButton.Icon:FindFirstChild("Glyph")
		DrawGrid(glyph and glyph:FindFirstChild("Box"))
	end
	StripGrid.Corner.Text = tag
	DrawGrid(StripGrid.Icon:FindFirstChild("Box"))
end
local function CycleGrid()
	gridIndex = gridIndex % #BuildCatalog.GRID_SIZES + 1
	UpdateGridButtons()
	if gridButton and gridButton.Parent then Pop(gridButton, 0.9, 0.2) end
	Pop(StripGrid, 0.9, 0.2)
end

--..Sizes (pixels from the ScreenGui, like HotbarClient)..--
function Fit()
	local size = gui.AbsoluteSize
	if size.X < 50 or size.Y < 50 then return end
	local h = math.clamp(math.floor(size.Y * 0.085), 44, 74)
	local w = math.floor(h * BUTTON_ASPECT)
	--.. 2026-09-24 (Home category = 5 categories): shrink the whole row evenly when it would not fit a narrow phone
	do
		local nCat, nSquare = 0, 0
		for _, button in ipairs(Categories:GetChildren()) do
			if button:IsA("Frame") then
				if button.Name == "Done" or button.Name == "Sell" or button.Name == "Grid" then nSquare += 1 else nCat += 1 end
			end
		end
		local list = Categories:FindFirstChildOfClass("UIListLayout")
		local pad = list and list.Padding.Offset or 8
		local need = nCat * w + nSquare * h + math.max(0, nCat + nSquare - 1) * pad
		local avail = size.X - 24
		if need > avail and need > 0 then
			h = math.max(30, math.floor(h * avail / need))
			w = math.floor(h * BUTTON_ASPECT)
		end
	end
	Categories.Size = UDim2.new(1, 0, 0, h)
	Categories.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
	for _, button in ipairs(Categories:GetChildren()) do
		if button:IsA("Frame") then
			local bw = w
			if button.Name == "Done" or button.Name == "Sell" or button.Name == "Grid" then bw = h end -- the icon buttons are squares
			button.Size = UDim2.fromOffset(bw, h)
		end
	end
	-- the Placing strip: hint line over Rotate + Cancel
	local hintH = math.clamp(math.floor(h * 0.45), 18, 30)
	Placing.Size = UDim2.new(1, 0, 0, h + hintH + 8)
	Placing.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
	PlacingHint.Size = UDim2.new(0.8, 0, 0, hintH)
	PlacingButtons.Size = UDim2.new(1, 0, 0, h)
	RotateButton.Size = UDim2.fromOffset(w, h)
	StripGrid.Size = UDim2.fromOffset(h, h)
	StripCollisions.Size = UDim2.fromOffset(math.floor(h * 2.5), h)
	CancelButton.Size = UDim2.fromOffset(w, h)
	-- the catalog: a bare strip of cards (no panel, no bar) CATALOG_GAP px above the Categories row (2026-09-12)
	Bar.Visible = false
	Catalog.BackgroundTransparency = 1
	local fill = Catalog:FindFirstChild("Fill")
	if fill then fill.Visible = false end
	local outline = Catalog:FindFirstChild("Outline")
	if outline then outline.Enabled = false end
	layout.CardH = math.clamp(math.floor(size.Y * 0.2), 96, 150)
	layout.CardW = math.floor(layout.CardH * 0.8)
	local n = currentCategory and cards[currentCategory] and #cards[currentCategory] or 0
	local cwMax = math.clamp(math.floor(size.X * 0.62), 320, 980)
	local want = n * layout.CardW + math.max(0, n - 1) * 8 + 16 -- cards + list padding + row padding
	local cw = n > 0 and math.min(cwMax, want) or cwMax
	local ch = layout.CardH + 18 -- row padding + the scroll bar's inset
	Catalog.AnchorPoint = Vector2.new(0.5, 1)
	Catalog.Size = UDim2.fromOffset(cw, ch)
	layout.CatalogY = -(BOTTOM + h + CATALOG_GAP)
	Catalog.Position = UDim2.new(0.5, 0, 1, layout.CatalogY)
	Row.Position = UDim2.fromOffset(0, 0)
	Row.Size = UDim2.new(1, 0, 1, 0)
	for _, list in pairs(cards) do
		for _, card in ipairs(list) do card.Size = UDim2.fromOffset(layout.CardW, layout.CardH) end
	end
end

--..Category buttons..--
local function MakeCategoryButton(name, look, order, iconName, onClick)
	local button = Templates.CategoryButton:Clone()
	button.Visible = true -- the template itself stays hidden
	button.Name = name
	button.LayoutOrder = order
	button.Label.Text = look.Label or BuildCatalog.SplitCamel(name)
	Paint(button, look)
	local icon = iconName and (Icons:FindFirstChild(iconName) or Icons:FindFirstChild("Box")) or nil
	if icon then
		local glyph = icon:Clone()
		glyph.Name = "Glyph"
		glyph.Visible = true
		glyph.Parent = button.Icon
	else
		-- no glyph: the label takes the whole face
		button.Icon.Visible = false
		button.Label.Position = UDim2.fromScale(0.06, 0.15)
		button.Label.Size = UDim2.fromScale(0.88, 0.7)
		button.Label.TextXAlignment = Enum.TextXAlignment.Center
	end
	button.Press.Activated:Connect(function()
		ButtonFX.Sound(ButtonFX.PRESS_SOUND)
		onClick()
	end)
	Hover(button.Press, button, 1.04)
	button.Parent = Categories
	return button
end

local function BuildCategoryButtons()
	for _, child in ipairs(Categories:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local order, seen = 0, {}
	local function add(name, look, icon, onClick)
		order += 1
		seen[name] = true
		return MakeCategoryButton(name, look, order, icon, onClick)
	end
	for _, info in ipairs(BuildCatalog.CATEGORIES) do
		local sub = TemplatesFolder:FindFirstChild(info.Name)
		if sub and #sub:GetChildren() > 0 then
			add(info.Name, info, info.Name, function() OpenCategory(info.Name) end)
		end
	end
	for _, sub in ipairs(TemplatesFolder:GetChildren()) do
		if sub:IsA("Folder") and not seen[sub.Name] and #sub:GetChildren() > 0 then
			local name = sub.Name
			add(name, BuildCatalog.NEUTRAL, "Box", function() OpenCategory(name) end)
		end
	end
	-- the close button: a square with just the red X label
	local close = add("Done", BuildCatalog.CLOSE, "Done", function() Exit() end)
	close.Label.Visible = false
	close.Icon.Position = UDim2.fromScale(0.15, 0.15)
	close.Icon.Size = UDim2.fromScale(0.7, 0.7)
	-- Sell (toggle) and Grid (cycle) beside it: squares with just an icon (+ the grid size in the corner)
	local function square(button)
		button.Label.Visible = false
		button.Icon.Position = UDim2.fromScale(0.15, 0.15)
		button.Icon.Size = UDim2.fromScale(0.7, 0.7)
	end
	sellButton = add("Sell", BuildCatalog.SELL_OFF, "Sell", function() SetSelling(not selling) end)
	square(sellButton)
	gridButton = add("Grid", BuildCatalog.GRID, "Grid", CycleGrid)
	square(gridButton)
	gridButton.Corner.Visible = true
	UpdateGridButtons()
	SetSelling(selling)
end

--..Cards..--
local function FitViewport(view, model)
	local _, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	local distance = radius / math.tan(math.rad(VIEW_FOV * 0.5)) * 1.06
	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEW_FOV
	camera.CFrame = CFrame.lookAt(VIEW_DIRECTION * distance, Vector3.zero)
	camera.Parent = view
	view.CurrentCamera = camera
end

--.. defence limits (2026-09-19): BuildService publishes BuildCount_<Key> / BuildLimit_<Key> on the
--.. player; limit is nil for an uncapped build (or before the server has published it)
local function CountsOf(key)
	return tonumber(player:GetAttribute(BuildCatalog.COUNT_ATTR .. key)) or 0, tonumber(player:GetAttribute(BuildCatalog.LIMIT_ATTR .. key))
end

local function CountText(key)
	local have, limit = CountsOf(key)
	return limit and ("[%d/%d]"):format(have, limit) or ""
end

--.. strength unlocks (2026-09-23 economy): BuildService stamps Unlock = BuildCatalog.UnlockOf(key) on the
--.. template. A card whose Unlock is above player.Data.Strength is dimmed by a dark "LockShade" overlay
--.. carrying a white "🔒 💪3K" label (the [X/Y] style) and refuses the pick (the server refuses too).
--.. SetLocked re-reads the strength; RefreshLocks runs it on every Strength change and category open.
local function UnlockOf(template)
	return tonumber(template:GetAttribute("Unlock")) or BuildCatalog.UnlockOf(template:GetAttribute("Key") or template.Name)
end

local function LockText(unlock)
	return "🔒 💪" .. NumberAbbrev.Abbrev(unlock)
end

local function SetLocked(card, template)
	local shade = card:FindFirstChild("LockShade")
	if not shade then return end
	local unlock = UnlockOf(template)
	shade.Visible = Strength() < unlock
	local label = shade:FindFirstChild("Lock")
	if label then label.Text = LockText(unlock) end
end

local function MakeCard(template, look, order)
	local card = Templates.BuildCard:Clone()
	card.Visible = true
	card.Name = template.Name
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(layout.CardW, layout.CardH)
	card.Title.Text = tostring(template:GetAttribute("DisplayName") or template.Name)
	--.. 2026-09-19 (user): "$1,200" in the HUD cash green instead of the cash icon + gold number
	card.CostRow.CostLabel.Text = "$" .. BuildCatalog.FormatCost(template:GetAttribute("Cost") or 0)
	card.CostRow.CostLabel.TextColor3 = CASH_GREEN
	local cashIcon = card.CostRow:FindFirstChild("CashIcon")
	if cashIcon then cashIcon:Destroy() end
	--.. a defence shows a white "[placed/allowed]" above its preview; the preview gives up the room
	local key = template:GetAttribute("Key") or template.Name
	if BuildCatalog.IsLimited(key) then
		card.View.Position = UDim2.fromScale(0.05, 0.16)
		card.View.Size = UDim2.fromScale(0.9, 0.46)
		local count = card.Title:Clone() -- the title's font, outline and scaling
		count.Name = "Count"
		count.Position = UDim2.fromScale(0.05, 0.03)
		count.Size = UDim2.fromScale(0.9, 0.12)
		count.TextColor3 = Color3.new(1, 1, 1)
		local cap = count:FindFirstChildOfClass("UITextSizeConstraint")
		if cap then cap.MaxTextSize = 16 end
		count.Text = CountText(key)
		count.Parent = card
	end
	--.. a build with a strength unlock: a dark overlay across the whole card (preview, title, price) + the lock label
	local unlock = UnlockOf(template)
	if unlock > 0 then
		local shade = Instance.new("Frame")
		shade.Name = "LockShade"
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.55 -- ~45 % darker
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 20 -- over the View (6), CostRow (8) and Title (10); under Press (30) so the click still lands
		shade.Visible = false
		local corners = card.Corners:Clone()
		corners.Parent = shade
		local lock = card.Title:Clone() -- the title's font, outline and scaling, like the Count label
		lock.Name = "Lock"
		lock.Position = UDim2.fromScale(0.05, 0.3)
		lock.Size = UDim2.fromScale(0.9, 0.2)
		lock.TextColor3 = Color3.new(1, 1, 1)
		lock.Text = LockText(unlock)
		lock.Parent = shade
		shade.Parent = card
		SetLocked(card, template)
	end
	card.Fill.InnerHighlight.Outline.Color = look.Highlight:Lerp(Color3.fromRGB(96, 96, 116), 0.55)
	local model = template:Clone()
	local hitbox = model:FindFirstChild("Hitbox")
	if hitbox then hitbox:Destroy() end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sound") or d:IsA("Beam") then d:Destroy() end
	end
	local cf = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(CFrame.identity) -- centred on the origin; the camera looks at the origin
	model.Parent = card.View
	FitViewport(card.View, model)
	cardTemplates[card] = template
	card.Press.Activated:Connect(function() Pick(template, card) end)
	Hover(card.Press, card, 1.03)
	card.Parent = Row
	return card
end

--.. every defence card's "[X/Y]" from the published attributes (cards live for the whole session)
local function RefreshCounts()
	for card, template in pairs(cardTemplates) do
		local label = card:FindFirstChild("Count")
		if label then label.Text = CountText(template:GetAttribute("Key") or template.Name) end
	end
end
player.AttributeChanged:Connect(function(name)
	if name:sub(1, #BuildCatalog.COUNT_ATTR) == BuildCatalog.COUNT_ATTR or name:sub(1, #BuildCatalog.LIMIT_ATTR) == BuildCatalog.LIMIT_ATTR then
		RefreshCounts()
	end
end)

--.. every card's lock from player.Data.Strength: on every Strength change and whenever a category opens
local function RefreshLocks()
	for card, template in pairs(cardTemplates) do SetLocked(card, template) end
end
task.spawn(function()
	local data = player:WaitForChild("Data", 60)
	local value = data and data:WaitForChild("Strength", 60)
	if not value then
		warn("[BuildMenuClient] player.Data.Strength never arrived; the strength locks stay as first drawn")
		return
	end
	value.Changed:Connect(RefreshLocks)
	RefreshLocks()
end)

--..Placement (the egg PlacementClient's rules, plus the plot's fixtures in the overlap test, floors, and moves)..--
local function Snap(v)
	local g = GridSize()
	if g <= 0 then return v end
	return math.round(v / g) * g
end

local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

local function ClampIn(v, half)
	if half <= 0 then return 0 end
	return math.clamp(v, -half, half)
end

local function AtBase(plot)
	local root = Root()
	if not root then return false end
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	return math.abs(rp.X) <= plot.Size.X * 0.5 + AT_BASE_MARGIN
		and math.abs(rp.Z) <= plot.Size.Z * 0.5 + AT_BASE_MARGIN
		and rp.Y > -10 and rp.Y < 60
end

local function FixturesOf(plot)
	local fixtures = Lobby:FindFirstChild("PlotFixtures")
	return fixtures and fixtures:FindFirstChild(plot.Name) or nil
end

--.. the ghost's parts go red while it cannot be placed (plus the Highlight), back to their colours when it can
--.. the grass tile of a ground-floor cell, and hiding it (locally) while the flooring ghost hovers there:
--.. the ghost's top sits exactly where the grass top is, so without this the two z-fight; the server hides
--.. it for real once the tile is placed (RefreshGrass) and it comes back as soon as the ghost moves on
local function GrassTileAt(plot, x, z)
	local folder = plot:FindFirstChild("GrassTiles")
	if not folder then return nil end
	for _, tile in ipairs(folder:GetChildren()) do
		if math.abs((tile:GetAttribute("CellX") or 1e9) - x) < 0.1 and math.abs((tile:GetAttribute("CellZ") or 1e9) - z) < 0.1 then return tile end
	end
	return nil
end
--.. the tile's Texture (the plot's checker) renders whatever the part's transparency, so it is hidden with it;
--.. on the way back it only returns when the server still shows the tile (a placed floor keeps it hidden)
local function SetGrassHidden(tile, hidden)
	tile.LocalTransparencyModifier = hidden and 1 or 0
	local texture = tile:FindFirstChildOfClass("Texture")
	if texture then
		if hidden then
			texture.Transparency = 1
		elseif tile.Transparency < 1 then
			local plot = tile.Parent and tile.Parent.Parent
			local base = plot and plot:FindFirstChildOfClass("Texture")
			texture.Transparency = base and base.Transparency or 0.8
		end
	end
end
local function HoverGrass(state, tile)
	if state.HoverGrass == tile then return end
	if state.HoverGrass and state.HoverGrass.Parent then SetGrassHidden(state.HoverGrass, false) end
	state.HoverGrass = tile
	if tile then SetGrassHidden(tile, true) end
end

local function SetGhostValid(state, valid)
	state.Valid = valid
	state.Highlight.Enabled = not valid
	if state.Tinted == (not valid) then return end
	state.Tinted = not valid
	for part, color in pairs(state.Colors) do
		if part.Parent then part.Color = valid and color or INVALID_COLOR end
	end
end

--.. a placed cucumber on the mouse (StartMovingCucumber): the plot surface only, its RestSize footprint on the
--.. current grid in its rest pose; red (parts + Highlight) while it hangs outside the plot or its box overlaps
--.. anything else in Placed - the same test CucumberMoveServer / CucumberCarry.Place run
local function UpdateCucumberPreview(state)
	local plot, model = state.Plot, state.Cucumber
	if not plot.Parent or not model.Parent or model:GetAttribute("StolenBy") then StopPlacing() return end
	local root = Root()
	if not root or not AtBase(plot) then
		if state.Preview.Parent then state.Preview.Parent = nil end
		state.Valid = false
		return
	elseif not state.Preview.Parent then
		state.Preview.Parent = workspace
	end
	local top = plot.Size.Y * 0.5
	local lp
	if targetOverride then
		lp = Vector3.new(targetOverride.X, top, targetOverride.Y)
	else
		local ray = mouse.UnitRay
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {plot}
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if hit and hit.Instance ~= plot then hit = nil end -- the Include filter takes the plot's descendants too
		if hit then
			lp = plot.CFrame:PointToObjectSpace(hit.Position)
		else
			local o = plot.CFrame:PointToObjectSpace(ray.Origin)
			local d = plot.CFrame:VectorToObjectSpace(ray.Direction)
			local t = math.abs(d.Y) > 1e-4 and (top - o.Y) / d.Y or -1
			lp = (t > 0 and t < 2000) and (o + d * t) or Vector3.new(0, top, 0)
		end
	end
	local size = state.Size
	local box = CucumberFootprint.Box(size) -- the footprint CucumberMoveServer tests (smaller than the canopy for wide ones)
	local yaw = math.rad(state.Yaw)
	local fx, fz = Footprint(box, yaw)
	local tooBig = fx > plot.Size.X or fz > plot.Size.Z
	local x = ClampIn(Snap(lp.X), math.max(0, plot.Size.X * 0.5 - fx * 0.5))
	local z = ClampIn(Snap(lp.Z), math.max(0, plot.Size.Z * 0.5 - fz * 0.5))
	local boxCF = plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
	state.TargetCF = boxCF
	state.Preview:PivotTo(plot.CFrame * CFrame.new(x, top + state.Lift, z) * CFrame.Angles(0, yaw, 0) * state.RestRotation)
	local holder = plot:FindFirstChild("Placed")
	local occupied = false
	if holder then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {holder}
		for _, part in ipairs(workspace:GetPartBoundsInBox(boxCF, box, overlap)) do
			if not part:IsDescendantOf(model) then occupied = true break end
		end
	end
	local hint = state.Hint
	if tooBig then hint = "Too big for your plot at this angle" elseif occupied then hint = "Something is already standing there" end
	if PlacingHint.Text ~= hint then PlacingHint.Text = hint end
	SetGhostValid(state, not occupied and not tooBig)
end

--.. RANGE DISC (2026-09-23, user: "show defense range when defense is selected in build mode (like a big circle
--.. around it)"): a flat disc of the defence's reach (the template's Range attribute, published by DefenceService
--.. from its own numbers) with a rim of short Neon segments, plus a red inner disc + rim for a MinRange (the
--.. catapult / mortar dead zone). Its own model in workspace, NOT a child of the ghost: the ghost's red
--.. OccupiedHighlight would paint it too. Never collides / answers rays, so it cannot block the mouse or a placement.
local function RangePart(model, name, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Color = color
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function RangeFill(model, radius, color, transparency, lift)
	local disc = RangePart(model, "Fill", color, transparency)
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.SmoothPlastic
	disc.Size = Vector3.new(0.08, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, math.rad(90)) -- the cylinder's axis (X) stood up
	return disc
end

local function RangeRim(model, radius, color, transparency, lift)
	local n = math.clamp(math.floor(radius * 1.4), 36, 96)
	local step = math.pi * 2 / n
	local length = radius * step * 1.06 -- a little overlap closes the polygon
	for i = 1, n do
		local a = (i - 1) * step
		local seg = RangePart(model, "Rim", color, transparency)
		seg.Material = Enum.Material.Neon
		seg.Size = Vector3.new(length, 0.1, RANGE_RIM_WIDTH)
		local centre = Vector3.new(math.cos(a) * radius, lift, math.sin(a) * radius)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		seg.CFrame = CFrame.fromMatrix(centre, tangent, Vector3.yAxis) -- the segment's length runs along the circle
	end
end

local function MakeRangeDisc(range, minRange)
	local model = Instance.new("Model")
	model.Name = "RangeDisc"
	model:SetAttribute("Range", range)
	model:SetAttribute("MinRange", minRange)
	local fill = RangeFill(model, range, RANGE_COLOR, RANGE_FILL_TRANSPARENCY, 0)
	RangeRim(model, range, RANGE_RIM_COLOR, RANGE_RIM_TRANSPARENCY, 0.06)
	if minRange > 0 and minRange < range then
		RangeFill(model, minRange, RANGE_DEAD_COLOR, RANGE_DEAD_TRANSPARENCY, 0.03)
		RangeRim(model, minRange, RANGE_DEAD_COLOR, RANGE_RIM_TRANSPARENCY, 0.09)
	end
	--.. a Model with a PrimaryPart IGNORES WorldPivot: its pivot is the primary part's, and the fill is a cylinder stood
	--.. up by 90 deg about Z. Undo that on the fill's PivotOffset, so the disc's pivot is upright at its centre and
	--.. PivotTo lays the whole disc flat (the first cut skipped this and the ring stood vertical, 2026-09-23).
	fill.PivotOffset = CFrame.Angles(0, 0, math.rad(-90))
	model.PrimaryPart = fill -- parts were built about the origin; PivotTo moves the whole disc
	return model
end

--.. put the disc at cf (its centre on the ghost's floor), or hide it (nil) with the ghost
local function ShowRangeDisc(state, cf)
	local disc = state.RangeDisc
	if not disc then return end
	if cf then
		disc:PivotTo(cf)
		if disc.Parent ~= workspace then disc.Parent = workspace end
	elseif disc.Parent then
		disc.Parent = nil
	end
end

local function UpdatePreview()
	local state = placing
	if not state then return end
	if state.Cucumber then return UpdateCucumberPreview(state) end
	local plot, hitbox = state.Plot, state.Hitbox
	if not plot.Parent or (state.Moving and not state.Moving.Parent) then StopPlacing() return end
	--.. only while standing at the base; elsewhere the ghost is hidden and nothing can be placed
	local root = Root()
	if not root or not AtBase(plot) then
		if state.Preview.Parent then state.Preview.Parent = nil end
		ShowRangeDisc(state, nil)
		HoverGrass(state, nil)
		state.Valid = false
		return
	elseif not state.Preview.Parent then
		state.Preview.Parent = workspace
	end
	--.. which floor: the one the player stands on; a tile's TOP and a build's BOTTOM both sit at its surface
	local isFloor = state.IsFloor
	local level = BuildCatalog.PlayerLevel(plot, root.Position)
	local surface = BuildCatalog.SurfaceY(plot, level) -- plot space
	--.. aim, in the plot's own space: the mouse ray on the plot slab (ground floor) or on the upper floor's
	--.. plane, else the plot's plane at that level (or the dev override)
	local lp
	if targetOverride then
		lp = Vector3.new(targetOverride.X, surface, targetOverride.Y)
	else
		local ray = mouse.UnitRay
		local hit
		if level == 1 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = {plot}
			hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
			if hit and hit.Instance ~= plot then hit = nil end -- the Include filter takes the plot's descendants too
		end
		if hit then
			lp = plot.CFrame:PointToObjectSpace(hit.Position)
		else
			local o = plot.CFrame:PointToObjectSpace(ray.Origin)
			local d = plot.CFrame:VectorToObjectSpace(ray.Direction)
			local t = math.abs(d.Y) > 1e-4 and (surface - o.Y) / d.Y or -1
			lp = (t > 0 and t < 2000) and (o + d * t) or Vector3.new(0, surface, 0)
		end
	end
	--.. snap + clamp inside the plot; a tile fills one grass cell (square), a staircase lands its landing
	--.. edge on a cell boundary, anything else follows the current grid
	local yaw = isFloor and 0 or math.rad(state.Yaw)
	local x, z
	local inside = true
	if isFloor then
		local w, d
		x, z, w, d = BuildCatalog.SnapCell(plot, lp.X, lp.Z)
		BuildCatalog.FitTile(state.Preview, w, d) -- an edge strip is narrower than a full cell
		HoverGrass(state, level == 1 and GrassTileAt(plot, x, z) or nil) -- the ghost stands in for the grass tile
	end
	local size = hitbox.Size
	local fx, fz = Footprint(size, yaw)
	if isFloor then
		-- snapped above
	elseif state.IsStairs then
		x, z = BuildCatalog.SnapStairs(plot, lp.X, lp.Z, yaw, size)
		inside = math.abs(x) + fx * 0.5 <= plot.Size.X * 0.5 + BOUNDS_EPSILON and math.abs(z) + fz * 0.5 <= plot.Size.Z * 0.5 + BOUNDS_EPSILON
	else
		x = ClampIn(Snap(lp.X), plot.Size.X * 0.5 - fx * 0.5)
		z = ClampIn(Snap(lp.Z), plot.Size.Z * 0.5 - fz * 0.5)
	end
	local centreY = isFloor and (surface - size.Y * 0.5) or (surface + size.Y * 0.5)
	local targetCF = plot.CFrame * CFrame.new(x, centreY, z) * CFrame.Angles(0, yaw, 0)
	state.TargetCF = targetCF
	state.Preview:PivotTo(targetCF)
	ShowRangeDisc(state, plot.CFrame * CFrame.new(x, surface + RANGE_LIFT, z)) -- flat on the ghost's floor, centred under it
	--.. occupied? (same test the server runs: tiles and builds pass each other on the ground, a moved
	--.. build ignores itself)
	local holder = plot:FindFirstChild("Placed")
	local filter = {}
	if holder then table.insert(filter, holder) end
	local fixtures = FixturesOf(plot)
	if fixtures then table.insert(filter, fixtures) end
	local occupied = false
	if #filter > 0 then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = filter
		for _, part in ipairs(workspace:GetPartBoundsInBox(targetCF, size * COLLISION_SHRINK, overlap)) do
			if not (state.Moving and part:IsDescendantOf(state.Moving)) and BuildCatalog.Blocks(part, holder, isFloor, level, collisions) then
				occupied = true
				break
			end
		end
	end
	--.. upstairs: a build needs flooring under it, a tile must join the floor, a staircase never goes there
	local hint = state.Hint
	local upstairsOk = true
	if level >= 2 then
		if state.IsStairs then
			upstairsOk = false
			hint = STAIRS_HINT
		elseif isFloor then
			local anchored, anyTile = BuildCatalog.FloorAnchored(holder, targetCF, size, level, state.Moving)
			if not anchored then
				upstairsOk = false
				hint = anyTile and NEXT_TILE_HINT or FIRST_TILE_HINT
			end
		elseif not BuildCatalog.Supported(holder, targetCF, size, state.Moving) then
			upstairsOk = false
			hint = SUPPORT_HINT
		end
	end
	if not inside then hint = "Keep it inside your plot" end
	if PlacingHint.Text ~= hint then PlacingHint.Text = hint end
	SetGhostValid(state, inside and not occupied and upstairsOk)
end

local function TryPlace()
	local state = placing
	if not state or not state.Valid or not state.TargetCF or not state.Preview.Parent then return end
	if state.Cucumber then
		local ok, reason = requestCucumberMove:InvokeServer(state.Cucumber, state.TargetCF)
		if placing ~= state then return end
		if ok then
			ButtonFX.Sound(ButtonFX.PRESS_SOUND)
			StopPlacing() -- the cucumber itself now stands where the ghost was
		else
			ButtonFX.Sound(ButtonFX.FAIL_SOUND)
			Notify.Error(tostring(reason or "Can't move it there"))
		end
		return
	end
	if state.Moving then
		local ok, reason = requestBuildMove:InvokeServer(state.Moving, state.TargetCF, {Collisions = collisions})
		if placing ~= state then return end
		if ok then
			ButtonFX.Sound(ButtonFX.PRESS_SOUND)
			StopPlacing() -- the build itself now stands where the ghost was
		else
			ButtonFX.Sound(ButtonFX.FAIL_SOUND)
			Notify.Error(tostring(reason or "Can't move it there"))
		end
		return
	end
	local template = state.Template
	local ok, reason, limit = requestBuildPlacement:InvokeServer(template:GetAttribute("Key"), state.TargetCF, {Collisions = collisions})
	if placing ~= state then return end
	if ok then
		for _, entry in ipairs(ButtonFX.SUCCESS_SOUNDS) do ButtonFX.Sound(entry) end
		SetGhostValid(state, false) -- the spot is taken now; the next Update() re-aims
		--.. a capped defence answers (true, placed, limit): that was the last one allowed -> off the mouse
		if tonumber(limit) and tonumber(reason) and tonumber(reason) >= tonumber(limit) then StopPlacing() end
	else
		ButtonFX.Sound(ButtonFX.FAIL_SOUND)
		Notify.Error(tostring(reason or "Can't place that here"))
		SetGhostValid(state, false)
	end
end

local function Rotate()
	if placing then placing.Yaw = (placing.Yaw + ROTATION_STEP) % 360 end
end

--.. the panel that was showing before a build went on the mouse
local function RestorePanels()
	Placing.Visible = false
	if mode == "catalog" then
		Catalog.Visible = true
		Categories.Visible = true -- the row lives under the strip: both come back after a cancel (fix 2026-09-12)
	elseif mode == "categories" then
		Categories.Visible = true
	end
end

function StopPlacing()
	local state = placing
	if not state then return end
	placing = nil
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	if state.Preview then state.Preview:Destroy() end
	if state.RangeDisc then state.RangeDisc:Destroy() end
	if state.Card and state.Card.Parent then
		state.Card.Outline.Color = DARK
		state.Card.Outline.Thickness = 2
	end
	for _, part in ipairs(state.Hidden or {}) do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	HoverGrass(state, nil)
	RestorePanels()
	Fit()
end

local function StartPlacing(template, card, moving)
	StopPlacing()
	local plot = MyPlot()
	if not plot then Notify.Error("You have no plot") return end
	if not template.PrimaryPart then return end
	local preview = template:Clone()
	preview.Name = template.Name .. " Preview"
	local colors = {}
	for _, d in ipairs(preview:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name ~= "Hitbox" then
				d.Transparency = math.max(d.Transparency, PREVIEW_TRANSPARENCY)
				colors[d] = d.Color
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d.Enabled = false
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "OccupiedHighlight"
	highlight.FillColor = INVALID_COLOR
	highlight.OutlineColor = INVALID_COLOR
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = preview
	-- not parented yet: UpdatePreview() shows it only while the player is at the base
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	--.. a defence's reach (RangeDisc): the template's Range / MinRange attributes, published by DefenceService
	local range = tonumber(template:GetAttribute("Range")) or 0
	local minRange = tonumber(template:GetAttribute("MinRange")) or 0
	local hidden = {}
	if moving then
		for _, d in ipairs(moving:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0.85 -- the original stays as a faint ghost while it is on the mouse
				table.insert(hidden, d)
			end
		end
	end
	local state = {
		Template = template, Card = card, Moving = moving, Plot = plot, Preview = preview, Hitbox = preview.PrimaryPart, Highlight = highlight,
		Yaw = moving and (tonumber(moving:GetAttribute("Yaw")) or 0) or 0, TargetCF = nil, Valid = false, Connections = {},
		IsFloor = template:GetAttribute("IsFloor") == true, IsStairs = template:GetAttribute("IsStairs") == true,
		Colors = colors, Tinted = false, Hidden = hidden,
		RangeDisc = range > 0 and MakeRangeDisc(range, minRange) or nil, -- not parented yet: it shows with the ghost
		Hint = moving and (touchOnly and "Tap where it goes" or "Click to drop it  |  R rotates  |  Cancel puts it back")
			or (touchOnly and "Tap your base to place" or "Click to place  |  R rotates  |  Cancel drops it"),
	}
	placing = state
	if card then
		local info = BuildCatalog.CategoryInfo(template:GetAttribute("Category")) or BuildCatalog.NEUTRAL
		card.Outline.Color = info.Highlight
		card.Outline.Thickness = 3
	end
	--.. only the Placing strip stays while a build is on the mouse
	Catalog.Visible = false
	Categories.Visible = false
	Placing.Visible = true
	PlacingHint.Text = state.Hint
	Fit()
	Pop(Placing, 0.8, 0.24)
	--.. Heartbeat (not RenderStepped) so the ghost keeps tracking while the window is unfocused
	table.insert(state.Connections, RunService.Heartbeat:Connect(UpdatePreview))
	table.insert(state.Connections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or placing ~= state then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TryPlace()
		end
	end))
	-- R only: right-click is the camera orbit and there is no Escape keybind
	table.insert(state.Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or placing ~= state then return end
		if input.KeyCode == Enum.KeyCode.R then Rotate() end
	end))
	UpdatePreview()
end

function Pick(template, card)
	if mode ~= "catalog" then return end
	if placing and placing.Template == template and not placing.Moving then return end -- already on the mouse
	--.. strength unlocks (2026-09-23 economy): locked -> refuse before it goes on the mouse (the server checks too)
	local unlock = UnlockOf(template)
	if Strength() < unlock then
		ButtonFX.Sound(ButtonFX.FAIL_SOUND)
		ButtonFX.Flash(card, Color3.fromRGB(255, 70, 70), 0.55, 0.35)
		Notify.Error(("Needs 💪%s strength"):format(NumberAbbrev.Abbrev(unlock)))
		SetLocked(card, template)
		return
	end
	--.. defence limits (2026-09-19): full up -> refuse before it goes on the mouse (the server checks too)
	local have, limit = CountsOf(template:GetAttribute("Key") or template.Name)
	if limit and have >= limit then
		ButtonFX.Sound(ButtonFX.FAIL_SOUND)
		ButtonFX.Flash(card, Color3.fromRGB(255, 70, 70), 0.55, 0.35)
		Notify.Error(("%s limit reached [%d/%d]"):format(tostring(template:GetAttribute("DisplayName") or template.Name), have, limit))
		return
	end
	local cost = tonumber(template:GetAttribute("Cost")) or 0
	local cash = Cash()
	if cash < cost then
		ButtonFX.Sound(ButtonFX.FAIL_SOUND)
		ButtonFX.Flash(card, Color3.fromRGB(255, 70, 70), 0.55, 0.35)
		Notify.Error(("Need $%s more"):format(BuildCatalog.FormatCost(cost - cash)))
		return
	end
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	Pop(card, 0.9, 0.2)
	StartPlacing(template, card, nil)
end

--..Moving and selling placed builds..--
local hoverHighlight = Instance.new("Highlight")
hoverHighlight.Name = "BuildHover"
hoverHighlight.FillColor = Color3.new(1, 1, 1)
hoverHighlight.FillTransparency = 0.75
hoverHighlight.OutlineColor = Color3.new(1, 1, 1)
hoverHighlight.OutlineTransparency = 0.15
hoverHighlight.DepthMode = Enum.HighlightDepthMode.Occluded

--.. the player's own placed build under the mouse, or nil
local function BuildUnderMouse()
	local plot = MyPlot()
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return nil end
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	local inst = hit and hit.Instance
	while inst and inst.Parent ~= holder do inst = inst.Parent end
	if inst and inst:IsA("Model") and CollectionService:HasTag(inst, BuildCatalog.PLACED_TAG) and inst:GetAttribute("Owner") == player.UserId then
		return inst
	end
	return nil
end

local function SetHover(model)
	if hoverHighlight.Parent == model then return end
	hoverHighlight.Parent = model
end

function StartMoving(model)
	local key = model and model:GetAttribute("BuildKey")
	local template = key and BuildCatalog.Find(key)
	if not template then Notify.Error("Can't move that") return end
	SetHover(nil)
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	StartPlacing(template, nil, model)
end

--.. the player's own placed CUCUMBER under the mouse (only its PlotHitbox answers rays), or nil
local function CucumberUnderMouse()
	local plot = MyPlot()
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return nil end
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	local inst = hit and hit.Instance
	while inst and inst.Parent ~= holder do inst = inst.Parent end
	if inst and inst:IsA("Model") and CollectionService:HasTag(inst, CUCUMBER_TAG) and inst:GetAttribute("Owner") == player.UserId and not inst:GetAttribute("StolenBy") then
		return inst
	end
	return nil
end

function StartMovingCucumber(model)
	local size = model and model:GetAttribute("RestSize")
	local restRot = model and model:GetAttribute("RestRotation")
	if not requestCucumberMove or typeof(size) ~= "Vector3" or typeof(restRot) ~= "CFrame" then Notify.Error("Can't move that") return end
	StopPlacing()
	local plot = MyPlot()
	if not plot then Notify.Error("You have no plot") return end
	SetHover(nil)
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	local lift = tonumber(model:GetAttribute("RestLift")) or size.Y * 0.5
	--.. its current yaw on the plot: the pivot is plot x offset x yaw x rest pose
	local relative = plot.CFrame:ToObjectSpace(model:GetPivot()) * restRot:Inverse()
	local _, yaw = relative:ToEulerAnglesYXZ()
	local preview = model:Clone()
	preview.Name = model.Name .. " Preview"
	local colors = {}
	for _, d in ipairs(preview:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("IKControl") or d:IsA("Attachment") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Highlight") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name ~= "PlotHitbox" then
				d.Transparency = math.max(d.Transparency, PREVIEW_TRANSPARENCY)
				colors[d] = d.Color
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d.Enabled = false
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "OccupiedHighlight"
	highlight.FillColor = INVALID_COLOR
	highlight.OutlineColor = INVALID_COLOR
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = preview
	local hidden = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "PlotHitbox" then
			d.LocalTransparencyModifier = 0.85 -- the original stays as a faint ghost while it is on the mouse
			table.insert(hidden, d)
		end
	end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local state = {
		Cucumber = model, Plot = plot, Preview = preview, Size = size, Lift = lift, RestRotation = restRot, Highlight = highlight,
		Yaw = math.round(math.deg(yaw) / ROTATION_STEP) * ROTATION_STEP % 360, TargetCF = nil, Valid = false, Connections = {},
		Colors = colors, Tinted = false, Hidden = hidden,
		Hint = touchOnly and "Tap where it goes" or "Click to drop it  |  R rotates  |  Cancel puts it back",
	}
	placing = state
	Catalog.Visible = false
	Categories.Visible = false
	Placing.Visible = true
	PlacingHint.Text = state.Hint
	Fit()
	Pop(Placing, 0.8, 0.24)
	table.insert(state.Connections, RunService.Heartbeat:Connect(UpdatePreview))
	table.insert(state.Connections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or placing ~= state then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TryPlace()
		end
	end))
	table.insert(state.Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or placing ~= state then return end
		if input.KeyCode == Enum.KeyCode.R then Rotate() end
	end))
	UpdatePreview()
end

local function SellBuild(model)
	local ok, a, b = requestBuildSell:InvokeServer(model)
	if ok then
		for _, entry in ipairs(ButtonFX.SUCCESS_SOUNDS) do ButtonFX.Sound(entry) end
		Notify.Success(("Sold %s for $%s"):format(tostring(b or "it"), BuildCatalog.FormatCost(a or 0)))
	else
		ButtonFX.Sound(ButtonFX.FAIL_SOUND)
		Notify.Error(tostring(a or "Can't sell that"))
	end
end

function SetSelling(on)
	selling = on == true
	if selling then StopPlacing() end
	if sellButton and sellButton.Parent then
		Paint(sellButton, selling and BuildCatalog.SELL_ON or BuildCatalog.SELL_OFF)
		sellButton.Label.Text = selling and "Selling" or "Sell"
		if selling then Pop(sellButton, 0.9, 0.22) end
	end
	local red = Color3.fromRGB(255, 70, 70)
	hoverHighlight.FillColor = selling and red or Color3.new(1, 1, 1)
	hoverHighlight.OutlineColor = selling and red or Color3.new(1, 1, 1)
	hoverHighlight.FillTransparency = selling and 0.55 or 0.75
end

function SetCollisions(on)
	collisions = on == true
	StripCollisions.Box.Check.Visible = collisions
	Paint(StripCollisions, collisions and BuildCatalog.COLLIDE_ON or BuildCatalog.COLLIDE_OFF)
	Pop(StripCollisions, 0.92, 0.18)
end

RunService.Heartbeat:Connect(function()
	if mode == "off" or placing then
		SetHover(nil)
		return
	end
	SetHover(BuildUnderMouse() or CucumberUnderMouse())
end)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed or mode == "off" or placing then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local model = BuildUnderMouse()
		if model then
			if selling then SellBuild(model) else StartMoving(model) end
			return
		end
		local cucumber = CucumberUnderMouse()
		if cucumber then
			if selling then Notify.Warn("Cucumbers can't be sold here") else StartMovingCucumber(cucumber) end
		end
	end
end)

--..Modes..--
local function ShowCategories()
	mode = "categories"
	currentCategory = nil
	Catalog.Visible = false
	Placing.Visible = false
	Categories.Visible = true
	Fit()
	Pop(Categories, 0.72, 0.3)
end

function OpenCategory(name)
	if mode == "off" then return end
	if not TemplatesFolder:FindFirstChild(name) then return end
	StopPlacing()
	SetSelling(false)
	mode = "catalog"
	currentCategory = name
	local info = BuildCatalog.CategoryInfo(name)
	if not cards[name] then
		cards[name] = {}
		local look = info or BuildCatalog.NEUTRAL
		for i, template in ipairs(BuildCatalog.BuildsIn(name)) do
			table.insert(cards[name], MakeCard(template, look, i))
		end
	end
	RefreshCounts()
	RefreshLocks() -- 2026-09-23 economy: the strength locks are re-read every time the panel opens
	for category, list in pairs(cards) do
		for _, card in ipairs(list) do card.Visible = category == name end
	end
	Row.CanvasPosition = Vector2.zero
	Bar.Title.Text = info and info.Label or BuildCatalog.SplitCamel(name)
	Bar.Hint.Text = "Pick a build"
	Categories.Visible = true -- the row stays: the panel is at the top, so nothing is covered
	Placing.Visible = false
	Catalog.Visible = true
	Fit()
	Rise()
	for i, card in ipairs(cards[name]) do
		if i > 8 then break end
		task.delay(0.03 * (i - 1), function()
			if card.Visible and Catalog.Visible then Pop(card, 0.85, 0.24) end
		end)
	end
end

local function Back()
	if mode ~= "catalog" then return end
	StopPlacing()
	ShowCategories()
end

local function Enter()
	if mode ~= "off" then return end
	if workspace:GetAttribute("CyclePhase") == "Night" then Notify.Warn("You can't build at night") return end
	if hud:GetAttribute("BaseMode") ~= true then Notify.Warn("Go to your base to build") return end
	if not MyPlot() then Notify.Error("You have no plot") return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:UnequipTools() end
	hud:SetAttribute("BuildMode", true)
	SetHotbar(false)
	selling = false
	BuildCategoryButtons() -- rebuilt on every entry: a few buttons, and it follows the folder
	ShowCategories()
end

function Exit()
	if mode == "off" then return end
	StopPlacing()
	SetSelling(false)
	mode = "off"
	currentCategory = nil
	Categories.Visible = false
	Catalog.Visible = false
	Placing.Visible = false
	SetHover(nil)
	hud:SetAttribute("BuildMode", false)
	SetHotbar(true)
end

--..Hooks..--
Paint(Bar.BackButton, BuildCatalog.BACK)
Paint(RotateButton, BuildCatalog.BACK)
Paint(StripGrid, BuildCatalog.GRID)
Paint(CancelButton, BuildCatalog.DONE)
UpdateGridButtons()
SetCollisions(collisions)
Hover(Bar.BackButton.Press, Bar.BackButton, 1.05)
Hover(RotateButton.Press, RotateButton, 1.05)
Hover(StripGrid.Press, StripGrid, 1.05)
Hover(StripCollisions.Press, StripCollisions, 1.05)
Hover(CancelButton.Press, CancelButton, 1.05)
buildButton.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	Enter()
end)
Bar.BackButton.Press.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	Back()
end)
RotateButton.Press.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	Rotate()
end)
StripGrid.Press.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	CycleGrid()
end)
StripCollisions.Press.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	SetCollisions(not collisions)
end)
CancelButton.Press.Activated:Connect(function()
	ButtonFX.Sound(ButtonFX.PRESS_SOUND)
	StopPlacing()
end)
hud:GetAttributeChangedSignal("BaseMode"):Connect(function()
	if mode ~= "off" and hud:GetAttribute("BaseMode") ~= true then Exit() end
end)
workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
	if mode ~= "off" and workspace:GetAttribute("CyclePhase") == "Night" then
		Exit()
		Notify.Warn("Night! Build mode is closed until morning.", 3)
	end
end)
--.. a daytime thief got away with a cucumber (ZombieRaidService "ThiefStole"): build mode closes (user 2026-09-12)
task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ZombieRaid", 60)
	if not remote then return end
	remote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Kind == "ThiefStole" and mode ~= "off" then
			Exit()
			Notify.Warn("Build mode closed.", 2)
		end
	end)
end)
local function WatchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then humanoid.Died:Connect(Exit) end
end
player.CharacterRemoving:Connect(Exit)
player.CharacterAdded:Connect(WatchCharacter)
if player.Character then task.spawn(WatchCharacter, player.Character) end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Fit)
Fit()

--..Studio dev hook..--
local function PlacedByName(want)
	local plot = MyPlot()
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return nil end
	local children = holder:GetChildren()
	if want == "last" then
		for i = #children, 1, -1 do
			if CollectionService:HasTag(children[i], BuildCatalog.PLACED_TAG) then return children[i] end
		end
	else
		for _, m in ipairs(children) do
			if m.Name == want and CollectionService:HasTag(m, BuildCatalog.PLACED_TAG) then return m end
		end
	end
	return nil
end
gui:GetAttributeChangedSignal("BuildDev"):Connect(function()
	local cmd = gui:GetAttribute("BuildDev")
	if type(cmd) ~= "string" or cmd == "" then return end
	gui:SetAttribute("BuildDev", nil)
	if cmd == "enter" then Enter()
	elseif cmd == "exit" then Exit()
	elseif cmd == "back" then Back()
	elseif cmd == "rotate" then Rotate()
	elseif cmd == "cancel" then StopPlacing()
	elseif cmd == "sell" then SetSelling(not selling)
	elseif cmd == "grid" then CycleGrid()
	elseif cmd == "collisions" then SetCollisions(not collisions)
	elseif cmd:sub(1, 9) == "category:" then OpenCategory(cmd:sub(10))
	elseif cmd:sub(1, 5) == "pick:" then
		local key = cmd:sub(6)
		local template = BuildCatalog.Find(key)
		local card
		for _, c in ipairs(cards[currentCategory or ""] or {}) do
			if c.Name == key then card = c end
		end
		if template and card then Pick(template, card) else warn("[BuildMenuClient] dev pick: no card for " .. key .. " in " .. tostring(currentCategory)) end
	elseif cmd:sub(1, 13) == "movecucumber:" then
		local want = cmd:sub(14)
		local plot = MyPlot()
		local holder = plot and plot:FindFirstChild("Placed")
		local found
		if holder then
			local children = holder:GetChildren()
			for i = #children, 1, -1 do
				local m = children[i]
				if CollectionService:HasTag(m, CUCUMBER_TAG) and (want == "last" or m.Name == want) then found = m break end
			end
		end
		if found then StartMovingCucumber(found) else warn("[BuildMenuClient] dev movecucumber: no placed cucumber " .. want) end
	elseif cmd:sub(1, 5) == "move:" then
		local found = PlacedByName(cmd:sub(6))
		if found then StartMoving(found) else warn("[BuildMenuClient] dev move: no placed build " .. cmd:sub(6)) end
	elseif cmd:sub(1, 10) == "sellclick:" then
		local found = PlacedByName(cmd:sub(11))
		if found then SellBuild(found) else warn("[BuildMenuClient] dev sellclick: no placed build " .. cmd:sub(11)) end
	elseif cmd:sub(1, 4) == "aim:" then
		local x, z = cmd:match("^aim:(%-?[%d%.]+),(%-?[%d%.]+)$")
		aimOverride = x and Vector2.new(tonumber(x), tonumber(z)) or nil
		targetOverride = aimOverride
		UpdatePreview()
	elseif cmd:sub(1, 5) == "place" then
		local x, z = cmd:match("^place:(%-?[%d%.]+),(%-?[%d%.]+)$")
		if x then targetOverride = Vector2.new(tonumber(x), tonumber(z)) end
		UpdatePreview()
		TryPlace()
		targetOverride = aimOverride
	else
		warn("[BuildMenuClient] dev: enter / exit / back / category:<Name> / pick:<Key> / place[:x,z] / rotate / cancel / move:<Name>|last / sell / sellclick:<Name>|last / grid / collisions / aim:x,z|aim:off")
	end
end)

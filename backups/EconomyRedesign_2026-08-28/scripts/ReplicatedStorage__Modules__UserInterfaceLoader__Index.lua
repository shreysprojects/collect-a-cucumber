--=====================================================================
-- PET INDEX -- figma rebuild (2026-07-28).
-- The panel UI is authored in Studio: Frames.Index.Canvas, a 976x719
-- design-px figma canvas driven by a UIScale (same responsive contract
-- as the Pets inventory / Rebirth panels: Scale = FramesBox.X * FILL / W).
-- This module DRIVES it: builds one tile per pet in the dictionary with a
-- live Module3D viewport, filters by rarity tabs, tracks discovery from
-- the replicated PlayerData.Pets.Unlocked StringValue, and claims
-- milestone rewards (server: IndexService).
--=====================================================================

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--..Modules..--
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")
local ComponentController = ControllerLoader.GetController("ComponentController")
local Module3D = require(ReplicatedStorage.Shared.Module3D)

--..Variables..--
local Player = Players.LocalPlayer
local Module = {}

local Index -- the Frames.Index frame (captured in OnStart)
local Canvas, Grid, Tiles -- Tiles = { [petName] = tile }
local Viewports = {} -- [tile] = Model3D (viewport culling registry)
local PetDict -- Pets dictionary from the server (cached forever)
local Built = false
local PanelOpen = false
local ActiveTab = "TabAll"

--.. responsive contract (see Pets module): canvas is 976x719 figma px;
--.. panel width = 0.886 x the aspect-locked Frames box (old Index footprint)
local DESIGN_W = 976
local PANEL_FILL = 0.886

local CULL_MARGIN = 250 -- px kept rendered beyond the scroll window

--.. tab buttons (authored in Canvas.Tabs) -> rarity filter (nil = show all)
local TAB_FILTER = {
	TabAll = nil;
	TabRare = "Rare";
	TabMythical = "Mythical";
	TabOmega = "Omega";
	TabLegendary = "Legendary";
	TabSpecial = "Special";
}

local RARITY_ORDER = {Common = 1; Uncommon = 2; Rare = 3; Epic = 4; Legendary = 5; Mythical = 6; Omega = 7; Special = 8}

--.. name-bar gradients per rarity (mirrors RarityController.Classes) + a
--.. darker tone for the underline strip
local RARITY_GRADIENTS = {
	Common    = {Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 255, 198), Color3.fromRGB(150, 200, 143)};
	Uncommon  = {Color3.fromRGB(213, 255, 0),   Color3.fromRGB(0, 207, 145),   Color3.fromRGB(0, 155, 108)};
	Rare      = {Color3.fromRGB(0, 255, 255),   Color3.fromRGB(0, 145, 255),   Color3.fromRGB(0, 110, 195)};
	Epic      = {Color3.fromRGB(249, 215, 255), Color3.fromRGB(226, 0, 255),   Color3.fromRGB(168, 0, 190)};
	Legendary = {Color3.fromRGB(255, 247, 0),   Color3.fromRGB(255, 183, 0),   Color3.fromRGB(200, 140, 0)};
	Mythical  = {Color3.fromRGB(246, 139, 255), Color3.fromRGB(25, 182, 255),  Color3.fromRGB(18, 135, 190)};
	Omega     = {Color3.fromRGB(255, 234, 0),   Color3.fromRGB(255, 0, 0),     Color3.fromRGB(190, 0, 0)};
	Special   = {Color3.fromRGB(255, 219, 219), Color3.fromRGB(255, 0, 0),     Color3.fromRGB(190, 0, 0)};
}
local LOCKED_GRADIENT = {Color3.fromRGB(191, 191, 191), Color3.fromRGB(136, 136, 136), Color3.fromRGB(114, 114, 114)}

--.. ComponentController hover recolour for the claim label (same shape the
--.. old panel used; Main's close-button wiring has its own copy for the X)
Module.Gradients = {
	ClaimButton = {
		OriginalGradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255));
		HoverGradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(17, 255, 0));
	};
}

--=====================================================================
-- Discovery state
--=====================================================================
local function UnlockedSet()
	local set = {}
	local ok, unlocked = pcall(function()
		return Player.PlayerData.Pets.Unlocked.Value
	end)
	if ok and unlocked then
		for name in string.gmatch(unlocked, "[^|]+") do
			set[name] = true
		end
	end
	return set
end

--=====================================================================
-- Viewport culling (same scheme as the Pets inventory: Roblox does not
-- cull ViewportFrames clipped by a ScrollingFrame, so 78 index viewports
-- would all render at once without this)
--=====================================================================
local function UpdateViewportCulling()
	if not (Grid and Grid.Parent) then return end
	if not PanelOpen then
		for tile, m3d in pairs(Viewports) do
			if not tile.Parent then
				Viewports[tile] = nil
			elseif m3d.Visible then
				m3d.Visible = false
			end
		end
		return
	end
	local winTop = Grid.AbsolutePosition.Y - CULL_MARGIN
	local winBot = Grid.AbsolutePosition.Y + Grid.AbsoluteWindowSize.Y + CULL_MARGIN
	for tile, m3d in pairs(Viewports) do
		if not tile.Parent then
			Viewports[tile] = nil
		else
			local tTop = tile.AbsolutePosition.Y
			local tBot = tTop + tile.AbsoluteSize.Y
			local onScreen = tile.Visible and tBot >= winTop and tTop <= winBot
			if m3d.Visible ~= onScreen then
				m3d.Visible = onScreen
			end
		end
	end
end

local cullQueued = false
local function queueCull()
	if cullQueued then return end
	cullQueued = true
	task.delay(0.03, function()
		cullQueued = false
		UpdateViewportCulling()
	end)
end

--=====================================================================
-- Tabs
--=====================================================================
local function ApplyFilter()
	if not Tiles then return end
	local want = TAB_FILTER[ActiveTab]
	for _, tile in pairs(Tiles) do
		tile.Visible = (want == nil) or (tile:GetAttribute("Rarity") == want)
	end
	Grid.CanvasPosition = Vector2.new(0, 0)
	queueCull()
end

local function SetTab(tabButton)
	ActiveTab = tabButton.Name
	for _, b in ipairs(Canvas.Tabs:GetChildren()) do
		if b:IsA("TextButton") then
			local selected = b.Name == ActiveTab
			b.Fill.SelectStroke.Color = selected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
			b.TabScale.Scale = selected and 1.06 or 1
		end
	end
	ApplyFilter()
end

--=====================================================================
-- Tile construction (once, lazily on first open)
--=====================================================================
local function BuildTiles()
	if Built then return end
	Built = true

	if not PetDict then
		local ok, dict = pcall(function()
			return Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})
		end)
		if ok then PetDict = dict end
	end
	local stats = PetDict and (PetDict.Stats or PetDict)
	if not stats then
		Built = false -- retry on the next open instead of bricking the panel
		warn("[Index] Pets dictionary unavailable")
		return
	end

	local list = {}
	for name, def in pairs(stats) do
		list[#list + 1] = {Name = name; Rarity = def.Rarity or "Common"}
	end
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[a.Rarity] or 0, RARITY_ORDER[b.Rarity] or 0
		if ra ~= rb then return ra < rb end
		return a.Name < b.Name
	end)

	local template = Grid.TileTemplate
	local petsFolder = ReplicatedStorage.Assets.Pets
	Tiles = {}
	for i, pet in ipairs(list) do
		local tile = template:Clone()
		tile.Name = pet.Name
		tile.LayoutOrder = i
		tile:SetAttribute("Rarity", pet.Rarity)
		tile.Visible = true
		tile.Parent = Grid
		Tiles[pet.Name] = tile

		--.. live 3D pet in the transparent Icon square (culled while offscreen)
		local model = petsFolder:FindFirstChild(pet.Name)
		if model then
			local m3d = Module3D:Attach3D(tile.Icon, model:Clone())
			m3d:SetDepthMultiplier(1.1)
			m3d.CurrentCamera.FieldOfView = 5
			m3d:SetCFrame(CFrame.Angles(0, math.rad(265), 0))
			m3d.Visible = false -- culling switches it on when scrolled into view
			Viewports[tile] = m3d
		end

		--.. building 78 viewport tiles in one gulp hitches low-end devices
		if i % 12 == 0 then task.wait() end
	end
end

--=====================================================================
-- State refresh (every open + on discovery/claim changes)
--=====================================================================
local function RefreshState()
	if not (Index and Built and Tiles) then return end
	local unlocked = UnlockedSet()
	local stats = PetDict and (PetDict.Stats or PetDict) or {}

	local total, found = 0, 0
	for name in pairs(stats) do
		total += 1
		if unlocked[name] then found += 1 end
	end

	for name, tile in pairs(Tiles) do
		local isUnlocked = unlocked[name] == true
		local rarity = tile:GetAttribute("Rarity")
		local colors = (isUnlocked and RARITY_GRADIENTS[rarity]) or LOCKED_GRADIENT
		tile.NameBar.Fill.UIGradient.Color = ColorSequence.new(colors[1], colors[2])
		tile.NameBar.Underline.BackgroundColor3 = colors[3]
		tile.NameBar.NameLabel.Text = isUnlocked and require(game.ReplicatedStorage.Modules.PetDisplayNames).Get(name) or "???"
		local m3d = Viewports[tile]
		if m3d then
			--.. locked pets render as black silhouettes (same trick as the egg preview)
			m3d.ImageColor3 = isUnlocked and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
		end
	end

	Canvas.DiscoveredLabel.Text = ("Discovered: %d/%d"):format(found, total)
	Canvas.PercentLabel.Text = total > 0 and (math.floor(found / total * 100 + 0.5) .. "%") or "0%"

	--.. milestone claim text (server-authoritative numbers)
	task.spawn(function()
		local ok, progress = pcall(function()
			return Network:InvokeServer("GetIndexProgress")
		end)
		local claimLabel = Canvas.ClaimButton.TextLabel
		if ok and progress and progress.Claimable and progress.Claimable > 0 then
			claimLabel.Text = ("CLAIM +%d COINS"):format(progress.NextReward)
		elseif ok and progress then
			local toNext = progress.PerMilestone - (progress.Discovered % progress.PerMilestone)
			claimLabel.Text = ("%d MORE PETS FOR +%d COINS"):format(toNext, progress.NextReward)
		end
	end)
end

--=====================================================================
-- Lifecycle (UserInterfaceLoader contract: DoesUpdate=true fires
-- OnOpen/OnClose off the frame's Visible property; Main.OpenFrame toggles it)
--=====================================================================
function Module.OnOpen()
	PanelOpen = true
	BuildTiles()
	RefreshState()
	ApplyFilter()
	--.. first open fires before tiles have AbsolutePositions; settle then cull
	task.defer(queueCull)
	task.delay(0.05, queueCull)
end

function Module.OnClose()
	PanelOpen = false
	queueCull() -- switch every viewport off while hidden
end

function Module.GetModules() end

function Module.OnStart(Interface)
	Index = Interface
	Canvas = Index:WaitForChild("Canvas")
	Grid = Canvas:WaitForChild("Grid")

	--.. Drive the canvas UIScale off the aspect-locked Frames box (the Pets
	--.. inventory contract: authored TextSize/strokes scale on every device).
	do
		local Scaler = Canvas:FindFirstChildOfClass("UIScale")
		local Host = Index.Parent
		if Scaler and Host then
			local function UpdateScale()
				if Host.AbsoluteSize.X > 0 then
					Scaler.Scale = Host.AbsoluteSize.X * PANEL_FILL / DESIGN_W
				end
			end
			UpdateScale()
			Host:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateScale)
		end
	end

	--.. rarity tabs
	for _, b in ipairs(Canvas.Tabs:GetChildren()) do
		if b:IsA("TextButton") then
			b.MouseButton1Click:Connect(function()
				SetTab(b)
			end)
		end
	end
	SetTab(Canvas.Tabs.TabAll) -- default state (also paints selection visuals)

	--.. viewport culling follows the scroll window
	Grid:GetPropertyChangedSignal("CanvasPosition"):Connect(queueCull)

	--.. live discovery updates while the panel is open (hatching new pets)
	task.spawn(function()
		local pets = Player:WaitForChild("PlayerData", 30)
		pets = pets and pets:WaitForChild("Pets", 10)
		local unlockedValue = pets and pets:WaitForChild("Unlocked", 10)
		if unlockedValue then
			unlockedValue.Changed:Connect(function()
				if PanelOpen then RefreshState() end
			end)
		end
	end)

	--.. milestone claim
	do
		local Button = Index.Canvas.ClaimButton
		local ButtonFunction = ComponentController.new({
			UIGradient = Button.TextLabel.UIGradient;
			Button = Button;
			OriginalGradient = Module.Gradients.ClaimButton.OriginalGradient;
			HoverGradient = Module.Gradients.ClaimButton.HoverGradient;
		})
		Button.MouseEnter:Connect(function() ButtonFunction:Hover() end)
		Button.MouseLeave:Connect(function() ButtonFunction:Leave() end)

		local Claiming = false
		Button.MouseButton1Click:Connect(function()
			if Claiming then return end
			Claiming = true
			ButtonFunction:Burst()
			pcall(function()
				Network:InvokeServer("ClaimIndexReward")
			end)
			RefreshState()
			Claiming = false
		end)
	end
end

return Module

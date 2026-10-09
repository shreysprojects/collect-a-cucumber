--[[
	PetView  (ModuleScript, StarterGui.CucumberMenus)
	Draws the Pets panel. Every instance is AUTHORED by pets-system/builders/build_petspanel.lua
	(PetsPanel.Content: Header, SlotRow.Slot1..6, Toolbar, PetGrid, Details, Footer, LockBanner,
	Status; PetsPanel.Templates: PetCard, SlotCard, Chip); this module only fills them from the
	view model PetController.Core.BuildViewModel makes, and reports clicks back.

	2026-09-22 (pet system, pets-system/CONTRACTS.md 3.11):
	  View.Start(gui) -> view        gui = PlayerGui.CucumberMenus
	  view.Render(vm)                header count, six slots, toolbar state, pet cards, details, footer, lock banner
	  view.SetStatus(text?)          the loading / error line (nil or "" hides it)
	  view.SetNextRoll(text)         the details countdown, refreshed by the controller between renders
	  view.Feedback(ok)              a refused request: fail sound + red flash on the equip button
	  view.FocusTarget(rosterEmpty)  what gamepad focus lands on when the panel opens
	  view.SetFooter(footer)         only the footer's three totals (review fix below)
	  view.ShowDetails(open)         compact layout: open / close the Details page (review fix below)
	  view.OnSelect(fn(petId)) / OnEquip(fn(petId, equip)) / OnBest(fn(mode)) / OnSort(fn(mode)) / OnFilter(fn(mode))
	  view.Destroy()
	  View.FitChips(chips, widthOf, maxWidth, gap)   pure chip-row fitting (review fix below)
	Cards are pooled by PetId (a re-render only rewrites text / colours); a card is destroyed only when
	its pet leaves the inventory, hidden while filtered out. Model previews (ViewportFrames) are built a
	few per step and only for cards near the visible part of the grid, and the ones far away are
	dropped again above MAX_CARD_PREVIEWS, so a big inventory never builds hundreds of models. A
	preview gets the pet's material / first-mutation look (CucumberMutations.ApplyLook with
	PrismaticLoop pre-set, so no colour loop runs; particles and lights are removed because viewports
	do not draw them). The selected pet's preview turns slowly while the panel is open.
	Hover / press pops use this module's own UIScale "PressScale" stepped on Heartbeat (ButtonFX.Animate);
	it never touches HoverScale / FXScale, which belong to MenuController (the CloseButton) and ButtonFX.
	Money texts arrive already formatted with NumberAbbrev.Abbrev ("$3.75/s"); cash is the HUD green.

	2026-09-22 (review fixes):
	  * Big inventories: cards are materialised in display order, INITIAL_CARDS on the first render and
	    CARD_BATCH more whenever the grid is scrolled near the last one, so opening the panel with 1000
	    pets clones 24 cards, not 1000; cards past that prefix stay hidden (pooled) until the grid grows to
	    them. A re-render only writes the properties of cards whose texts changed (a per-card signature),
	    and view.SetFooter(footer) redraws just the footer (the controller's path for Kind = "Totals").
	    A switch between the wide and compact layouts re-draws the held view model WITHOUT its footer, so
	    totals a later SetFooter wrote are never replaced by the older ones in that model.
	  * Chips are fitted to the chip row's WIDTH (TextService widths of the chip font + padding + gap):
	    the ones that do not fit fold into a "+N" chip (View.FitChips, pure), so a card's chips never spill
	    into the neighbouring card. The controller hands over every material / mutation chip.
	  * Phones: while PetsPanel.ResponsiveScale.Scale < the panel attribute CompactBelow (0.55; the 844 x 390
	    landscape fit is ~0.372) the view uses the builder's COMPACT layout: every instance's
	    Compact_<Property> attributes are applied (and the authored values put back above the threshold),
	    the grid shows 2 wide columns, the slot row and sort / filter tabs hide, Toolbar.SortCycle /
	    FilterCycle step through the sort / filter modes, and Details becomes a page over the grid +
	    toolbar: tapping a card opens it, Details.BackButton closes it (view.ShowDetails(open) does the
	    same; closing the panel resets it). A card's status tag takes its chip row's place there. The
	    panel attribute Compact mirrors the mode. Compact texts are >= 30 design px (~11 real px on the
	    phone) and its buttons >= 110 design px tall (~41 real px); the Details traits line wraps to up to
	    three lines there, so a material + all eight mutations stays at 30.

	2026-09-22 (S7 integration, phone preset): UITextSizeConstraint MaxTextSize / MinTextSize are SCREEN pixels
	(they apply after the panel's UIScale), but the builder writes them in design px. On the iPhone 13 preset
	(fit 0.362) the compact Min 20 therefore forced 20 px text into 13-18 px boxes (lines overflowed and ran
	into each other) and no Max cap ever bound. The view now keeps each cap's design values (attributes
	DesignMaxTextSize / DesignMinTextSize) and writes design x ResponsiveScale.Scale, for the wide or compact
	values, whenever the scale or the layout changes (Destroy puts the design values back).
]]
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local View = {}

local C = Color3.fromRGB
local HOVER_SCALE = 1.035
local PRESS_SCALE = 0.97
local POP_SECONDS = 0.12
local PREVIEW_FOV = 30
local PREVIEW_DIRECTION = Vector3.new(0.15, 0.3, 1).Unit -- camera side: front, a little right and above
local PREVIEW_YAW = math.rad(200)       -- pet models face -Z; turn them to the camera, slightly to the side
local PREVIEWS_PER_STEP = 3             -- card previews built per scan
local PREVIEW_SCAN = 0.15               -- seconds between preview / card scans while the panel is open
local MAX_CARD_PREVIEWS = 48            -- built card previews kept at most (far ones are dropped first)
local INITIAL_CARDS = 24                -- cards materialised by the first render (a multiple of 2 and 3 columns)
local CARD_BATCH = 18                   -- more cards per scan once the grid is scrolled near the last one
local DETAIL_SPIN = 0.5                 -- rad/s, the selected pet's preview
local COMPACT_BELOW = 0.55              -- default for the PetsPanel attribute CompactBelow
local COMPACT_PREFIX = "Compact_"       -- builder attributes: Compact_<Property> = the compact value
local CHIP_FONT = Enum.Font.FredokaOne  -- the Chip template's label font (for the width fitting)
local CASH_HEX = "#41EB14"              -- 65, 235, 20: the HUD cash green
local MUTED_HEX = "#C8CDD7"
local WHITE = C(255, 255, 255)
local CARD_BORDER = C(36, 25, 29)
local SELECTED_BORDER = C(255, 205, 40)
local CHIP_FALLBACK = C(90, 96, 120)
local FAIL_FLASH = C(255, 70, 70)
local PALETTE = {
	On = {C(15, 224, 255), C(0, 170, 240)},      -- IndexView's active tab
	Off = {C(146, 177, 207), C(74, 113, 148)},   -- IndexView's inactive tab
	Green = {C(149, 255, 70), C(63, 204, 28)},   -- EquipReward unlocked
	Red = {C(255, 100, 100), C(230, 30, 30)},
	Grey = {C(149, 172, 180), C(104, 130, 143)}, -- EquipReward locked
}
local SORT_BUTTONS = {Income = "SortIncome", Combat = "SortCombat", Rarity = "SortRarity", Newest = "SortNewest"}
local FILTER_BUTTONS = {All = "FilterAll", Active = "FilterActive", Reserve = "FilterReserve"}
local BEST_BUTTONS = {Income = "BestIncome", Combat = "BestCombat"}
local SORT_CYCLE = {"Income", "Combat", "Rarity", "Newest"} -- compact SortCycle order
local FILTER_CYCLE = {"All", "Active", "Reserve"}
local SORT_WORDS = {Income = "INCOME", Combat = "COMBAT", Rarity = "RARITY", Newest = "NEWEST"}
local FILTER_WORDS = {All = "ALL", Active = "ACTIVE", Reserve = "RESERVE"}

local function Module(name, wait)
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	if not modules and wait then modules = ReplicatedStorage:WaitForChild("Modules", wait) end
	local module = modules and modules:FindFirstChild(name)
	if not module and modules and wait then module = modules:WaitForChild(name, wait) end
	if not module then return nil end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then return result end
	warn("[PetView] " .. name .. ": " .. tostring(result))
	return nil
end

local function Escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function Need(parent, name)
	local child = parent:FindFirstChild(name)
	if not child then error("[PetView] missing " .. parent:GetFullName() .. "." .. name .. " - re-run build_petspanel.lua") end
	return child
end

local function IsPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function Paint(button, pair)
	local gradient = button:FindFirstChild("Gradient")
	if gradient then gradient.Color = ColorSequence.new(pair[1], pair[2]) end
end

local function SetLabel(button, text)
	local label = button:FindFirstChild("Label")
	if label then label.Text = text end
end

local function NextOf(list, value)
	local i = table.find(list, value)
	return list[i and (i % #list) + 1 or 1]
end

--.. chips = {{Text, Word}...} in priority order; widthOf(text) = one chip's full width (text + padding).
--.. Returns the chips that fit in maxWidth (gap between chips); when not all fit, the rest fold into a
--.. trailing {Text = "+N", Word = ""} chip that is counted in the width too. Pure (unit-tested).
function View.FitChips(chips, widthOf, maxWidth, gap)
	local n = type(chips) == "table" and #chips or 0
	if n == 0 then return {} end
	gap = gap or 0
	local sums, total = {}, 0
	for i = 1, n do
		total += widthOf(chips[i].Text)
		sums[i] = total
	end
	if total + gap * (n - 1) <= maxWidth then return chips end
	for k = n - 1, 0, -1 do
		local more = "+" .. (n - k)
		local need = (k > 0 and sums[k] + gap * k or 0) + widthOf(more)
		if need <= maxWidth then
			local out = table.move(chips, 1, k, 1, {})
			out[k + 1] = {Text = more, Word = ""}
			return out
		end
	end
	return {}
end

--.. Compact_<Property> attributes on root and its descendants -> {{Inst, Prop, Compact, Wide}}; Wide = the
--.. authored value read now (collect before the first compact write)
local function IsCapProp(inst, prop)
	return (prop == "MaxTextSize" or prop == "MinTextSize") and inst:IsA("UITextSizeConstraint")
end

local function CollectLayout(root, list)
	list = list or {}
	local function add(inst)
		for name, value in pairs(inst:GetAttributes()) do
			if string.sub(name, 1, #COMPACT_PREFIX) == COMPACT_PREFIX then
				local prop = string.sub(name, #COMPACT_PREFIX + 1)
				local ok, wide = pcall(function() return inst[prop] end)
				-- text caps are not layout values: CollectCaps / ApplyCaps scale them (S7 note below)
				if ok and typeof(wide) == typeof(value) and not IsCapProp(inst, prop) then
					list[#list + 1] = {Inst = inst, Prop = prop, Compact = value, Wide = wide}
				end
			end
		end
	end
	add(root)
	for _, d in ipairs(root:GetDescendants()) do add(d) end
	return list
end

local function ApplyLayout(list, compact)
	for _, e in ipairs(list) do
		local value = if compact then e.Compact else e.Wide
		if e.Inst[e.Prop] ~= value then e.Inst[e.Prop] = value end
	end
end

--.. 2026-09-22 (S7 integration): a UITextSizeConstraint's MaxTextSize / MinTextSize are SCREEN pixels (measured
--.. on the phone preset: a SizeCap Max 10 gave 10 px text under the panel's 0.36 UIScale, and the compact Min 20
--.. forced 20 px text into 13-18 px boxes, so lines overflowed and overlapped), while the builder authors them -
--.. and the Compact_MaxTextSize / Compact_MinTextSize attributes - in DESIGN px like every other size. So every
--.. cap keeps its authored design values in the attributes DesignMaxTextSize / DesignMinTextSize (written once,
--.. so a later view reads the same numbers) and gets design x PetsPanel.ResponsiveScale.Scale (rounded, >= 1)
--.. whenever the scale or the layout changes. Destroy writes the design values back.
local function CollectCaps(root, list)
	list = list or {}
	local function add(cap)
		local max = cap:GetAttribute("DesignMaxTextSize")
		local min = cap:GetAttribute("DesignMinTextSize")
		if type(max) ~= "number" then max = cap.MaxTextSize cap:SetAttribute("DesignMaxTextSize", max) end
		if type(min) ~= "number" then min = cap.MinTextSize cap:SetAttribute("DesignMinTextSize", min) end
		local cmax, cmin = cap:GetAttribute(COMPACT_PREFIX .. "MaxTextSize"), cap:GetAttribute(COMPACT_PREFIX .. "MinTextSize")
		list[#list + 1] = {Cap = cap, Max = max, Min = min, CompactMax = type(cmax) == "number" and cmax or max,
			CompactMin = type(cmin) == "number" and cmin or min}
	end
	if root:IsA("UITextSizeConstraint") then add(root) end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UITextSizeConstraint") then add(d) end
	end
	return list
end

local function ApplyCaps(list, compact, scale)
	scale = type(scale) == "number" and scale == scale and scale > 0 and scale or 1
	for _, e in ipairs(list) do
		local cap = e.Cap
		local max = math.max(1, math.floor((if compact then e.CompactMax else e.Max) * scale + 0.5))
		local min = math.clamp(math.floor((if compact then e.CompactMin else e.Min) * scale + 0.5), 1, max)
		if cap.MinTextSize > max then cap.MinTextSize = min end -- never Min > Max, not even for one write
		if cap.MaxTextSize ~= max then cap.MaxTextSize = max end
		if cap.MinTextSize ~= min then cap.MinTextSize = min end
	end
end

local function RestoreCaps(list)
	for _, e in ipairs(list) do
		if e.Cap.MinTextSize > e.Max then e.Cap.MinTextSize = e.Min end
		e.Cap.MaxTextSize = e.Max
		e.Cap.MinTextSize = e.Min
	end
end

--..Previews..--
local function ClearPreview(viewport)
	for _, child in ipairs(viewport:GetChildren()) do
		if child.Name == "PreviewModel" or child.Name == "PreviewCamera" then child:Destroy() end
	end
	viewport.CurrentCamera = nil
end

local function BuildPreview(viewport, catalog, mutations, petKey, material, mutationList)
	ClearPreview(viewport)
	local source = catalog and type(petKey) == "string" and petKey ~= "" and catalog.ModelOf(petKey)
	if not (source and source:IsA("Model")) then return nil end
	local model = source:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then d:Destroy() end
	end
	model:SetAttribute("PrismaticLoop", true) -- ApplyLook must not start its colour loop on a preview
	if mutations and (material ~= "" or #mutationList > 0) then
		pcall(mutations.ApplyLook, model, material ~= "" and material or nil, table.concat(mutationList, ","))
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then d:Destroy() end
	end
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(CFrame.Angles(0, PREVIEW_YAW, 0))
	model.Name = "PreviewModel"
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = PREVIEW_FOV
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	camera.CFrame = CFrame.lookAt(PREVIEW_DIRECTION * (radius / math.tan(math.rad(PREVIEW_FOV * 0.5))), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	return model
end

function View.Start(gui)
	local panel = Need(gui, "PetsPanel")
	local content = Need(panel, "Content")
	local templates = Need(panel, "Templates")
	local cardTemplate = Need(templates, "PetCard")
	local chipTemplate = Need(templates, "Chip")
	local header = Need(content, "Header")
	local subtitle = Need(header, "Subtitle")
	local slotRow = Need(content, "SlotRow")
	local toolbar = Need(content, "Toolbar")
	local grid = Need(content, "PetGrid")
	local empty = Need(grid, "Empty")
	local details = Need(content, "Details")
	local footer = Need(content, "Footer")
	local lockBanner = Need(content, "LockBanner")
	local status = Need(content, "Status")
	local d = {}
	for _, name in ipairs({"Preview", "PetName", "Rarity", "Traits", "CashLine", "CombatLine", "AbilityName",
		"AbilityEffect", "AbilityChance", "NextRoll", "EquipButton"}) do
		d[name] = Need(details, name)
	end
	local f = {Pet = Need(footer, "PetCash"), Cucumber = Need(footer, "CucumberCash"), Total = Need(footer, "TotalCash")}
	local slots = {}
	for i = 1, 12 do
		local slot = slotRow:FindFirstChild("Slot" .. i)
		if not slot then break end
		slots[i] = {Button = slot, Id = nil, Look = nil}
	end
	-- compact-only buttons (a panel built before the compact layout has none: it then stays wide)
	local sortCycle = toolbar:FindFirstChild("SortCycle")
	local filterCycle = toolbar:FindFirstChild("FilterCycle")
	local backButton = details:FindFirstChild("BackButton")
	local responsive = panel:FindFirstChild("ResponsiveScale")
	local canCompact = sortCycle ~= nil and filterCycle ~= nil and backButton ~= nil and responsive ~= nil and responsive:IsA("UIScale")
	local chipLabelTemplate = chipTemplate:FindFirstChild("Label")
	local chipPadding = chipTemplate:FindFirstChildOfClass("UIPadding")
	local chipPad = chipPadding and (chipPadding.PaddingLeft.Offset + chipPadding.PaddingRight.Offset) or 10

	local ButtonFX = Module("ButtonFX", 5)
	local Catalog = Module("PetsCatalog", 5)
	local Mutations = Module("CucumberMutations", 5)
	local Balance = nil
	local function Abilities()
		if not Balance then Balance = Module("PetBalance") end
		return Balance and Balance.ABILITIES or nil
	end

	local view = {}
	local callbacks = {}
	local connections = {}
	local destroyed = false
	local current = nil -- the last view model
	local cards = {} -- [petId] = {Id, Button, Conns, Layout, Visible, Order, Sig, ChipKey, ChipsHidden, HasPreview, PreviewLook, Card}
	local limit = INITIAL_CARDS -- display positions materialised so far (grows while the grid is scrolled)
	local builtCount = 0
	local popTokens = {}
	local detail = {Id = nil, Look = nil, Model = nil, Yaw = PREVIEW_YAW, EquipAction = nil, EquipEnabled = false}
	local compact = false
	local overlay = false -- compact: the Details page is open over the grid + toolbar
	local layout = CollectLayout(content) -- the authored (wide) values are captured here
	local caps = CollectCaps(content) -- text caps: design values, written as design x scale (S7)
	local toolbarKey = nil
	local function CurrentScale()
		return responsive ~= nil and responsive:IsA("UIScale") and responsive.Scale or 1
	end

	local function Sound(entry)
		if ButtonFX and entry then ButtonFX.Sound(entry) end
	end

	--.. hover / press pop on this module's own UIScale
	local function Pop(button, target)
		local scale = button:FindFirstChild("PressScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "PressScale"
			scale.Parent = button
		end
		local token = (popTokens[button] or 0) + 1
		popTokens[button] = token
		if not ButtonFX then
			scale.Scale = target
			return
		end
		local from = scale.Scale
		task.spawn(function()
			ButtonFX.Animate(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
				scale.Scale = from + (target - from) * a
			end, function() return not destroyed and popTokens[button] == token and button.Parent ~= nil end)
		end)
	end

	local function Wire(button, onActivated, list)
		list = list or connections
		table.insert(list, button.MouseEnter:Connect(function() Pop(button, HOVER_SCALE) end))
		table.insert(list, button.MouseLeave:Connect(function() Pop(button, 1) end))
		table.insert(list, button.SelectionGained:Connect(function() Pop(button, HOVER_SCALE) end))
		table.insert(list, button.SelectionLost:Connect(function() Pop(button, 1) end))
		table.insert(list, button.InputBegan:Connect(function(input) if IsPointer(input) then Pop(button, PRESS_SCALE) end end))
		table.insert(list, button.InputEnded:Connect(function(input) if IsPointer(input) then Pop(button, 1) end end))
		table.insert(list, button.Activated:Connect(function()
			if destroyed then return end
			onActivated()
		end))
	end

	local function Fire(name, ...)
		local fn = callbacks[name]
		if fn then task.spawn(fn, ...) end
	end

	--.. gamepad: move a selection that is inside the panel (never grabs focus from elsewhere)
	local function MoveFocus(target)
		local selected = GuiService.SelectedObject
		if target and selected and selected:IsDescendantOf(panel) then GuiService.SelectedObject = target end
	end

	--.. compact: which page shows (the grid + toolbar, or the Details page)
	local function UpdatePages()
		local page = compact and overlay
		grid.Visible = not page
		toolbar.Visible = not page
		details.Visible = not compact or page
	end

	--..Static wiring..--
	for mode, name in pairs(SORT_BUTTONS) do
		local button = Need(toolbar, name)
		Wire(button, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Sort", mode)
		end)
	end
	for mode, name in pairs(FILTER_BUTTONS) do
		local button = Need(toolbar, name)
		Wire(button, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Filter", mode)
		end)
	end
	for mode, name in pairs(BEST_BUTTONS) do
		local button = Need(toolbar, name)
		Wire(button, function()
			if not (current and current.ActionsEnabled) then return end
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Best", mode)
		end)
	end
	if sortCycle then
		Wire(sortCycle, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Sort", NextOf(SORT_CYCLE, current and current.Sort or "Income"))
		end)
	end
	if filterCycle then
		Wire(filterCycle, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Filter", NextOf(FILTER_CYCLE, current and current.Filter or "All"))
		end)
	end
	if backButton then
		Wire(backButton, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			view.ShowDetails(false)
		end)
	end
	Wire(d.EquipButton, function()
		if not (detail.Id and detail.EquipEnabled and detail.EquipAction) then
			if detail.Id then Sound(ButtonFX and ButtonFX.FAIL_SOUND) end
			return
		end
		Sound(ButtonFX and ButtonFX.PRESS_SOUND)
		Fire("Equip", detail.Id, detail.EquipAction == "Equip")
	end)
	for _, slot in ipairs(slots) do
		Wire(slot.Button, function()
			if not slot.Id then return end
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			Fire("Select", slot.Id)
		end)
	end

	--..Cards..--
	local function DropPreview(entry)
		if entry.HasPreview then
			ClearPreview(entry.Button.Preview)
			entry.HasPreview = false
			builtCount -= 1
		end
	end

	local function DropCard(entry)
		for _, connection in ipairs(entry.Conns) do connection:Disconnect() end
		DropPreview(entry)
		popTokens[entry.Button] = nil
		entry.Button:Destroy()
		cards[entry.Id] = nil
	end

	local function SetVisible(entry, visible)
		if entry.Visible ~= visible then
			entry.Visible = visible
			entry.Button.Visible = visible
		end
	end

	local function NewCard(id)
		local button = cardTemplate:Clone()
		button.Name = "Pet_" .. id
		local entry = {Id = id, Button = button, Conns = {}, Layout = CollectLayout(button), Caps = CollectCaps(button), Visible = button.Visible, HasPreview = false}
		ApplyLayout(entry.Layout, compact)
		ApplyCaps(entry.Caps, compact, CurrentScale())
		Wire(button, function()
			Sound(ButtonFX and ButtonFX.PRESS_SOUND)
			if compact then view.ShowDetails(true) end
			Fire("Select", entry.Id)
		end, entry.Conns)
		button.Parent = grid
		cards[id] = entry
		return entry
	end

	--.. one chip's width in design px (text in the chip font + the chip's padding), cached per size + text
	local chipWidths = {}
	local function ChipTextSize()
		if not chipLabelTemplate then return 14 end
		local size = compact and chipLabelTemplate:GetAttribute(COMPACT_PREFIX .. "TextSize") or nil
		return type(size) == "number" and size or chipLabelTemplate.TextSize
	end
	local function ChipWidth(text, textSize)
		local cache = chipWidths[textSize]
		if not cache then
			cache = {}
			chipWidths[textSize] = cache
		end
		local width = cache[text]
		if not width then
			local ok, bounds = pcall(TextService.GetTextSize, TextService, text, textSize, CHIP_FONT, Vector2.new(10000, 10000))
			width = ok and bounds.X or #text * textSize * 0.62
			cache[text] = width
		end
		return width + chipPad
	end

	local function FillChips(frame, chips)
		for _, child in ipairs(frame:GetChildren()) do
			if child.Name == "Chip" then child:Destroy() end
		end
		local listLayout = frame:FindFirstChildOfClass("UIListLayout")
		local textSize = ChipTextSize()
		local fitted = View.FitChips(chips, function(text) return ChipWidth(text, textSize) end,
			frame.Size.X.Offset, listLayout and listLayout.Padding.Offset or 0)
		for i, chip in ipairs(fitted) do
			local item = chipTemplate:Clone()
			item.Name = "Chip"
			item.LayoutOrder = i
			item.Visible = true
			ApplyLayout(CollectLayout(item), compact)
			local color = Mutations and chip.Word ~= "" and Mutations.ColorOf(chip.Word) or nil
			item.BackgroundColor3 = color or CHIP_FALLBACK
			local label = item:FindFirstChild("Label")
			if label then label.Text = chip.Text end
			item.Parent = frame
		end
	end

	local function RarityLook(rarity)
		local glow = Catalog and Catalog.RARITY_GLOW[rarity] or WHITE
		local gradient = Catalog and Catalog.RARITY_GRADIENTS[rarity] or ColorSequence.new(glow)
		return glow, gradient
	end

	local function UpdateCard(entry, c, order)
		local b = entry.Button
		if entry.Order ~= order then
			entry.Order = order
			b.LayoutOrder = order
		end
		SetVisible(entry, true)
		local statusText = tostring(c.StatusText or "")
		-- only the texts / colours that changed since the last render are written
		local sig = table.concat({tostring(c.DisplayName), tostring(c.Rarity), tostring(c.RateText), c.Equipped and "1" or "0",
			statusText, c.Selected and "1" or "0"}, "\n")
		if entry.Sig ~= sig then
			entry.Sig = sig
			b.PetName.Text = c.DisplayName
			local glow, gradient = RarityLook(c.Rarity)
			b.RarityText.Text = string.upper(c.Rarity)
			b.RarityText.TextColor3 = glow
			local bar = b.RarityBar
			bar.BackgroundColor3 = WHITE
			local barGradient = bar:FindFirstChild("Gradient")
			if barGradient then barGradient.Color = gradient else bar.BackgroundColor3 = glow end
			b.Rate.Text = c.RateText
			b.EquippedTag.Visible = c.Equipped
			b.StatusTag.Text = statusText
			b.StatusTag.Visible = statusText ~= ""
			local border = b:FindFirstChild("Border")
			if border then
				border.Color = c.Selected and SELECTED_BORDER or CARD_BORDER
				border.Thickness = c.Selected and 5 or 3
			end
		end
		-- compact: the status tag sits on the chip row
		local hideChips = compact and statusText ~= ""
		if entry.ChipsHidden ~= hideChips then
			entry.ChipsHidden = hideChips
			b.Chips.Visible = not hideChips
		end
		local chipKey = {}
		for _, chip in ipairs(c.Chips or {}) do chipKey[#chipKey + 1] = chip.Text end
		chipKey = table.concat(chipKey, ",") .. (compact and "|c" or "|w")
		if entry.ChipKey ~= chipKey then
			entry.ChipKey = chipKey
			FillChips(b.Chips, c.Chips or {})
		end
		if entry.PreviewLook ~= c.Look then
			DropPreview(entry)
			entry.PreviewLook = c.Look
		end
		entry.Card = c
	end

	--..Slots / details..--
	local function UpdateSlot(slot, s)
		local b = slot.Button
		b.Visible = true
		slot.Id = s.Id
		b.Empty.Visible = s.Id == nil
		b.PetName.Text = s.Id and s.DisplayName or ""
		local border = b:FindFirstChild("Border")
		if border then
			border.Color = s.Selected and SELECTED_BORDER or CARD_BORDER
			border.Thickness = s.Selected and 5 or 3
		end
		local look = s.Id and s.Look or nil
		if slot.Look ~= look then
			slot.Look = look
			if look then
				BuildPreview(b.Preview, Catalog, Mutations, s.Pet, s.Material, s.Mutations)
			else
				ClearPreview(b.Preview)
			end
		end
	end

	local function TraitsText(list)
		if #list == 0 then return string.format('<font color="%s">No traits</font>', MUTED_HEX) end
		local parts = {}
		for _, word in ipairs(list) do
			local color = Mutations and Mutations.ColorOf(word)
			parts[#parts + 1] = color and Mutations.Font(word, color, true) or Escape(word)
		end
		return table.concat(parts, "  ")
	end

	local function RenderDetails(info, loaded)
		if not info then
			detail.Id, detail.EquipAction, detail.EquipEnabled = nil, nil, false
			if detail.Look then
				ClearPreview(d.Preview)
				detail.Look, detail.Model = nil, nil
			end
			d.PetName.Text = loaded and "Select a pet" or ""
			for _, name in ipairs({"Rarity", "Traits", "CashLine", "CombatLine", "AbilityName", "AbilityEffect", "AbilityChance", "NextRoll"}) do
				d[name].Text = ""
			end
			d.EquipButton.Visible = false
			return
		end
		detail.Id = info.Id
		detail.EquipAction = info.EquipAction
		detail.EquipEnabled = info.EquipEnabled == true
		if detail.Look ~= info.Look then
			detail.Look = info.Look
			detail.Yaw = PREVIEW_YAW
			detail.Model = BuildPreview(d.Preview, Catalog, Mutations, info.Pet, info.Material, info.Mutations)
		end
		d.PetName.Text = info.DisplayName
		local glow = RarityLook(info.Rarity)
		d.Rarity.Text = string.upper(info.Rarity) .. (info.StatusText ~= "" and ("  ·  " .. string.upper(info.StatusText)) or "")
		d.Rarity.TextColor3 = glow
		d.Traits.Text = TraitsText(info.Traits)
		local note = info.RateNote ~= "" and string.format('  <font color="%s">(%s)</font>', MUTED_HEX, Escape(info.RateNote)) or ""
		d.CashLine.Text = string.format('Cash  <font color="%s">%s</font>%s', CASH_HEX, Escape(info.Rate), note)
		d.CombatLine.Text = info.Combat
		local abilities = Abilities()
		local row = abilities and abilities[info.AbilityKind] -- "NoAbility" (not a fighter) has no row: white
		d.AbilityName.Text = info.AbilityName
		d.AbilityName.TextColor3 = type(row) == "table" and typeof(row.Color) == "Color3" and row.Color or WHITE
		d.AbilityEffect.Text = info.AbilityEffect
		d.AbilityChance.Text = info.AbilityChance
		d.NextRoll.Text = info.NextRoll
		local button = d.EquipButton
		button.Visible = true
		SetLabel(button, info.EquipText)
		if not info.EquipEnabled then
			Paint(button, PALETTE.Grey)
		elseif info.EquipAction == "Unequip" then
			Paint(button, PALETTE.Red)
		else
			Paint(button, PALETTE.Green)
		end
	end

	--..API..--
	function view.SetFooter(footerData)
		if destroyed then return end
		footerData = type(footerData) == "table" and footerData or {}
		f.Pet.Text = string.format('Pets  <font color="%s">%s</font>', CASH_HEX, Escape(footerData.Pet or "$0/s"))
		f.Cucumber.Text = string.format('Cucumbers  <font color="%s">%s</font>', CASH_HEX, Escape(footerData.Cucumber or "$0/s"))
		f.Total.Text = string.format('Total  <font color="%s">%s</font>', CASH_HEX, Escape(footerData.Total or "$0/s"))
	end

	--.. everything a view model draws except the footer: SetCompact re-draws the held model with this, because
	--.. a later SetFooter (the Kind = "Totals" path) may already show newer totals than current.Footer
	local function Draw(vm)
		current = vm
		subtitle.Text = vm.Subtitle or ""
		local key = tostring(vm.Sort) .. "|" .. tostring(vm.Filter) .. "|" .. tostring(vm.ActionsEnabled)
		if toolbarKey ~= key then
			toolbarKey = key
			for mode, name in pairs(SORT_BUTTONS) do Paint(toolbar[name], mode == vm.Sort and PALETTE.On or PALETTE.Off) end
			for mode, name in pairs(FILTER_BUTTONS) do Paint(toolbar[name], mode == vm.Filter and PALETTE.On or PALETTE.Off) end
			for _, name in pairs(BEST_BUTTONS) do Paint(toolbar[name], vm.ActionsEnabled and PALETTE.Green or PALETTE.Grey) end
			if sortCycle then SetLabel(sortCycle, "SORT: " .. (SORT_WORDS[vm.Sort] or string.upper(tostring(vm.Sort)))) end
			if filterCycle then SetLabel(filterCycle, "SHOW: " .. (FILTER_WORDS[vm.Filter] or string.upper(tostring(vm.Filter)))) end
		end
		lockBanner.Text = vm.Banner and vm.Banner.Text or ""
		lockBanner.Visible = vm.Banner ~= nil and vm.Banner.Visible == true
		for i, slot in ipairs(slots) do
			local s = vm.Slots and vm.Slots[i]
			if s then
				UpdateSlot(slot, s)
			else
				slot.Button.Visible = false
				slot.Id = nil
			end
		end
		-- cards: the first `limit` display positions are materialised; later ones stay hidden until the grid grows
		local list = vm.Cards or {}
		local upto = math.min(#list, limit)
		local listed = {}
		for order, c in ipairs(list) do
			listed[c.Id] = true
			if order <= upto then
				UpdateCard(cards[c.Id] or NewCard(c.Id), c, order)
			else
				local entry = cards[c.Id]
				if entry then SetVisible(entry, false) end
			end
		end
		for id, entry in pairs(cards) do
			if not listed[id] then
				if vm.Known and vm.Known[id] then
					SetVisible(entry, false)
				else
					DropCard(entry)
				end
			end
		end
		empty.Text = vm.EmptyText or ""
		empty.Visible = vm.EmptyText ~= nil and vm.EmptyText ~= ""
		RenderDetails(vm.Details, vm.Loaded)
		if overlay and not vm.Details then view.ShowDetails(false) end
	end

	function view.Render(vm)
		if destroyed or type(vm) ~= "table" then return end
		Draw(vm)
		view.SetFooter(vm.Footer)
	end

	function view.SetStatus(text)
		status.Text = type(text) == "string" and text or ""
		status.Visible = type(text) == "string" and text ~= ""
	end

	function view.SetNextRoll(text)
		if detail.Id then d.NextRoll.Text = type(text) == "string" and text or "" end
	end

	function view.Feedback(ok)
		if ok or destroyed then return end
		Sound(ButtonFX and ButtonFX.FAIL_SOUND)
		if ButtonFX and d.EquipButton.Visible then ButtonFX.Flash(d.EquipButton, FAIL_FLASH, 0.55, 0.35) end
	end

	--.. compact: open / close the Details page (a no-op in the wide layout, where details always show)
	function view.ShowDetails(open)
		open = open == true and compact
		if overlay == open or destroyed then return end
		overlay = open
		UpdatePages()
		if open then
			MoveFocus(d.EquipButton.Visible and d.EquipButton or backButton)
		else
			local entry = detail.Id and cards[detail.Id]
			MoveFocus(entry and entry.Visible and entry.Button or nil)
		end
	end

	function view.FocusTarget(rosterEmpty)
		if compact and overlay then return d.EquipButton.Visible and d.EquipButton or backButton end
		if not compact and not rosterEmpty and slots[1] then return slots[1].Button end
		if current then
			for _, c in ipairs(current.Cards or {}) do
				local entry = cards[c.Id]
				if entry and entry.Visible then return entry.Button end
			end
		end
		if compact then return sortCycle end
		return slots[1] and slots[1].Button or nil
	end

	function view.OnSelect(fn) callbacks.Select = fn end
	function view.OnEquip(fn) callbacks.Equip = fn end
	function view.OnBest(fn) callbacks.Best = fn end
	function view.OnSort(fn) callbacks.Sort = fn end
	function view.OnFilter(fn) callbacks.Filter = fn end

	--..Compact (phone) layout..--
	--.. text caps follow the scale and the layout (S7): design x ResponsiveScale.Scale
	local function Rescale()
		if destroyed then return end
		local scale = CurrentScale()
		ApplyCaps(caps, compact, scale)
		for _, entry in pairs(cards) do ApplyCaps(entry.Caps, compact, scale) end
	end
	local function SetCompact(on)
		on = on == true
		if on == compact or destroyed then return end
		compact = on
		overlay = false
		ApplyLayout(layout, compact)
		for _, entry in pairs(cards) do
			ApplyLayout(entry.Layout, compact)
			entry.ChipKey = nil -- chips are refitted at the new text size / row width
			entry.ChipsHidden = nil
		end
		Rescale()
		panel:SetAttribute("Compact", compact)
		UpdatePages()
		-- re-draw at the new layout, footer untouched: it may already show a newer SetFooter than current.Footer
		if current then Draw(current) end
	end
	local function CheckCompact()
		if destroyed then return end
		local threshold = tonumber(panel:GetAttribute("CompactBelow")) or COMPACT_BELOW
		SetCompact(canCompact and responsive.Scale < threshold)
	end
	if canCompact then
		table.insert(connections, responsive:GetPropertyChangedSignal("Scale"):Connect(CheckCompact))
		table.insert(connections, panel:GetAttributeChangedSignal("CompactBelow"):Connect(CheckCompact))
	end
	if responsive ~= nil and responsive:IsA("UIScale") then
		table.insert(connections, responsive:GetPropertyChangedSignal("Scale"):Connect(Rescale))
	end
	-- closing the panel resets the compact page to the grid
	table.insert(connections, content:GetPropertyChangedSignal("Visible"):Connect(function()
		if not content.Visible and overlay then
			overlay = false
			UpdatePages()
		end
	end))

	--..Stepper: more cards near the end of the grid, lazy card previews, the turning detail preview..--
	local function NearWindow(button)
		local top = grid.AbsolutePosition.Y
		local bottom = top + grid.AbsoluteWindowSize.Y
		local y, h = button.AbsolutePosition.Y, button.AbsoluteSize.Y
		return y + h >= top - h and y <= bottom + h
	end
	local function GrowCards()
		if not (current and grid.Visible) then return end
		local list = current.Cards or {}
		if limit >= #list then return end
		local last = list[limit] and cards[list[limit].Id]
		-- the last materialised card is still more than a window below the visible part: nothing to add yet
		if last and last.Button.AbsolutePosition.Y > grid.AbsolutePosition.Y + 2 * grid.AbsoluteWindowSize.Y then return end
		local from = limit + 1
		limit = math.min(#list, limit + CARD_BATCH)
		for order = from, limit do
			local c = list[order]
			UpdateCard(cards[c.Id] or NewCard(c.Id), c, order)
		end
	end
	local function ScanPreviews()
		if not current then return end
		local list = current.Cards or {}
		local budget = PREVIEWS_PER_STEP
		for order = 1, math.min(#list, limit) do
			if budget <= 0 then break end
			local c = list[order]
			local entry = cards[c.Id]
			if entry and not entry.HasPreview and entry.Visible and NearWindow(entry.Button) then
				budget -= 1
				BuildPreview(entry.Button.Preview, Catalog, Mutations, c.Pet, c.Material, c.Mutations)
				entry.HasPreview = true
				entry.PreviewLook = c.Look
				builtCount += 1
			end
		end
		if builtCount > MAX_CARD_PREVIEWS then
			for _, entry in pairs(cards) do
				if builtCount <= MAX_CARD_PREVIEWS then break end
				if entry.HasPreview and (not entry.Visible or not NearWindow(entry.Button)) then DropPreview(entry) end
			end
		end
	end
	local scanClock = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if destroyed or not content.Visible then return end
		if detail.Model and detail.Model.Parent then
			detail.Yaw += dt * DETAIL_SPIN
			detail.Model:PivotTo(CFrame.Angles(0, detail.Yaw, 0))
		end
		scanClock += dt
		if scanClock < PREVIEW_SCAN then return end
		scanClock = 0
		GrowCards()
		ScanPreviews()
	end))

	function view.Destroy()
		if destroyed then return end
		destroyed = true
		for _, connection in ipairs(connections) do connection:Disconnect() end
		for _, entry in pairs(cards) do DropCard(entry) end
		for _, slot in ipairs(slots) do ClearPreview(slot.Button.Preview) end
		ClearPreview(d.Preview)
		table.clear(callbacks)
		-- put the authored (wide) layout back, so a view started later on the same panel captures it
		pcall(RestoreCaps, caps) -- the design caps too (S7)
		if compact then
			pcall(ApplyLayout, layout, false)
			compact, overlay = false, false
			pcall(UpdatePages)
			pcall(panel.SetAttribute, panel, "Compact", false)
		end
	end

	view.SetStatus(nil)
	panel:SetAttribute("Compact", false)
	CheckCompact()
	Rescale()
	return view
end

return View

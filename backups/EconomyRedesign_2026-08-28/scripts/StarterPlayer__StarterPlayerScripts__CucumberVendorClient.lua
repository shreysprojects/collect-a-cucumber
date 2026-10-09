--[[
	CucumberVendorClient
	The Cucumber Vendor UI, ported from Build a Restaurant's Seed Shop:
	same studded style (green header, brown body), same typed speech-bubble
	dialog with choices. Opens when the server fires OpenSellShop (the
	"Talk" prompt on the vendor). "Sell my cucumbers" opens the sell
	window; SELL ALL converts every cucumber into coins.

	All UI is designed in StarterGui.CucumberVendorUI (SellLayer /
	DialogChoices / SellPopups) plus the VendorDialogBubble billboard and the
	blur in Lighting.VendorBlur. This script only wires behavior and clones
	the ChoiceTemplate/CashPopup templates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("VendorRemotes")
local OpenSellShop = Remotes:WaitForChild("OpenSellShop")
local SellAll = Remotes:WaitForChild("SellAll")
local SellCarried = Remotes:WaitForChild("SellCarried")

local leaderstats = player:WaitForChild("leaderstats", 30)
local Orbs = leaderstats:WaitForChild("Cukes")

----------------------------------------------------------------------
-- Pet selling deps. Everything here degrades gracefully: if any of it is
-- missing the "sell a pet" dialogue option is simply not offered, and the
-- existing cucumber sale keeps working. An unguarded require or an untimed
-- WaitForChild here would take the whole vendor down with it.
----------------------------------------------------------------------
local PetSellValues, Network
do
	local ok, result = pcall(function()
		local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
		return {
			Values = require(ReplicatedStorage.Modules.PetSellValues);
			Net = ControllerLoader.GetController("Network");
		}
	end)
	if ok and result then
		PetSellValues = result.Values
		Network = result.Net
	else
		warn("[CucumberVendorClient] pet selling unavailable:", result)
	end
end

--.. TIMED wait: if SellPets is ever missing, only the pet option degrades.
local SellPetsFn = Remotes:WaitForChild("SellPets", 15)

--.. Inlined rather than requiring RarityController: that module runs a blocking
--.. Network:InvokeServer at module scope, so requiring it here could yield or error
--.. during init and kill the vendor. These are the end keypoints of its gradients.
local RARITY_COLORS = {
	Common    = Color3.fromRGB(206, 255, 198);
	Uncommon  = Color3.fromRGB(0, 207, 145);
	Rare      = Color3.fromRGB(0, 145, 255);
	Epic      = Color3.fromRGB(226, 0, 255);
	Legendary = Color3.fromRGB(255, 183, 0);
	Mythical  = Color3.fromRGB(25, 182, 255);
	Omega     = Color3.fromRGB(255, 0, 0);
	Special   = Color3.fromRGB(255, 0, 0);
}

local GREEN = Color3.fromRGB(78, 226, 52)
local DISABLED_GRAY = Color3.fromRGB(184, 178, 170)

local DESIGN_W, DESIGN_H = 560, 430

local function formatMoney(value)
	local text = tostring(value)
	while true do
		local updated, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = updated
		if count == 0 then break end
	end
	return text
end

----------------------------------------------------------------------
-- Sell window (designed in StarterGui.CucumberVendorUI)
----------------------------------------------------------------------
local gui = pg:WaitForChild("CucumberVendorUI")
local blur = Lighting:WaitForChild("VendorBlur")

local panel = gui:WaitForChild("SellLayer")
local windowRoot = panel:WaitForChild("SellWindow")
local windowScale = windowRoot:WaitForChild("UIScale")
local window = windowRoot:WaitForChild("Body")
local header = window:WaitForChild("Header")
local closeBtn = header:WaitForChild("Close")
local card = window:WaitForChild("Card")
local haveLbl = card:WaitForChild("Have")
local worthLbl = card:WaitForChild("Worth")
local sellBtn = window:WaitForChild("SellAll")
local sellLbl = sellBtn:WaitForChild("Label")

----------------------------------------------------------------------
-- Pet sell window forward declarations.
--
-- These MUST live above computeFit/applyFit. connectViewport() is called
-- unconditionally during script init and calls applyFit(), so every name
-- applyFit touches has to already be a local by then -- declaring them lower
-- down would make applyFit read a nil GLOBAL, throw, and halt the script
-- before the OpenSellShop connection at the bottom, killing the entire vendor
-- including cucumber selling.
----------------------------------------------------------------------
--.. Pet sell grid metrics. PET_W/PET_H/PET_COLS are RECOMPUTED on every open from the
--.. viewport (see petWindowMetrics) rather than fixed: a fixed 4-column 600x620 window
--.. has to scale to ~0.54 on a 375px-tall phone, which renders the 13px cell text at
--.. about 7px. Deriving the column count instead keeps cells at full size and simply
--.. shows fewer per row on small screens.
local PET_CELL_W, PET_CELL_H = 126, 158
local PET_PAD_X, PET_PAD_Y = 10, 10
local PET_PAD_L, PET_PAD_R = 8, 14      -- 14 right = 8px scrollbar + 6px gap
local PET_ROW_STRIDE = PET_CELL_H + PET_PAD_Y
local PET_SCROLL_PAD_TOP = 8
local PET_COLS = 4
local PET_W, PET_H = 600, 620

--.. mirrors MAX_SELL_BATCH in SellVendorServer. The server refuses to sell more than
--.. this in one call; capping here means the player is told, instead of the extras
--.. being silently dropped from a sale whose window then closes.
local PET_MAX_SELECT = 50

local petLayer, petScale, petScroll, petTotalLbl, petSellBtn, petWindow, petGrid
local rebuildPetList, setPetOpen, showCashPopup, showTextPopup
local petSelected = {}
local rebuildToken = 0
local petSelling = false

--.. Column count and window size are chosen so the grid renders at ~1:1 in the current
--.. viewport, which is what keeps the labels readable. Falls back to a desktop-ish
--.. guess before the camera exists.
local function petWindowMetrics()
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local chrome = 20 + PET_PAD_L + PET_PAD_R          -- window padding + scroll inset
	--.. SLACK is not cosmetic. Sizing the window to exactly fit N cells leaves zero
	--.. horizontal headroom, and UIGridLayout's wrap width is ambiguous by ~8px
	--.. (canvas width vs window width, which differ by ScrollBarThickness). At zero
	--.. slack that tie is decided by float rounding and the grid silently drops to
	--.. N-1 columns. 12px is comfortably more than the scrollbar.
	local SLACK = 12
	local budget = (vp.X - 80) - chrome - SLACK
	local cols = math.floor((budget + PET_PAD_X) / (PET_CELL_W + PET_PAD_X))
	cols = math.clamp(cols, 2, 4)
	local w = chrome + SLACK + cols * PET_CELL_W + (cols - 1) * PET_PAD_X
	local h = math.clamp(vp.Y - 80, 360, 620)
	return w, h, cols
end

--.. single owner for the blur: setOpen(false) used to kill it unconditionally, and
--.. startDialog calls setOpen(false) on every prompt trigger, so without this
--.. re-pressing Talk while the pet window is open would clear its blur.
local function updateBlur()
	blur.Enabled = panel.Visible or (petLayer ~= nil and petLayer.Visible)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
local function refresh()
	local count = Orbs.Value
	haveLbl.Text = "You have: " .. formatMoney(count) .. " Cucumbers"
	worthLbl.Text = "Worth: " .. formatMoney(count) .. " Coins"
	if count >= 1 then
		sellBtn.ImageColor3 = GREEN
		sellBtn.BackgroundColor3 = GREEN
		sellBtn.AutoButtonColor = true
		sellLbl.Text = "SELL ALL"
	else
		sellBtn.ImageColor3 = DISABLED_GRAY
		sellBtn.BackgroundColor3 = DISABLED_GRAY
		sellBtn.AutoButtonColor = false
		sellLbl.Text = "NOTHING TO SELL"
	end
end

----------------------------------------------------------------------
-- Responsive fit + open/close (same feel as the Seed Shop)
----------------------------------------------------------------------
local function computeFit()
	local cam = Workspace.CurrentCamera
	if not cam then return 1 end
	local vp = cam.ViewportSize
	return math.min(1, (vp.X - 40) / DESIGN_W, (vp.Y - 40) / DESIGN_H)
end

local function applyFit()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if panel.Visible then
		windowScale.Scale = computeFit()
	end
	if petLayer and petLayer.Visible and petScale then
		petScale.Scale = math.min(1, (vp.X - 40) / PET_W, (vp.Y - 40) / PET_H)
	end
end

local viewportConnection
local function connectViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local cam = Workspace.CurrentCamera
	if cam then
		viewportConnection = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyFit)
	end
	applyFit()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectViewport)
connectViewport()

local function setOpen(isOpen)
	if isOpen then
		refresh()
		panel.Visible = true
		updateBlur()
		local fit = computeFit()
		windowScale.Scale = fit * 0.9
		TweenService:Create(
			windowScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = fit }
		):Play()
	else
		panel.Visible = false
		updateBlur()
	end
end

----------------------------------------------------------------------
-- NPC dialog: typed greeting above the vendor's head + choices,
-- exactly like the Seed Shop vendor. Bubble/choice UI live in StarterGui.
----------------------------------------------------------------------
local npcModel = Workspace:WaitForChild("Points"):WaitForChild("Sell"):WaitForChild("Vendor")
local npcHead = npcModel:WaitForChild("Head")

--.. The "Talk" prompt otherwise floats over the dialogue the whole time it is open.
--.. Hidden CLIENT-SIDE only, so it stays visible to everyone else at the same vendor.
--.. Resolved on each call rather than cached: SellVendorServer creates the prompt at
--.. runtime (so it may not exist when this script first runs) and streaming can swap
--.. the rig out and back, which would leave a cached reference pointing at a corpse.
local function setTalkPrompt(shown)
	local root = npcModel:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		prompt.Enabled = shown
	end
end

local TYPE_SPEED = 0.035
local HOVER_GROW = 1.08 -- same hover grow as Build a Restaurant's UI buttons
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local bubble = pg:WaitForChild("VendorDialogBubble")
bubble.Adornee = npcHead
local bubbleLabel = bubble:WaitForChild("Label")

-- dialog choices live inside CucumberVendorUI.DialogChoices (shown via Visible)
local choicesLayer = gui:WaitForChild("DialogChoices")
local choiceFrame = choicesLayer:WaitForChild("ChoiceFrame")
local choiceTemplate = choiceFrame:WaitForChild("ChoiceTemplate")

--.. The choice column's geometry is authored in StarterGui: ChoiceFrame is anchored
--.. (0, 0.5) at 50%/60% and sized 0.48 x 0.40, the same numbers the original dialog
--.. used. A runtime override used to re-pin it to 8% of the width with a clamped
--.. pixel width, which pushed the options into the left-hand HUD and stretched each
--.. one into a full-width bar. Devices are handled by the AutoScale UIScale inside
--.. ChoiceFrame (driven by HudScaler off a 1920x1080 reference), so a phone shows
--.. the same proportions as desktop instead of a separate layout.

local dialogToken = 0

local function clearChoices()
	for _, c in ipairs(choiceFrame:GetChildren()) do
		if c:IsA("TextButton") and c ~= choiceTemplate then c:Destroy() end
	end
end

local function hideDialog()
	dialogToken += 1
	bubble.Enabled = false
	choicesLayer.Visible = false
	clearChoices()
	setTalkPrompt(true)
end

local function showChoices(options)
	clearChoices()
	choicesLayer.Visible = true
	for i, opt in ipairs(options) do
		local btn = choiceTemplate:Clone()
		btn.Name = "Choice" .. i
		btn.Text = "#" .. i .. ' ["' .. opt.text .. '"]'
		btn.LayoutOrder = i
		-- start fully faded; tween back to the template's designed look
		btn.TextTransparency = 1
		btn.TextStrokeTransparency = 1
		btn.BackgroundTransparency = 1
		btn.Visible = true
		btn.Parent = choiceFrame

		-- hover grow, same feel as the restaurant vendor's buttons
		local hoverScale = btn:WaitForChild("UIScale")
		btn.MouseEnter:Connect(function()
			TweenService:Create(hoverScale, HOVER_TWEEN, { Scale = HOVER_GROW }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(hoverScale, HOVER_TWEEN, { Scale = 1 }):Play()
		end)

		btn.Activated:Connect(function()
			if opt.action then opt.action() end
		end)

		task.delay(i * 0.07, function()
			TweenService:Create(btn, TweenInfo.new(0.2), {
				TextTransparency = 0,
				TextStrokeTransparency = 0.35,
				BackgroundTransparency = 0.5,
			}):Play()
		end)
	end
end

local function typeLine(text, onDone)
	dialogToken += 1
	local myToken = dialogToken
	choicesLayer.Visible = false
	clearChoices()
	bubble.Enabled = true
	bubbleLabel.Text = ""
	setTalkPrompt(false)
	task.spawn(function()
		for i = 1, #text do
			if myToken ~= dialogToken then return end
			bubbleLabel.Text = string.sub(text, 1, i)
			task.wait(TYPE_SPEED)
		end
		if myToken == dialogToken and onDone then
			onDone()
		end
	end)
end

-- showCashPopup is defined further down (after the popup GUI refs); it is
-- forward-declared in the pet-sell block near the top of this file so both the
-- cucumber sale and the pet sale can fire the "+cash" popup.

-- "I have a cucumber to sell" (2026-08-26, replaced the sell-all-Cukes
-- option): sells the cucumber on your ARM (the CarryService carry) at its
-- vault value. The server owns validation + payout and answers with the
-- coins so the gold "+cash" popup shows the real amount.
local function sellCarriedNow()
	local result
	local ok = pcall(function()
		result = SellCarried:InvokeServer()
	end)
	if ok and type(result) == "table" and result.Ok and result.Coins then
		showCashPopup(result.Coins)
		--.. SFX pass (2026-08-26): golden coin shower over the vendor for BIG
		--.. sales -- a client-created one-shot emitter (server Emit calls
		--.. don't render), cheap and self-cleaning
		if result.Coins > 50000 then
			pcall(function()
				local att = Instance.new("Attachment")
				att.WorldPosition = npcHead.Position + Vector3.new(0, 2.5, 0)
				att.Parent = Workspace.Terrain
				local pe = Instance.new("ParticleEmitter")
				pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				pe.Color = ColorSequence.new(Color3.fromRGB(255, 210, 70))
				pe.LightEmission = 0.7
				pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0)})
				pe.Lifetime = NumberRange.new(0.6, 1)
				pe.Speed = NumberRange.new(6, 10)
				pe.SpreadAngle = Vector2.new(70, 70)
				pe.Acceleration = Vector3.new(0, -22, 0)
				pe.Enabled = false
				pe.Parent = att
				pe:Emit(26)
				game:GetService("Debris"):AddItem(att, 2.2)
			end)
		end
	end
	hideDialog()
end

local function openPetSell()
	hideDialog()
	local event = gui:FindFirstChild("OpenNewPetSell")
	if event then
		event:Fire(true)
	else
		setPetOpen(true)
	end
end

--.. the pet option is only offered when everything it needs actually resolved
local petSellReady = (PetSellValues ~= nil and Network ~= nil and SellPetsFn ~= nil)

local mainChoices = {
	{ text = "I have a cucumber to sell", action = sellCarriedNow },
}
if petSellReady then
	mainChoices[#mainChoices + 1] = { text = "I would like to sell a pet", action = openPetSell }
end
mainChoices[#mainChoices + 1] = { text = "Nevermind", action = hideDialog }

local function startDialog()
	--.. reset BOTH windows. The prompt is re-triggerable from 9 studs, and the
	--.. ZIndex-2 dialogue buttons would otherwise sit under the pet window's opaque
	--.. ZIndex-4 backdrop while staying clickable -- one blind click would dump the
	--.. player's entire cucumber balance.
	setOpen(false)
	if setPetOpen then setPetOpen(false) end
	local event = gui:FindFirstChild("OpenNewPetSell")
	if event then event:Fire(false) end
	typeLine("Got some cucumbers?", function()
		showChoices(mainChoices)
	end)
end

-- auto-close the chat if the player walks away from the vendor
task.spawn(function()
	while true do
		task.wait(0.3)
		if bubble.Enabled or choicesLayer.Visible or (petLayer and petLayer.Visible) then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp or (hrp.Position - npcHead.Position).Magnitude > 28 then
				hideDialog()
				if setPetOpen then setPetOpen(false) end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Cartoony "+cash" gold popup (clones CucumberVendorUI.SellPopups.CashPopup)
----------------------------------------------------------------------
local popupGui = gui:WaitForChild("SellPopups")
local popupTemplate = popupGui:WaitForChild("CashPopup")

--.. must sit above PetSellLayer (ZIndex 4). SellPopups is authored at ZIndex 3 and
--.. CashPopup at 10, but CucumberVendorUI uses Sibling ZIndexBehavior, so the whole
--.. SellPopups subtree renders inside its parent's ZIndex-3 slot -- the "+N Coins"
--.. popup would otherwise animate its full 1.1s life behind the pet window's dark
--.. backdrop. Safe for the cucumber flow: 5 is still above SellLayer (1) and
--.. DialogChoices (2).
popupGui.ZIndex = 5

--.. ONE spawner for every floating popup. The pet window closes on a successful sale,
--.. so the sale summary cannot live on petTotalLbl any more -- that label dies with the
--.. window. SellPopups is a sibling layer in the same ScreenGui that setPetOpen never
--.. touches, so a popup spawned here outlives the window it was fired from.
local function spawnPopup(text, opts)
	opts = opts or {}
	local jitter = math.random(-35, 35) / 1000 -- tiny horizontal pickaxeer so repeats don't stack
	local startY = opts.StartY or 0.52
	local peak = opts.PeakScale or 1.15
	local rest = opts.RestScale or 1

	local holder = popupTemplate:Clone()
	holder.Position = UDim2.fromScale(0.5 + jitter, startY)
	holder.Visible = true

	local scale = holder:WaitForChild("UIScale")
	scale.Scale = 0.35 * rest

	local lbl = holder:WaitForChild("Label")
	lbl.Text = text
	local stroke = lbl:WaitForChild("UIStroke")

	--.. the authored Label carries a gold UIGradient that repaints TextColor3, so a
	--.. non-payout line has to disable it or it renders as gold "you got paid" text.
	if opts.TextColor then
		local grad = lbl:FindFirstChildOfClass("UIGradient")
		if grad then grad.Enabled = false end
		lbl.TextColor3 = opts.TextColor
	end

	holder.Parent = popupGui

	-- pop in with an overshoot, then settle back
	TweenService:Create(scale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = peak }):Play()
	task.delay(0.26, function()
		if holder.Parent then
			TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = rest }):Play()
		end
	end)

	-- float upward
	TweenService:Create(holder, TweenInfo.new(1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5 + jitter, startY - 0.22),
	}):Play()

	-- cartoony rotation wiggle
	TweenService:Create(lbl, TweenInfo.new(0.95, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = 7 }):Play()

	-- fade out near the end, then clean up
	task.delay(0.62, function()
		if not holder.Parent then return end
		local fade = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(lbl, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)
	task.delay(1.1, function()
		holder:Destroy()
	end)
end

function showCashPopup(amount)  -- assigns to the forward-declared local above
	spawnPopup("+" .. formatMoney(amount) .. " Coins")
end

--.. secondary line for non-payout news. Starts lower and is fired on a short delay by
--.. the caller so it never collides with the coin popup climbing from 0.52.
function showTextPopup(text, color)
	spawnPopup(text, {
		StartY = 0.62;
		TextColor = color or Color3.fromRGB(255, 220, 150);
		PeakScale = 0.82;
		RestScale = 0.72;
	})
end

----------------------------------------------------------------------
-- Pet sell window (built at runtime)
--
-- Parented as a Frame INSIDE the authored CucumberVendorUI ScreenGui, never as
-- a new ScreenGui: EggController.UiController and StarterPortalClient both hook
-- PlayerGui.ChildAdded and force Enabled = false on every ScreenGui during egg
-- hatches and portal transitions, so a runtime ScreenGui created while either is
-- in flight is silently disabled forever. As a Frame it inherits the vendor GUI's
-- correct DisplayOrder 30 / ResetOnSpawn false / IgnoreGuiInset true, and ZIndex 4
-- sits cleanly above SellLayer (1), DialogChoices (2) and SellPopups (raised to 5).
----------------------------------------------------------------------
if petSellReady then
	local ROW_BG = Color3.fromRGB(96, 63, 41)
	local BODY_BROWN = Color3.fromRGB(128, 84, 54)

	petLayer = Instance.new("Frame")
	petLayer.Name = "PetSellLayer"
	petLayer.Size = UDim2.fromScale(1, 1)
	petLayer.BackgroundTransparency = 1
	petLayer.Visible = false
	petLayer.ZIndex = 4
	petLayer.Parent = gui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(7, 10, 6)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 4
	backdrop.Parent = petLayer

	petWindow = Instance.new("Frame")
	petWindow.Name = "Window"
	petWindow.Size = UDim2.fromOffset(PET_W, PET_H)
	petWindow.Position = UDim2.fromScale(0.5, 0.5)
	petWindow.AnchorPoint = Vector2.new(0.5, 0.5)
	petWindow.BackgroundColor3 = BODY_BROWN
	petWindow.BorderSizePixel = 0
	petWindow.ZIndex = 5
	petWindow.Parent = petLayer

	petScale = Instance.new("UIScale")
	petScale.Parent = petWindow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = petWindow

	local head = Instance.new("TextLabel")
	head.Name = "Header"
	head.Size = UDim2.new(1, 0, 0, 44)
	head.BackgroundColor3 = GREEN
	head.BorderSizePixel = 0
	head.Text = "SELL PETS"
	head.TextColor3 = Color3.fromRGB(255, 255, 255)
	head.TextSize = 24
	head.Font = Enum.Font.GothamBold
	head.ZIndex = 6
	head.Parent = petWindow

	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(0, 10)
	headCorner.Parent = head

	local closeBtnPet = Instance.new("TextButton")
	closeBtnPet.Name = "Close"
	closeBtnPet.AnchorPoint = Vector2.new(1, 0)
	closeBtnPet.Position = UDim2.new(1, -6, 0, 6)
	closeBtnPet.Size = UDim2.fromOffset(32, 32)
	closeBtnPet.BackgroundColor3 = Color3.fromRGB(200, 60, 50)
	closeBtnPet.BorderSizePixel = 0
	closeBtnPet.Text = "X"
	closeBtnPet.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtnPet.TextSize = 20
	closeBtnPet.Font = Enum.Font.GothamBold
	closeBtnPet.ZIndex = 7
	closeBtnPet.Parent = head

	petScroll = Instance.new("ScrollingFrame")
	petScroll.Name = "PetList"
	petScroll.Size = UDim2.new(1, -20, 1, -150)
	petScroll.Position = UDim2.fromOffset(10, 54)
	petScroll.BackgroundColor3 = Color3.fromRGB(74, 48, 31)
	petScroll.BackgroundTransparency = 0.35
	petScroll.BorderSizePixel = 0
	petScroll.CanvasSize = UDim2.new()
	petScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	petScroll.ScrollBarThickness = 8
	petScroll.ZIndex = 6
	petScroll.Parent = petWindow

	------------------------------------------------------------------
	-- Grid. Column count is set per open by applyPetMetrics() rather than hardcoded,
	-- so a narrow viewport gets fewer columns at full cell size instead of four
	-- columns shrunk to unreadable. Pure OFFSET CellSize like every other grid in
	-- this place (Pets 112/30-35/7, Shop 255x213/9-12/3, Index 200x173/14/4) --
	-- Scale on X is a verified trap: UDim2.new(0.25,0,0,H) with 10px padding
	-- resolves wider than a quarter of the usable width and silently drops to 3.
	------------------------------------------------------------------
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingLeft = UDim.new(0, PET_PAD_L)
	gridPad.PaddingRight = UDim.new(0, PET_PAD_R)
	gridPad.PaddingTop = UDim.new(0, PET_SCROLL_PAD_TOP)
	gridPad.PaddingBottom = UDim.new(0, 8)
	gridPad.Parent = petScroll

	petGrid = Instance.new("UIGridLayout")
	petGrid.CellSize = UDim2.fromOffset(PET_CELL_W, PET_CELL_H)
	petGrid.CellPadding = UDim2.fromOffset(PET_PAD_X, PET_PAD_Y)
	petGrid.FillDirection = Enum.FillDirection.Horizontal
	petGrid.FillDirectionMaxCells = PET_COLS
	petGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	petGrid.VerticalAlignment = Enum.VerticalAlignment.Top
	petGrid.SortOrder = Enum.SortOrder.LayoutOrder
	petGrid.StartCorner = Enum.StartCorner.TopLeft
	petGrid.Parent = petScroll

	--.. petScroll keeps its default ClipsDescendants = true. Do NOT turn it off to let
	--.. the star badge overhang the way the inventory tile does -- that would let cells
	--.. render outside the window. The badge is nudged inward instead.

	petTotalLbl = Instance.new("TextLabel")
	petTotalLbl.Name = "Total"
	petTotalLbl.Size = UDim2.new(1, -20, 0, 28)
	petTotalLbl.Position = UDim2.new(0, 10, 1, -92)
	petTotalLbl.BackgroundTransparency = 1
	petTotalLbl.Text = "Selected: 0  -  0 Coins"
	petTotalLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	petTotalLbl.TextSize = 18
	petTotalLbl.Font = Enum.Font.GothamBold
	petTotalLbl.TextXAlignment = Enum.TextXAlignment.Left
	petTotalLbl.ZIndex = 6
	petTotalLbl.Parent = petWindow

	petSellBtn = Instance.new("TextButton")
	petSellBtn.Name = "SellSelected"
	petSellBtn.Size = UDim2.new(1, -20, 0, 46)
	petSellBtn.Position = UDim2.new(0, 10, 1, -56)
	petSellBtn.BackgroundColor3 = DISABLED_GRAY
	petSellBtn.BorderSizePixel = 0
	petSellBtn.Text = "SELL"
	petSellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	petSellBtn.TextSize = 22
	petSellBtn.Font = Enum.Font.GothamBold
	petSellBtn.AutoButtonColor = false
	petSellBtn.ZIndex = 6
	petSellBtn.Parent = petWindow

	local sellCorner = Instance.new("UICorner")
	sellCorner.CornerRadius = UDim.new(0, 8)
	sellCorner.Parent = petSellBtn

	------------------------------------------------------------------
	-- responsive sizing: pick the column count and window size that render the grid
	-- at ~1:1 in the current viewport, then let applyFit handle any residual scale.
	------------------------------------------------------------------
	local function applyPetMetrics()
		local w, h, cols = petWindowMetrics()
		PET_W, PET_H, PET_COLS = w, h, cols
		petWindow.Size = UDim2.fromOffset(w, h)
		if petGrid then petGrid.FillDirectionMaxCells = cols end
	end

	------------------------------------------------------------------
	-- selection total
	------------------------------------------------------------------
	local function countSelected()
		local sum, count = 0, 0
		for _, coins in pairs(petSelected) do
			sum += coins
			count += 1
		end
		return sum, count
	end

	local function updatePetTotal()
		local sum, count = countSelected()
		petTotalLbl.Text = string.format("Selected: %d  -  %s Coins", count, formatMoney(sum))
		petSellBtn.BackgroundColor3 = count > 0 and GREEN or DISABLED_GRAY
		petSellBtn.AutoButtonColor = count > 0
	end

	------------------------------------------------------------------
	-- Pet previews: index-range VIRTUALIZATION, not Visible-culling.
	--
	-- The Pet Inventory culls by toggling ViewportFrame.Visible, which measures as
	-- reclaiming ~0% of the memory -- it saves render work, not RAM. Pet storage is
	-- effectively unbounded ("+10 Pet Inventory" is a repeatable, persisted developer
	-- product), so this grid CREATES and DESTROYS previews by visible index range
	-- instead: bounded RAM regardless of inventory size, and exactly zero while the
	-- window is closed.
	--
	-- Release uses a WIDER margin than acquire. With one shared margin, scrolling a
	-- single row evicts a full row of Model3Ds and immediately rebuilds another --
	-- each build clones a model averaging ~52 parts. The asymmetry makes a one-row
	-- scroll a no-op and only sheds previews once they are well out of view.
	------------------------------------------------------------------
	local Module3D, PetAssets
	do
		--.. MUST be the Shared copy: ControllerLoader's older Module3D writes the
		--.. viewport size in raw pixels and petWindow has a UIScale, so that copy
		--.. renders the pet at scale^2. Guarded so a failure only costs the previews.
		local ok, m = pcall(function() return require(ReplicatedStorage.Shared.Module3D) end)
		if ok then Module3D = m else warn("[CucumberVendorClient] pet previews unavailable:", m) end
		--.. FindFirstChild, never WaitForChild: this runs at script init, above the
		--.. OpenSellShop connection, so a yield here would stall the whole vendor
		--.. (including the cucumber sale). Re-resolved lazily on first use instead.
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		PetAssets = assets and assets:FindFirstChild("Pets")
	end

	local ACQUIRE_MARGIN_ROWS = 1
	local RELEASE_MARGIN_ROWS = 3
	local liveVp = {}      -- [index] = Model3D
	local cellByIndex = {} -- [index] = { Host = ImageLabel; PetName = string }
	local vpGen = 0

	local function releaseViewport(i)
		local m3d = liveVp[i]
		if not m3d then return end
		liveVp[i] = nil
		--.. Model3D:Destroy frees the AdornFrame AND disconnects the Frame.Changed
		--.. connection Attach3D left on the host. Destroying the host alone leaks it.
		pcall(function() m3d:Destroy() end)
	end

	local function acquireViewport(i)
		if liveVp[i] or not Module3D then return end
		local entry = cellByIndex[i]
		if not (entry and entry.Host and entry.Host.Parent) then return end

		if not PetAssets then
			local a = ReplicatedStorage:FindFirstChild("Assets")
			PetAssets = a and a:FindFirstChild("Pets")
			if not PetAssets then return end
		end
		--.. FindFirstChild, never the bracket form: names like "King Cuke" contain
		--.. spaces and an unknown pet must degrade rather than throw.
		local src = PetAssets:FindFirstChild(entry.PetName)
		if not src then return end

		local ok, m3d = pcall(function()
			return Module3D:Attach3D(entry.Host, src:Clone())
		end)
		if not ok or not m3d then return end

		--.. CALL ORDER IS LOAD-BEARING. DistanceBack is cached at construction from the
		--.. camera's default FieldOfView of 70 and is only recomputed inside
		--.. SetDepthMultiplier and the FIRST SetCFrame -- setting FOV without a trailing
		--.. SetCFrame leaves the pet framed for a 70-degree camera. Same 1.1 / 5 / 265
		--.. recipe every other pet viewport in this game uses. Deliberately no lighting:
		--.. no pet-inventory viewport sets any, and doing so would light these differently.
		m3d:SetDepthMultiplier(1.1)
		if m3d.CurrentCamera then
			m3d.CurrentCamera.FieldOfView = 5
		end
		m3d:SetCFrame(CFrame.Angles(math.rad(0), math.rad(265), 0))

		--.. the Viewport3D template ships ZIndex 10 and Shared.Module3D does not reset
		--.. it. Force it into this cell's ladder: cell 7 / labels + host 8 / viewport 9 /
		--.. star badge 10 / stars 11-13.
		m3d.ZIndex = 9
		m3d.Visible = true
		entry.Host.Image = ""
		liveVp[i] = m3d
	end

	--.. UIGridLayout geometry is deterministic, so the visible range is exact and this
	--.. never has to read AbsolutePosition (which is why it needs no settle passes).
	local function rangeFor(marginRows)
		local s = (petScale and petScale.Scale > 0) and petScale.Scale or 1
		local top = petScroll.CanvasPosition.Y
		--.. CanvasPosition and the grid offsets are UNSCALED canvas units but
		--.. AbsoluteWindowSize is already multiplied by petScale -- divide it back out.
		local height = petScroll.AbsoluteWindowSize.Y / s
		if height <= 0 then height = PET_H end
		local firstRow = math.floor((top - PET_SCROLL_PAD_TOP) / PET_ROW_STRIDE) - marginRows
		local lastRow = math.floor((top + height - PET_SCROLL_PAD_TOP) / PET_ROW_STRIDE) + marginRows
		if firstRow < 0 then firstRow = 0 end
		if lastRow < firstRow then lastRow = firstRow end
		return firstRow * PET_COLS + 1, (lastRow + 1) * PET_COLS
	end

	local function refreshViewports()
		if not (petLayer and petLayer.Visible and petScroll.Parent) then
			for i in pairs(liveVp) do releaseViewport(i) end
			return
		end

		vpGen += 1
		local myGen = vpGen

		local rlo, rhi = rangeFor(RELEASE_MARGIN_ROWS)
		for i in pairs(liveVp) do
			if i < rlo or i > rhi then releaseViewport(i) end
		end

		--.. chunked: up to a few dozen Attach3D calls in one frame is a visible stall on
		--.. first open (each clones a ~52-part model). Six per frame is imperceptible and
		--.. matches the Pet Index's precedent. The generation guard matters because the
		--.. task.wait() makes this re-entrant -- two property signals also drive it.
		local alo, ahi = rangeFor(ACQUIRE_MARGIN_ROWS)
		local n = 0
		for i = alo, ahi do
			if cellByIndex[i] then
				acquireViewport(i)
				n += 1
				if n % 6 == 0 then
					task.wait()
					if myGen ~= vpGen or not (petLayer and petLayer.Visible) then return end
				end
			end
		end
	end

	local vpQueued = false
	local function queueViewports()
		if vpQueued then return end
		vpQueued = true
		task.delay(0.06, function()
			vpQueued = false
			refreshViewports()
		end)
	end

	petScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(queueViewports)
	--.. also drives the FIRST fill: AbsoluteWindowSize is still 0 on the frame the layer
	--.. becomes visible, so this signal is what populates the grid initially.
	petScroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(queueViewports)

	--.. MANDATORY teardown. liveVp/cellByIndex are strong-keyed: one stale Model3D left
	--.. reachable pins its ViewportFrame and its cloned model forever, and this window
	--.. reopens on every vendor interaction.
	local function clearPetRows()
		for i in pairs(liveVp) do releaseViewport(i) end
		table.clear(liveVp)
		table.clear(cellByIndex)
		for _, c in ipairs(petScroll:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
	end

	------------------------------------------------------------------
	-- Equipped star badge, cloned from the authored Pet Inventory tile so the mark is
	-- identical. It is THREE stacked ImageLabels with three different asset ids, not
	-- one star -- reproducing only the largest looks visibly wrong.
	------------------------------------------------------------------
	local STAR_SRC do
		local ok, src = pcall(function()
			return game:GetService("StarterGui")
				.Display.Frame.Frames.Pets.PetsScroll.ScrollingFrame.Template.Equipped
		end)
		if ok then STAR_SRC = src end
	end

	--.. literal fallback if a future Figma re-import renames that path
	local STAR_LAYERS = {
		{Name = "Star 259"; Image = "rbxassetid://118179801776799"; Px = 37; X = -21; Y = -23; Z = 11};
		{Name = "Star 258"; Image = "rbxassetid://81863340870986";  Px = 46; X =  -5; Y = -26; Z = 12};
		{Name = "Star 257"; Image = "rbxassetid://115726567975473"; Px = 60; X = -28; Y = -28; Z = 13};
	}

	--.. deliberately NOT ICON_PX/112. At that ratio the 60px star renders 51px over a
	--.. 96px preview and swallows the whole upper-left quadrant. In the inventory the
	--.. cluster hangs OUTSIDE the tile (negative offsets, unclipped scroll) so it reads
	--.. as a corner ornament; here it has to sit inside a clipped cell, so it is scaled
	--.. to read as a badge ON the pet rather than a cover over it.
	local STAR_SCALE = 0.5
	local STAR_NUDGE = math.ceil(28 * STAR_SCALE)

	local function addEquippedStar(cell, iconX, iconY)
		local badge
		if STAR_SRC then
			badge = STAR_SRC:Clone()
			local s = Instance.new("UIScale")
			s.Scale = STAR_SCALE
			s.Parent = badge
			for _, img in ipairs(badge:GetChildren()) do
				if img:IsA("ImageLabel") then
					--.. rebase the authored 14/15/16 onto 11/12/13 so the cluster sits in
					--.. this cell's ladder and cannot interleave with the vendor chrome.
					img.ZIndex = img.ZIndex - 3
				end
			end
		else
			badge = Instance.new("Frame")
			for _, L in ipairs(STAR_LAYERS) do
				local px = math.floor(L.Px * STAR_SCALE + 0.5)
				local img = Instance.new("ImageLabel")
				img.Name = L.Name
				img.Image = L.Image
				img.ScaleType = Enum.ScaleType.Fit
				img.Size = UDim2.fromOffset(px, px)
				img.Position = UDim2.fromOffset(
					math.floor(L.X * STAR_SCALE + 0.5),
					math.floor(L.Y * STAR_SCALE + 0.5)
				)
				img.BackgroundTransparency = 1
				img.BorderSizePixel = 0
				img.ZIndex = L.Z
				img.Parent = badge
			end
		end

		badge.Name = "Equipped"
		badge.Size = UDim2.fromOffset(112, 112)
		badge.BackgroundTransparency = 1
		badge.BorderSizePixel = 0
		badge.ClipsDescendants = false
		badge.ZIndex = 10 -- sibling of the icon host (8): draws over the viewport
		badge.Visible = true
		--.. the authored stars sit at negative offsets so the cluster overhangs its
		--.. tile. petScroll clips (and must keep clipping), so push the badge in by the
		--.. scaled overhang: the cluster then lands on the preview's top-left corner
		--.. with every layer inside the cell.
		badge.Position = UDim2.fromOffset(iconX + STAR_NUDGE, iconY + STAR_NUDGE)
		badge.Parent = cell
		return badge
	end

	------------------------------------------------------------------
	-- list build
	------------------------------------------------------------------
	local petDict --.. cached after first success

	rebuildPetList = function()
		rebuildToken += 1
		local myToken = rebuildToken

		local ok, UserData = pcall(function() return Network:InvokeServer("GetUserData") end)
		if not petDict then
			local ok2, d = pcall(function()
				return Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})
			end)
			if ok2 and type(d) == "table" then petDict = d end
		end

		--.. generation guard: the invokes above yield, so two overlapping rebuilds
		--.. (fast close+reopen, or sale+reopen) would otherwise each clear and each
		--.. append, rendering every pet twice with two rows writing to one selection
		--.. set. Same pattern as dialogToken.
		if myToken ~= rebuildToken then return end

		--.. destroys every Model3D and drops every Lua reference to one. Destroying the
		--.. cells alone would leak a cloned pet model plus a Frame.Changed connection
		--.. per cell on every reopen and every sale.
		clearPetRows()

		if not ok or type(UserData) ~= "table" or type(UserData.PetData) ~= "table" then
			petTotalLbl.Text = "Loading..."
			return
		end

		local list = {}
		for Id, Pet in pairs(UserData.PetData) do
			--.. MANDATORY guard: PetData holds the non-pet key "Unlocked", a
			--.. "|"-separated string. Without this you build a garbage row and then
			--.. error indexing a string.
			if Id ~= "Unlocked" and type(Pet) == "table" and Pet.Name then
				local Def = petDict and petDict[Pet.Name]
				--.. the SAME call the server makes, from the SAME module
				local Coins, Rarity = PetSellValues.GetValue(Pet, Def)
				list[#list + 1] = {
					Id = Id; Name = Pet.Name; Coins = Coins; Rarity = Rarity;
					Craft = Pet.Craft;
					Equipped = Pet.Equipped and true or false;
				}
			end
		end

		table.sort(list, function(a, b)
			if a.Coins ~= b.Coins then return a.Coins > b.Coins end
			return a.Name < b.Name
		end)

		--.. drop selections for pets that no longer exist
		local live = {}
		for _, e in ipairs(list) do live[e.Id] = true end
		for id in pairs(petSelected) do
			if not live[id] then petSelected[id] = nil end
		end

		--.. cell interior: name / rarity / coins stacked on top, pet preview beneath.
		local ICON_PX = 92
		local ICON_X = math.floor((PET_CELL_W - ICON_PX) / 2)
		local ICON_Y = 55 -- clears the three label rows

		for i, e in ipairs(list) do
			--.. UIGridLayout drives Size; only LayoutOrder and the interior matter here.
			local cell = Instance.new("TextButton")
			cell.Name = "PetCell"
			cell.LayoutOrder = i
			cell.BackgroundColor3 = ROW_BG
			cell.BorderSizePixel = 0
			cell.Text = ""
			cell.AutoButtonColor = false
			cell.ClipsDescendants = false
			cell.ZIndex = 7

			local cellCorner = Instance.new("UICorner")
			cellCorner.CornerRadius = UDim.new(0, 6)
			cellCorner.Parent = cell

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "PetTitle"
			nameLbl.Size = UDim2.new(1, -8, 0, 17)
			nameLbl.Position = UDim2.fromOffset(4, 5)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 13
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.ZIndex = 8
			--.. no text tags any more: [LOCKED] went with the lock system and [EQUIPPED]
			--.. is now the star badge sitting on the pet.
			nameLbl.Text = e.Name .. (e.Craft == "Golden" and " (Golden)" or "")
			nameLbl.Parent = cell

			local rarityLbl = Instance.new("TextLabel")
			rarityLbl.Name = "Rarity"
			rarityLbl.Size = UDim2.new(1, -8, 0, 14)
			rarityLbl.Position = UDim2.fromOffset(4, 22)
			rarityLbl.BackgroundTransparency = 1
			rarityLbl.Font = Enum.Font.Gotham
			rarityLbl.TextSize = 12
			rarityLbl.TextTruncate = Enum.TextTruncate.AtEnd
			rarityLbl.TextColor3 = RARITY_COLORS[e.Rarity] or Color3.fromRGB(220, 220, 220)
			rarityLbl.TextXAlignment = Enum.TextXAlignment.Center
			rarityLbl.Text = e.Rarity
			rarityLbl.ZIndex = 8
			rarityLbl.Parent = cell

			local valueLbl = Instance.new("TextLabel")
			valueLbl.Name = "Value"
			valueLbl.Size = UDim2.new(1, -8, 0, 15)
			valueLbl.Position = UDim2.fromOffset(4, 37)
			valueLbl.BackgroundTransparency = 1
			valueLbl.Font = Enum.Font.GothamBold
			valueLbl.TextSize = 13
			valueLbl.TextTruncate = Enum.TextTruncate.AtEnd
			valueLbl.TextColor3 = Color3.fromRGB(255, 226, 92)
			valueLbl.TextXAlignment = Enum.TextXAlignment.Center
			valueLbl.Text = formatMoney(e.Coins) .. " Coins"
			valueLbl.ZIndex = 8
			valueLbl.Parent = cell

			--.. viewport HOST, beneath the labels. Module3D fits a centred square to
			--.. min(AbsoluteSize), so a square host renders the pet host-sized. The 3D
			--.. model is attached LAZILY by refreshViewports, never here.
			local iconHost = Instance.new("ImageLabel")
			iconHost.Name = "Icon"
			iconHost.Image = ""
			iconHost.Size = UDim2.fromOffset(ICON_PX, ICON_PX)
			iconHost.Position = UDim2.fromOffset(ICON_X, ICON_Y)
			iconHost.BackgroundTransparency = 1
			iconHost.BorderSizePixel = 0
			iconHost.ClipsDescendants = true
			iconHost.ZIndex = 8
			iconHost.Parent = cell

			cell.Parent = petScroll
			cellByIndex[i] = { Host = iconHost; PetName = e.Name; }

			if e.Equipped then
				--.. equipped pets are refused server-side, so deliberately no Activated
				--.. connection: unsellable AND unselectable. Dimmed so it reads as
				--.. disabled, with the Pet Inventory's own star badge on the pet.
				cell.BackgroundTransparency = 0.7
				addEquippedStar(cell, ICON_X, ICON_Y)
			else
				cell.BackgroundColor3 = petSelected[e.Id] and GREEN or ROW_BG
				cell.Activated:Connect(function()
					if petSelected[e.Id] then
						petSelected[e.Id] = nil
					else
						--.. hard cap mirroring the server's MAX_SELL_BATCH. Without it the
						--.. server sells the first 50 and silently drops the rest, and the
						--.. window closes before the player could notice.
						local _, count = countSelected()
						if count >= PET_MAX_SELECT then
							petTotalLbl.Text = string.format(
								"You can sell %d pets at a time", PET_MAX_SELECT)
							return
						end
						petSelected[e.Id] = e.Coins
					end
					cell.BackgroundColor3 = petSelected[e.Id] and GREEN or ROW_BG
					updatePetTotal()
				end)
			end
		end

		if #list == 0 then
			--.. must come AFTER the loop: updatePetTotal used to overwrite this
			--.. immediately, so the empty state never rendered.
			petSellBtn.BackgroundColor3 = DISABLED_GRAY
			petSellBtn.AutoButtonColor = false
			petTotalLbl.Text = "You have no pets to sell"
		else
			updatePetTotal()
		end

		--.. fill the visible previews. The first open fires before petScroll has
		--.. resolved AbsoluteWindowSize, so re-run once layout settles.
		refreshViewports()
		task.defer(refreshViewports)
	end

	------------------------------------------------------------------
	-- open / close
	------------------------------------------------------------------
	setPetOpen = function(isOpen)
		if not petLayer then return end
		petLayer.Visible = isOpen
		if isOpen then
			petSelected = {}
			applyPetMetrics() --.. column count + window size for the current viewport
			applyFit()
			rebuildPetList()
		else
			--.. bump the generation so a rebuild still yielding inside its InvokeServer
			--.. cannot append cells -- and spin up 3D previews -- into a window the
			--.. player already closed.
			rebuildToken += 1
			--.. hard teardown: every Model3D destroyed, every reference dropped. A closed
			--.. window costs zero preview memory however often it is reopened.
			clearPetRows()
			petSelected = {}
			updatePetTotal()
		end
		updateBlur()
	end

	--.. re-flow the grid when the window is resized while open
	do
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if petLayer and petLayer.Visible then
					local _, _, cols = petWindowMetrics()
					local changed = (cols ~= PET_COLS)
					applyPetMetrics()
					applyFit()
					--.. only a column change alters which index sits in which row, so a
					--.. plain viewport resize just re-ranges instead of rebuilding.
					if changed then rebuildPetList() else queueViewports() end
				end
			end)
		end
	end

	closeBtnPet.Activated:Connect(function()
		setPetOpen(false)
	end)

	------------------------------------------------------------------
	-- sell
	------------------------------------------------------------------
	petSellBtn.Activated:Connect(function()
		if petSelling or not SellPetsFn then return end

		local ids = {}
		for id in pairs(petSelected) do ids[#ids + 1] = id end
		if #ids == 0 then return end

		petSelling = true
		petSellBtn.AutoButtonColor = false
		--.. send ONLY the ids. The server recomputes every price itself.
		local ok, res = pcall(function() return SellPetsFn:InvokeServer(ids) end)
		petSelling = false

		if ok and type(res) == "table" and res.Ok then
			--.. close FIRST, then popup. setPetOpen(false) tears down every cell and
			--.. every Model3D; the popups write into SellPopups, a sibling layer
			--.. setPetOpen never touches, so they outlive the window that fired them.
			setPetOpen(false)
			showCashPopup(res.Coins)
			--.. the sale summary used to live on petTotalLbl, which now dies with the
			--.. window, so it becomes a second floating line. Wording stays neutral: the
			--.. server counts a pet as skipped if it is equipped OR no longer owned
			--.. (traded, evolved, or already sold by a racing click), so naming only
			--.. "equipped" would be wrong in the other cases.
			if res.Skipped and res.Skipped > 0 then
				local sold, skipped = res.Sold, res.Skipped
				task.delay(0.22, function()
					showTextPopup(string.format(
						"Sold %d - %d skipped (equipped or no longer owned)", sold, skipped))
				end)
			end
		else
			local reason = (ok and type(res) == "table" and res.Reason) or nil
			petSelected = {}
			rebuildPetList() --.. resync from the server, never optimistically remove cells
			if reason == "IN_TRADE" then
				petTotalLbl.Text = "Finish your trade first"
			elseif reason == "NONE_VALID" then
				petTotalLbl.Text = "Those pets can't be sold (equipped)"
			elseif reason == "BUSY" then
				petTotalLbl.Text = "Slow down!"
			else
				petTotalLbl.Text = "Sale failed - try again"
			end
		end
	end)
end

OpenSellShop.OnClientEvent:Connect(startDialog)

closeBtn.Activated:Connect(function()
	setOpen(false)
end)

sellBtn.Activated:Connect(function()
	local amount = Orbs.Value
	if amount >= 1 then
		SellAll:FireServer()
		setOpen(false)          -- close the sell window
		showCashPopup(amount)   -- gold "+cash" popup floats up
	end
end)

Orbs.Changed:Connect(function()
	if panel.Visible then
		refresh()
	end
end)

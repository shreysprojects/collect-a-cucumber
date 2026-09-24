--[[---------------------------------------DESCRIPTION------------------------------------------
	Builds the Rebirth and Ascend panels under ServerStorage.Assets.UserInterfaces.HUD in the
	"Manage" look of the New Map Cucumber Game place (drop shadow, white body with a soft
	vertical gradient, tiled stud texture, cream inner rim, coloured edge stroke, a banner header
	on the top edge, gradient cards and buttons with dark borders and inner rims, FredokaOne text
	with an ink outline). Run it from an edit-mode execute_luau; it replaces both frames.

	The HUD module (ServerStorage.Modules.UserInterfaces.HUD) reads these names, so keep them:
	  Background.Foreground.CurrentBoost / UpcomingBoost   boost now / after the next reset
	  Background.Foreground.Level (Frame) + BackFrame fill + Frame.TextLabel / TextShadow
	  Background.Foreground.Buy (TextButton) + TextLabel / TextShadow
	  X (GuiButton anywhere)                               close
	Everything is laid out in Scale inside a window that keeps a 1.25 aspect ratio at 80% of the
	screen height, so it fits every viewport; text is TextScaled.

	The previous Rebirth frame is kept in ServerStorage.Backups.UI_Rebirth_before-restyle_2026-09-24
	and in extras/Rebirth_before-restyle_2026-09-24.rbxm.

--------------------------------------------------------------------------------------------]]--

local ServerStorage = game:GetService("ServerStorage")
local HUD_FRAMES = ServerStorage.Assets.UserInterfaces.HUD

local STUDS = "rbxassetid://14905298636" -- New Map stud tile
local ARROW = "rbxassetid://113666736365393" -- the panel's "next" arrow
local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(36, 25, 29)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local THEMES = {
	Rebirth = {
		Shadow = Color3.fromRGB(100, 8, 25),
		Border = Color3.fromRGB(100, 8, 25),
		BodyTop = Color3.fromRGB(255, 220, 225),
		BodyBottom = Color3.fromRGB(255, 176, 190),
		Edge = Color3.fromRGB(255, 39, 92),
		HeaderTop = Color3.fromRGB(255, 140, 169),
		HeaderBottom = Color3.fromRGB(209, 11, 110),
		CardTop = Color3.fromRGB(15, 224, 255),
		CardBottom = Color3.fromRGB(0, 170, 240),
		CardBorder = INK,
		CardRim = Color3.fromRGB(190, 245, 255),
		TrackTop = Color3.fromRGB(96, 132, 168),
		TrackBottom = Color3.fromRGB(52, 80, 110),
		FillTop = Color3.fromRGB(15, 224, 255),
		FillBottom = Color3.fromRGB(0, 170, 240),
		BuyTop = Color3.fromRGB(155, 255, 51),
		BuyBottom = Color3.fromRGB(66, 214, 5),
		BuyBorder = Color3.fromRGB(36, 72, 12),
		BuyRim = Color3.fromRGB(225, 255, 190),
		Title = "REBIRTH",
		Icon = "rbxassetid://133985401312423",
		Heading = "Current Boost",
		LevelTitle = "LEVEL",
		Note = "Resets level, coins, mountains & gear. Keeps your boost and lifetime totals.",
		Button = "REBIRTH!",
	},
	Ascend = {
		Shadow = Color3.fromRGB(110, 72, 8),
		Border = Color3.fromRGB(110, 72, 8),
		BodyTop = Color3.fromRGB(255, 250, 228),
		BodyBottom = Color3.fromRGB(255, 226, 150),
		Edge = Color3.fromRGB(255, 196, 40),
		HeaderTop = Color3.fromRGB(255, 226, 120),
		HeaderBottom = Color3.fromRGB(232, 150, 20),
		CardTop = Color3.fromRGB(255, 205, 70),
		CardBottom = Color3.fromRGB(232, 140, 10),
		CardBorder = Color3.fromRGB(90, 55, 5),
		CardRim = Color3.fromRGB(255, 240, 190),
		TrackTop = Color3.fromRGB(150, 110, 50),
		TrackBottom = Color3.fromRGB(100, 70, 25),
		FillTop = Color3.fromRGB(255, 232, 120),
		FillBottom = Color3.fromRGB(255, 190, 40),
		BuyTop = Color3.fromRGB(255, 220, 80),
		BuyBottom = Color3.fromRGB(240, 160, 20),
		BuyBorder = Color3.fromRGB(110, 70, 0),
		BuyRim = Color3.fromRGB(255, 245, 200),
		Title = "ASCEND",
		Icon = nil,
		Heading = "Current Power",
		LevelTitle = "LEVEL",
		Note = "Resets EVERYTHING: level, coins, rebirths, mountains, gear & totals. Your power is permanent.",
		Button = "ASCEND!",
	},
}

local function make(class, name, parent, props)
	local inst = Instance.new(class)
	inst.Name = name
	for key, value in props or {} do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, px)
	return make("UICorner", "Corners", parent, { CornerRadius = UDim.new(0, px) })
end

local function border(parent, color, thick, name)
	return make("UIStroke", name or "Border", parent, {
		Color = color,
		Thickness = thick,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function gradient(parent, top, bottom, rotation)
	return make("UIGradient", "Gradient", parent, {
		Rotation = rotation or 90,
		Color = ColorSequence.new(top, bottom),
	})
end

local function aspect(parent, ratio)
	return make("UIAspectRatioConstraint", "Aspect", parent, {
		AspectRatio = ratio,
		DominantAxis = Enum.DominantAxis.Height,
	})
end

local function studs(parent, transparency, radius, tile, z)
	local image = make("ImageLabel", "StudTexture", parent, {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = STUDS,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile, tile),
		ZIndex = z,
	})
	corner(image, radius)
	return image
end

local function rim(parent, color, inset, radius, thick, z)
	local frame = make("Frame", "InnerRim", parent, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
		ZIndex = z,
	})
	corner(frame, radius)
	border(frame, color, thick)
	return frame
end

-- FredokaOne, TextScaled, ink outline.
local function text(name, parent, str, position, size, z, stroke, color)
	local label = make("TextLabel", name, parent, {
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		ZIndex = z,
		Font = FONT,
		Text = str,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = color or WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	make("UIStroke", "UIStroke", label, {
		Color = INK,
		Thickness = stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
	return label
end

-- A white label over a black copy shifted down: the pair setButtonText writes.
local function shadowedText(parent, str, position, size, z, stroke)
	local shadow = text("TextShadow", parent, str, position + UDim2.fromScale(0, 0.07), size, z, stroke - 1, BLACK)
	shadow.UIStroke.Color = BLACK
	local label = text("TextLabel", parent, str, position, size, z + 1, stroke)
	return label, shadow
end

local function buildPanel(name, theme)
	local old = HUD_FRAMES:FindFirstChild(name)
	if old then
		old:Destroy()
	end

	local root = make("Frame", name, HUD_FRAMES, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
	})

	local function window(windowName, z, yOffset)
		-- UIAspectRatioConstraint (FitWithinMaxSize) fits the 1.25 box inside this Size, so the
		-- width must be a real bound (a 0 width collapses the whole panel to 0 x 0).
		local frame = make("Frame", windowName, root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.53, yOffset),
			Size = UDim2.fromScale(1, 0.8),
			BorderSizePixel = 0,
			ZIndex = z,
		})
		aspect(frame, 1.25)
		return frame
	end

	local shadow = window("Shadow", 5, 9)
	shadow.BackgroundColor3 = theme.Shadow
	corner(shadow, 23)

	local bg = window("Background", 6, 0)
	bg.BackgroundColor3 = WHITE
	corner(bg, 22)
	border(bg, theme.Border, 6)
	gradient(bg, theme.BodyTop, theme.BodyBottom)
	studs(bg, 0.89, 8, 180, 7)
	rim(bg, Color3.fromRGB(255, 251, 245), 7, 17, 4, 8)
	local edge = make("Frame", "Edge", bg, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 8,
	})
	corner(edge, 20)
	border(edge, theme.Edge, 3)

	-- Banner on the top edge.
	local header = make("Frame", "Header", bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.6, 0.15),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	corner(header, 14)
	border(header, INK, 3)
	gradient(header, theme.HeaderTop, theme.HeaderBottom)
	studs(header, 0.85, 12, 120, 13)
	rim(header, Color3.fromRGB(255, 240, 240), 5, 10, 2, 13)
	text("Title", header, theme.Title, UDim2.fromScale(0.16, 0.12), UDim2.fromScale(0.72, 0.76), 15, 5)
	if theme.Icon then
		local icon = make("ImageLabel", "Icon", header, {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.06, 0.5),
			Size = UDim2.fromScale(1.7, 1.7),
			Image = theme.Icon,
			ZIndex = 16,
		})
		aspect(icon, 1)
	end

	-- Close.
	local close = make("TextButton", "X", bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.985, 0),
		Size = UDim2.fromScale(0.13, 0.13),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 14,
	})
	aspect(close, 1)
	corner(close, 12)
	border(close, INK, 3)
	gradient(close, Color3.fromRGB(255, 103, 103), Color3.fromRGB(195, 41, 41))
	rim(close, Color3.fromRGB(255, 220, 220), 4, 9, 2, 15)
	shadowedText(close, "X", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.8, 0.8), 16, 4)

	-- Content.
	local fg = make("Frame", "Foreground", bg, {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.15),
		Size = UDim2.fromScale(0.88, 0.8),
		ZIndex = 9,
	})

	text("HeadingShadow", fg, theme.Heading, UDim2.fromScale(0, 0.012), UDim2.fromScale(1, 0.13), 9, 4, BLACK).UIStroke.Color = BLACK
	text("Heading", fg, theme.Heading, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.13), 10, 5)

	local card = make("Frame", "BoostCard", fg, {
		Position = UDim2.fromScale(0, 0.16),
		Size = UDim2.fromScale(1, 0.28),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	corner(card, 14)
	border(card, theme.CardBorder, 3)
	gradient(card, theme.CardTop, theme.CardBottom)
	studs(card, 0.85, 12, 120, 11)
	rim(card, theme.CardRim, 5, 10, 2, 11)
	text("CurrentBoost", card, "X1", UDim2.fromScale(0.03, 0.12), UDim2.fromScale(0.4, 0.76), 12, 5)
	local arrow = make("ImageLabel", "Arrow", card, {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		Image = ARROW,
		ZIndex = 12,
	})
	aspect(arrow, 1)
	text("UpcomingBoost", card, "X1.5", UDim2.fromScale(0.57, 0.12), UDim2.fromScale(0.4, 0.76), 12, 5)

	text("LevelTitle", fg, theme.LevelTitle, UDim2.fromScale(0, 0.46), UDim2.fromScale(1, 0.08), 10, 3)

	local level = make("Frame", "Level", fg, {
		Position = UDim2.fromScale(0, 0.555),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	corner(level, 12)
	border(level, INK, 3)
	gradient(level, theme.TrackTop, theme.TrackBottom)
	local fill = make("Frame", "BackFrame", level, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.98, 0.84),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 11,
	})
	fill:SetAttribute("FullWidthScale", 0.98)
	corner(fill, 10)
	gradient(fill, theme.FillTop, theme.FillBottom)
	local holder = make("Frame", "Frame", level, {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 12,
	})
	shadowedText(holder, "0/10", UDim2.fromScale(0.05, 0.19), UDim2.fromScale(0.9, 0.62), 12, 4)

	text("Note", fg, theme.Note, UDim2.fromScale(0, 0.71), UDim2.fromScale(1, 0.105), 10, 2)

	local buy = make("TextButton", "Buy", fg, {
		Position = UDim2.fromScale(0, 0.83),
		Size = UDim2.fromScale(1, 0.17),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
	})
	corner(buy, 12)
	border(buy, theme.BuyBorder, 3)
	gradient(buy, theme.BuyTop, theme.BuyBottom)
	studs(buy, 0.85, 10, 120, 11)
	rim(buy, theme.BuyRim, 5, 9, 2, 11)
	shadowedText(buy, theme.Button, UDim2.fromScale(0.05, 0.15), UDim2.fromScale(0.9, 0.7), 12, 5)

	return root
end

----------------------------------------------------------------------------------------------
-- "2x power!" gift checklist (ServerStorage.Assets.UserInterfaces.Gift.Interface, a whole
-- ScreenGui: manifest Parent = {}). Same look, green body, gold banner. Names the Gift module
-- reads: Gift (frame) > ... Favorite / Group rows (Check.Mark, Button + TextLabel/TextShadow),
-- Note, Claim (+ TextLabel/TextShadow), X.
----------------------------------------------------------------------------------------------

local GIFT = {
	Shadow = Color3.fromRGB(20, 80, 30),
	Border = Color3.fromRGB(20, 80, 30),
	BodyTop = Color3.fromRGB(228, 255, 228),
	BodyBottom = Color3.fromRGB(160, 235, 170),
	Edge = Color3.fromRGB(60, 200, 90),
	HeaderTop = Color3.fromRGB(255, 226, 120),
	HeaderBottom = Color3.fromRGB(232, 150, 20),
	RowTop = Color3.fromRGB(255, 255, 255),
	RowBottom = Color3.fromRGB(215, 245, 220),
	RowBorder = Color3.fromRGB(36, 72, 12),
	RowRim = Color3.fromRGB(240, 255, 240),
	ButtonTop = Color3.fromRGB(15, 224, 255),
	ButtonBottom = Color3.fromRGB(0, 170, 240),
	ButtonBorder = INK,
	ButtonRim = Color3.fromRGB(190, 245, 255),
	ClaimTop = Color3.fromRGB(255, 220, 80),
	ClaimBottom = Color3.fromRGB(240, 160, 20),
	ClaimBorder = Color3.fromRGB(110, 70, 0),
	ClaimRim = Color3.fromRGB(255, 245, 200),
	CheckInk = Color3.fromRGB(46, 160, 90),
}

local function buildGiftPanel()
	local ui = ServerStorage.Assets.UserInterfaces
	local folder = ui:FindFirstChild("Gift")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Gift"
	folder.Parent = ui

	local screen = make("ScreenGui", "Interface", folder, {
		DisplayOrder = 6,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	})
	local root = make("Frame", "Gift", screen, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	})

	local function window(windowName, z, yOffset)
		local frame = make("Frame", windowName, root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.53, yOffset),
			Size = UDim2.fromScale(1, 0.8),
			BorderSizePixel = 0,
			ZIndex = z,
		})
		aspect(frame, 1.25)
		return frame
	end

	local shadow = window("Shadow", 5, 9)
	shadow.BackgroundColor3 = GIFT.Shadow
	corner(shadow, 23)

	local bg = window("Background", 6, 0)
	bg.BackgroundColor3 = WHITE
	bg.Active = true -- clicks on the panel stay on the panel
	corner(bg, 22)
	border(bg, GIFT.Border, 6)
	gradient(bg, GIFT.BodyTop, GIFT.BodyBottom)
	studs(bg, 0.89, 8, 180, 7)
	rim(bg, Color3.fromRGB(250, 255, 250), 7, 17, 4, 8)
	local edge = make("Frame", "Edge", bg, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 8,
	})
	corner(edge, 20)
	border(edge, GIFT.Edge, 3)

	local header = make("Frame", "Header", bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.6, 0.15),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	corner(header, 14)
	border(header, INK, 3)
	gradient(header, GIFT.HeaderTop, GIFT.HeaderBottom)
	studs(header, 0.85, 12, 120, 13)
	rim(header, Color3.fromRGB(255, 250, 230), 5, 10, 2, 13)
	text("Title", header, "2x power!", UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.8), 15, 5)

	local close = make("TextButton", "X", bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.985, 0),
		Size = UDim2.fromScale(0.13, 0.13),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 14,
	})
	aspect(close, 1)
	corner(close, 12)
	border(close, INK, 3)
	gradient(close, Color3.fromRGB(255, 103, 103), Color3.fromRGB(195, 41, 41))
	rim(close, Color3.fromRGB(255, 220, 220), 4, 9, 2, 15)
	shadowedText(close, "X", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.8, 0.8), 16, 4)

	local fg = make("Frame", "Foreground", bg, {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.15),
		Size = UDim2.fromScale(0.88, 0.8),
		ZIndex = 9,
	})

	local function row(name, y, labelText, buttonText)
		local frame = make("Frame", name, fg, {
			Position = UDim2.fromScale(0, y),
			Size = UDim2.fromScale(1, 0.25),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 10,
		})
		corner(frame, 14)
		border(frame, GIFT.RowBorder, 3)
		gradient(frame, GIFT.RowTop, GIFT.RowBottom)
		rim(frame, GIFT.RowRim, 5, 10, 2, 11)

		local check = make("Frame", "Check", frame, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.09, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 12,
		})
		aspect(check, 1)
		corner(check, 10)
		border(check, INK, 3)
		local mark = text("Mark", check, "\u{2713}", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.96), 13, 2, GIFT.CheckInk)
		mark.Visible = false

		text("Label", frame, labelText, UDim2.fromScale(0.18, 0.2), UDim2.fromScale(0.46, 0.6), 12, 3)
		local label = frame.Label
		label.TextXAlignment = Enum.TextXAlignment.Left

		local button = make("TextButton", "Button", frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.3, 0.64),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 12,
		})
		corner(button, 11)
		border(button, GIFT.ButtonBorder, 3)
		gradient(button, GIFT.ButtonTop, GIFT.ButtonBottom)
		rim(button, GIFT.ButtonRim, 4, 8, 2, 13)
		shadowedText(button, buttonText, UDim2.fromScale(0.06, 0.14), UDim2.fromScale(0.88, 0.72), 14, 4)
		return frame
	end

	row("Favorite", 0.02, "Like & Favorite the game", "FAVORITE")
	row("Group", 0.31, "Join Ricky's Realm", "JOIN")

	text("Note", fg, "Do both, then claim your permanent 2x power on coins and XP!", UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.12), 10, 2)

	local claim = make("TextButton", "Claim", fg, {
		Position = UDim2.fromScale(0, 0.78),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
	})
	corner(claim, 12)
	border(claim, GIFT.ClaimBorder, 3)
	gradient(claim, GIFT.ClaimTop, GIFT.ClaimBottom)
	studs(claim, 0.85, 10, 120, 11)
	rim(claim, GIFT.ClaimRim, 5, 9, 2, 11)
	shadowedText(claim, "CLAIM", UDim2.fromScale(0.05, 0.15), UDim2.fromScale(0.9, 0.7), 12, 5)

	return screen
end

local built = {}
for name, theme in THEMES do
	buildPanel(name, theme)
	table.insert(built, name)
end
buildGiftPanel()
table.insert(built, "Gift")
table.sort(built)
return "built " .. table.concat(built, ", ")

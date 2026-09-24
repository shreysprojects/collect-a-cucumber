--[[
	build_shop_frames.lua  (run in the RAS - Dev EDIT DataModel via execute_luau)  2026-09-24

	Rebuilds ServerStorage.Assets.UserInterfaces.HUD.Shop in the New Map Cucumber Game's shop look
	(tab rail on the left, ribbon header, chunky close plate, rounded stud-textured cards with a
	rarity gradient, green buy pill, balance pill) using the RAS icy palette. Idempotent: the first
	run moves the original Shop frame to ServerStorage.Backups.UI_Shop_before-remake_2026-09-24,
	later runs replace the previous build (attribute ShopRemake).

	Everything is authored in DESIGN pixels on a 1140 x 735 panel; ShopPanel.luau (the client
	module) fits it to the screen through Panel.Fit (UIScale) and fills Grid from Templates.Card.
]]

local ServerStorage = game:GetService("ServerStorage")

local STUD = "rbxassetid://6927295847" -- the stud tile the rest of the RAS UI uses
local ICON_SHOP = "rbxassetid://115069395023212"
local ICON_SNOWBALLS = "rbxassetid://132114319503474"
local ICON_BLASTERS = "rbxassetid://128605655714992"
local ICON_COIN = "rbxassetid://138813916097806"
local ICON_LOCK = "rbxassetid://114665013893653"
local FONT = Enum.Font.FredokaOne
local NAVY = Color3.fromRGB(16, 42, 67)
local WHITE = Color3.new(1, 1, 1)
local BUILD_TAG = "2026-09-24"

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return mk("UICorner", { Name = "Corners", CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, mode, transparency, name)
	return mk("UIStroke", {
		Name = name or "Outline",
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Transparency = transparency or 0,
	}, parent)
end

local function gradient(parent, top, bottom, rotation, name)
	return mk("UIGradient", {
		Name = name or "Gradient",
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, parent)
end

local function stud(parent, transparency, radius, z)
	local label = mk("ImageLabel", {
		Name = "StudTexture",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = STUD,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(64, 64),
		ZIndex = z or (parent.ZIndex + 1),
	}, parent)
	corner(label, radius)
	return label
end

local function label(parent, name, textValue, props)
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		Font = FONT,
		Text = textValue,
		TextColor3 = WHITE,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = parent.ZIndex + 2,
	}
	for k, v in props do
		base[k] = v
	end
	local strokeColor = base.StrokeColor or NAVY
	local strokeThickness = base.StrokeThickness or 2.5
	local maxText = base.MaxTextSize
	base.StrokeColor, base.StrokeThickness, base.MaxTextSize = nil, nil, nil
	local tl = mk("TextLabel", base, parent)
	stroke(tl, strokeColor, strokeThickness, Enum.ApplyStrokeMode.Contextual, 0, "TextOutline")
	if maxText then
		mk("UITextSizeConstraint", { Name = "SizeLimit", MinTextSize = 8, MaxTextSize = maxText }, tl)
	end
	return tl
end

-- Rounded plate with gradient + stud texture + inner rim: the New Map card / tab / pill body.
local function plate(parent, name, props, style)
	local base = {
		Name = name,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or (parent.ZIndex + 1),
	}
	for k, v in props do
		base[k] = v
	end
	local frame = mk(style.Class or "Frame", base, parent)
	if style.Class == "TextButton" then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	corner(frame, style.Radius)
	stroke(frame, style.Stroke, style.StrokeThickness or 3)
	gradient(frame, style.Top, style.Bottom, style.Rotation or 90)
	if style.Stud then
		stud(frame, style.Stud, math.max(style.Radius - 2, 4))
	end
	if style.Rim then
		local rim = mk("Frame", {
			Name = "Rim",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(1, -10, 1, -10),
			ZIndex = frame.ZIndex + 1,
		}, frame)
		corner(rim, math.max(style.Radius - 4, 4))
		stroke(rim, style.Rim, 2, Enum.ApplyStrokeMode.Border, style.RimTransparency or 0.4)
	end
	return frame
end

------------------------------------------------------------------------------------------------
local function build()
	local hud = ServerStorage.Assets.UserInterfaces.HUD
	local backups = ServerStorage:FindFirstChild("Backups") or mk("Folder", { Name = "Backups" }, ServerStorage)

	local existing = hud:FindFirstChild("Shop")
	if existing then
		if existing:GetAttribute("ShopRemake") then
			existing:Destroy()
		else
			local backupName = "UI_Shop_before-remake_2026-09-24"
			if backups:FindFirstChild(backupName) then
				existing:Destroy()
			else
				existing.Name = backupName
				existing.Parent = backups
			end
		end
	end

	-- Root: full screen, centred anchor (HUD.luau pops PanelScale on it).
	local root = mk("Frame", {
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = true,
		ZIndex = 1,
	}, hud)
	root:SetAttribute("ShopRemake", BUILD_TAG)

	-- Oversized dimmer (the pop scales the root, the edges must stay covered); click = close.
	local dimmer = mk("TextButton", {
		Name = "Dimmer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 1.6),
		BackgroundColor3 = Color3.fromRGB(5, 16, 28),
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, root)
	dimmer:SetAttribute("HoverScaleBound", true)

	local panel = mk("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46), -- ShopPanel.PANEL_CENTER_Y: leaves the toast strip free below
		Size = UDim2.fromOffset(1140, 735),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, root)
	mk("UIScale", { Name = "Fit", Scale = 1 }, panel)

	-- Shadow + body
	local shadow = mk("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(126, 54),
		Size = UDim2.fromOffset(1010, 691),
		BackgroundColor3 = Color3.fromRGB(11, 34, 56),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, panel)
	corner(shadow, 26)

	local body = mk("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(118, 44),
		Size = UDim2.fromOffset(1010, 691),
		BackgroundColor3 = Color3.fromRGB(244, 250, 255),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, panel)
	corner(body, 22)
	stroke(body, NAVY, 6)
	gradient(body, Color3.fromRGB(250, 253, 255), Color3.fromRGB(207, 231, 248), 90)
	stud(body, 0.9, 18, 4)
	local rim = mk("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		ZIndex = 4,
	}, body)
	corner(rim, 16)
	stroke(rim, WHITE, 3, Enum.ApplyStrokeMode.Border, 0.35)

	-- Balance pill (top right of the body)
	local balance = plate(body, "Balance", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 30),
		Size = UDim2.fromOffset(240, 54),
		ZIndex = 6,
	}, { Radius = 16, Stroke = Color3.fromRGB(73, 182, 232), StrokeThickness = 3, Top = Color3.fromRGB(28, 62, 96), Bottom = Color3.fromRGB(12, 32, 54), Stud = 0.9 })
	mk("UIScale", { Name = "Pop", Scale = 1 }, balance)
	mk("ImageLabel", {
		Name = "Coin",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Image = ICON_COIN,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 8,
	}, balance)
	label(balance, "Value", "0", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 58, 0.5, 0),
		Size = UDim2.new(1, -72, 0, 36),
		TextColor3 = Color3.fromRGB(255, 224, 68),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeColor = Color3.fromRGB(6, 21, 37),
		StrokeThickness = 2.5,
		MaxTextSize = 32,
		ZIndex = 8,
	})

	-- Content area with heading + card grid
	local content = mk("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(24, 108),
		Size = UDim2.fromOffset(962, 559),
		BackgroundColor3 = Color3.fromRGB(207, 230, 248),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, body)
	corner(content, 18)
	stroke(content, Color3.fromRGB(143, 195, 234), 3)
	label(content, "Heading", "SNOWBALLS", {
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -36, 0, 32),
		TextColor3 = Color3.fromRGB(255, 220, 80),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeColor = Color3.fromRGB(74, 40, 8),
		StrokeThickness = 2.5,
		MaxTextSize = 26,
		ZIndex = 7,
	})
	local grid = mk("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(73, 182, 232),
		ScrollBarImageTransparency = 0.1,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 6,
	}, content)
	mk("UIGridLayout", {
		Name = "Layout",
		CellSize = UDim2.fromOffset(296, 236),
		CellPadding = UDim2.fromOffset(14, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 3,
	}, grid)
	mk("UIPadding", {
		Name = "Padding",
		PaddingLeft = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 2),
	}, grid)

	-- Tab rail (left)
	local rail = mk("Frame", {
		Name = "TabRail",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(120, 735),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, panel)
	local function tab(name, y, top, bottom, icon, text)
		local button = plate(rail, name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(64, y),
			Size = UDim2.fromOffset(106, 110),
			ZIndex = 5,
		}, { Class = "TextButton", Radius = 16, Stroke = NAVY, StrokeThickness = 4, Top = top, Bottom = bottom, Stud = 0.7, Rim = WHITE, RimTransparency = 0.5 })
		button:SetAttribute("HoverScaleBound", true)
		button:SetAttribute("ShopTab", name)
		mk("UIScale", { Name = "TabScale", Scale = 1 }, button)
		mk("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(66, 66),
			Image = icon,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 8,
		}, button)
		label(button, "Label", text, {
			Position = UDim2.fromOffset(4, 78),
			Size = UDim2.new(1, -8, 0, 22),
			StrokeColor = Color3.fromRGB(16, 22, 13),
			StrokeThickness = 2.5,
			MaxTextSize = 18,
			ZIndex = 8,
		})
		local dim = mk("Frame", {
			Name = "Dim",
			BackgroundColor3 = Color3.fromRGB(10, 22, 40),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
		}, button)
		corner(dim, 16)
		return button
	end
	tab("Snowballs", 200, Color3.fromRGB(226, 198, 255), Color3.fromRGB(139, 92, 246), ICON_SNOWBALLS, "SNOWBALLS")
	tab("Blasters", 328, Color3.fromRGB(125, 227, 244), Color3.fromRGB(46, 143, 214), ICON_BLASTERS, "BLASTERS")

	-- Header ribbon
	local header = plate(panel, "Header", {
		Position = UDim2.fromOffset(150, 4),
		Size = UDim2.fromOffset(360, 86),
		Rotation = -2.5,
		ZIndex = 7,
	}, { Radius = 18, Stroke = NAVY, StrokeThickness = 5, Top = Color3.fromRGB(111, 208, 255), Bottom = Color3.fromRGB(46, 155, 224), Stud = 0.82 })
	mk("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-22, -12),
		Size = UDim2.fromOffset(104, 104),
		Image = ICON_SHOP,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 10,
	}, header)
	label(header, "TitleShadow", "SHOP", {
		Position = UDim2.fromOffset(90, 12),
		Size = UDim2.fromOffset(250, 68),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		StrokeColor = Color3.fromRGB(0, 0, 0),
		StrokeThickness = 4,
		ZIndex = 9,
	})
	label(header, "Title", "SHOP", {
		Position = UDim2.fromOffset(90, 6),
		Size = UDim2.fromOffset(250, 68),
		StrokeColor = NAVY,
		StrokeThickness = 5,
		ZIndex = 10,
	})

	-- Close plate (X)
	local closePlate = mk("Frame", {
		Name = "CloseShadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(1094, 62),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Color3.fromRGB(11, 34, 56),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, panel)
	corner(closePlate, 22)
	local close = plate(panel, "X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(1094, 56),
		Size = UDim2.fromOffset(84, 84),
		ZIndex = 8,
	}, { Class = "TextButton", Radius = 22, Stroke = NAVY, StrokeThickness = 5, Top = Color3.fromRGB(255, 103, 103), Bottom = Color3.fromRGB(195, 41, 41), Stud = 0.8, Rim = WHITE, RimTransparency = 0.55 })
	label(close, "TextShadow", "X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 5),
		Size = UDim2.fromScale(0.8, 0.8),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		StrokeColor = Color3.fromRGB(0, 0, 0),
		StrokeThickness = 3,
		ZIndex = 10,
	})
	label(close, "Label", "X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		StrokeColor = NAVY,
		StrokeThickness = 4,
		ZIndex = 11,
	})

	-- Card template
	local templates = mk("Folder", { Name = "Templates" }, panel)
	local card = plate(templates, "Card", {
		Size = UDim2.fromOffset(296, 236),
		Visible = false,
		ZIndex = 7,
	}, { Radius = 14, Stroke = Color3.fromRGB(31, 78, 110), StrokeThickness = 3, Top = Color3.fromRGB(230, 247, 255), Bottom = Color3.fromRGB(166, 221, 245), Stud = 0.78, Rim = WHITE, RimTransparency = 0.45 })
	mk("UIScale", { Name = "Pop", Scale = 1 }, card)
	label(card, "Title", "Snowball", { -- "Title", not "Name": card.Name is the instance name
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -100, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeColor = Color3.fromRGB(20, 34, 48),
		StrokeThickness = 2.5,
		MaxTextSize = 26,
		ZIndex = 11,
	})
	label(card, "Rarity", "COMMON", {
		Position = UDim2.fromOffset(13, 42),
		Size = UDim2.new(1, -100, 0, 18),
		TextColor3 = Color3.fromRGB(221, 238, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeColor = Color3.fromRGB(20, 34, 48),
		StrokeThickness = 2,
		MaxTextSize = 15,
		ZIndex = 11,
	})
	local mult = plate(card, "Mult", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(78, 32),
		ZIndex = 10,
	}, { Radius = 10, Stroke = Color3.fromRGB(107, 74, 0), StrokeThickness = 2.5, Top = Color3.fromRGB(255, 233, 107), Bottom = Color3.fromRGB(255, 184, 0) })
	label(mult, "Label", "x1", {
		Size = UDim2.fromScale(1, 1),
		StrokeColor = Color3.fromRGB(107, 74, 0),
		StrokeThickness = 2.5,
		MaxTextSize = 22,
		ZIndex = 12,
	})
	local iconPlate = mk("Frame", {
		Name = "IconPlate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(118, 118),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, card)
	mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, iconPlate)
	mk("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(112, 112),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 10,
	}, card)
	mk("ImageLabel", {
		Name = "Lock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(60, 60),
		Image = ICON_LOCK,
		ImageColor3 = Color3.fromRGB(221, 235, 242),
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 12,
	}, card)
	local equipped = plate(card, "Equipped", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(176, 40),
		Rotation = -8,
		Visible = false,
		ZIndex = 13,
	}, { Radius = 10, Stroke = Color3.fromRGB(107, 74, 0), StrokeThickness = 3, Top = Color3.fromRGB(255, 233, 107), Bottom = Color3.fromRGB(255, 184, 0), Stud = 0.85 })
	mk("UIScale", { Name = "Stamp", Scale = 1 }, equipped)
	label(equipped, "Label", "EQUIPPED", {
		Size = UDim2.fromScale(1, 1),
		StrokeColor = Color3.fromRGB(107, 74, 0),
		StrokeThickness = 3,
		MaxTextSize = 24,
		ZIndex = 15,
	})
	local buy = plate(card, "Buy", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -28, 0, 50),
		ZIndex = 12,
	}, { Class = "TextButton", Radius = 12, Stroke = Color3.fromRGB(34, 71, 10), StrokeThickness = 3, Top = Color3.fromRGB(159, 255, 66), Bottom = Color3.fromRGB(64, 214, 0), Stud = 0.84, Rim = WHITE, RimTransparency = 0.55 })
	mk("ImageLabel", {
		Name = "Coin",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -70, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Image = ICON_COIN,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 15,
	}, buy)
	label(buy, "Label", "$2.5K", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 18, 0.5, 0),
		Size = UDim2.new(1, -80, 0, 34),
		StrokeColor = Color3.fromRGB(16, 22, 13),
		StrokeThickness = 2.5,
		MaxTextSize = 28,
		ZIndex = 15,
	})

	return string.format("built Shop: %d descendants (template card %d)", #root:GetDescendants(), #card:GetDescendants())
end

return build()

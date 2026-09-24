--[[
	build_mountains_frame.lua  (run in the RAS - Dev EDIT DataModel via execute_luau)  2026-09-24

	Rebuilds ServerStorage.Assets.UserInterfaces.HUD.Mountains in the same look as the remade Shop
	(build_shop_frames.lua): ribbon header, chunky X, frosty body, and a 2 x 4 grid of mountain
	cards drawn on each mountain's banner art. Idempotent: the first run moves the original frame
	to ServerStorage.Backups.UI_Mountains_before-remake_2026-09-24, later runs replace the previous
	build (attribute MountainsRemake).

	HUD.luau (ApplyMountainLocks) keeps driving it by name: the grid is "ScrollingFrame", each
	card is named after its mountain id, and carries Travel (GO! / HERE pill, label "TextLabel"),
	Locked (dim overlay + padlock + LockText + LOCKED pill), Difficulty and Length labels, and an
	Outline stroke that turns gold on the mountain you are on. Panel.Fit is sized by HUD.luau.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig:Clone())()

local STUD = "rbxassetid://6927295847"
local ICON_MOUNTAINS = "rbxassetid://121436119655925"
local ICON_LOCK = "rbxassetid://114665013893653"
local ART = {
	Frostpeak = "rbxassetid://122665305375671",
	Christmas = "rbxassetid://139273002438617",
	Candy = "rbxassetid://106690192827821",
	PirateGlacier = "rbxassetid://105494966184429",
	Haunted = "rbxassetid://131350473397800",
	Volcano = "rbxassetid://91427628893256",
	Tech = "rbxassetid://132843263242828",
	Cosmic = "rbxassetid://87919076686307",
}
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

	local existing = hud:FindFirstChild("Mountains")
	if existing then
		if existing:GetAttribute("MountainsRemake") then
			existing:Destroy()
		else
			local backupName = "UI_Mountains_before-remake_2026-09-24"
			if backups:FindFirstChild(backupName) then
				existing:Destroy()
			else
				existing.Name = backupName
				existing.Parent = backups
			end
		end
	end

	local root = mk("Frame", {
		Name = "Mountains",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = true,
		ZIndex = 1,
	}, hud)
	root:SetAttribute("MountainsRemake", BUILD_TAG)

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
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(1140, 735),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, root)
	panel:SetAttribute("DesignWidth", 1140)
	panel:SetAttribute("DesignHeight", 735)
	mk("UIScale", { Name = "Fit", Scale = 1 }, panel)

	local shadow = mk("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(78, 54),
		Size = UDim2.fromOffset(1010, 691),
		BackgroundColor3 = Color3.fromRGB(11, 34, 56),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, panel)
	corner(shadow, 26)

	local body = mk("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(70, 44),
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

	-- Content area with heading + card grid (the grid keeps the name HUD.luau looks for)
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
	label(content, "Heading", "⛰ MOUNTAINS — FINISH ONE TO UNLOCK THE NEXT", {
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
		Name = "ScrollingFrame",
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
		-- 2 x 452 + 14 = 918 px fits the 922 px the grid keeps after its scrollbar inset + padding
		CellSize = UDim2.fromOffset(452, 108),
		CellPadding = UDim2.fromOffset(14, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 2,
	}, grid)
	mk("UIPadding", {
		Name = "Padding",
		PaddingLeft = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 2),
	}, grid)

	-- Header ribbon
	local header = plate(panel, "Header", {
		Position = UDim2.fromOffset(102, 4),
		Size = UDim2.fromOffset(440, 86),
		Rotation = -2.5,
		ZIndex = 7,
	}, { Radius = 18, Stroke = NAVY, StrokeThickness = 5, Top = Color3.fromRGB(111, 208, 255), Bottom = Color3.fromRGB(46, 155, 224), Stud = 0.82 })
	mk("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-22, -12),
		Size = UDim2.fromOffset(104, 104),
		Image = ICON_MOUNTAINS,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 10,
	}, header)
	label(header, "TitleShadow", "MOUNTAINS", {
		Position = UDim2.fromOffset(90, 12),
		Size = UDim2.fromOffset(330, 68),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		StrokeColor = Color3.fromRGB(0, 0, 0),
		StrokeThickness = 4,
		ZIndex = 9,
	})
	label(header, "Title", "MOUNTAINS", {
		Position = UDim2.fromOffset(90, 6),
		Size = UDim2.fromOffset(330, 68),
		StrokeColor = NAVY,
		StrokeThickness = 5,
		ZIndex = 10,
	})

	-- Close plate (X)
	local closePlate = mk("Frame", {
		Name = "CloseShadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(1046, 62),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Color3.fromRGB(11, 34, 56),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, panel)
	corner(closePlate, 22)
	local close = plate(panel, "X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(1046, 56),
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

	-- One card per mountain, in the progression order
	for index, mountainId in ipairs(mountainConfig.MountainOrder) do
		local card = mk("Frame", {
			Name = mountainId,
			LayoutOrder = index,
			Size = UDim2.fromOffset(452, 108),
			BackgroundColor3 = Color3.fromRGB(30, 60, 90),
			BorderSizePixel = 0,
			ZIndex = 7,
		}, grid)
		corner(card, 14)
		stroke(card, Color3.fromRGB(31, 78, 110), 3)
		local art = mk("ImageLabel", {
			Name = "Art",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = ART[mountainId] or "",
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 8,
		}, card)
		corner(art, 14)
		local shade = mk("Frame", {
			Name = "Shade",
			BackgroundColor3 = Color3.fromRGB(4, 14, 26),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
		}, card)
		corner(shade, 14)
		mk("UIGradient", {
			Name = "Gradient",
			Color = ColorSequence.new(WHITE, WHITE),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.55, 0.55),
				NumberSequenceKeypoint.new(1, 0.9),
			}),
			Rotation = 0,
		}, shade)
		local rimFrame = mk("Frame", {
			Name = "Rim",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(1, -10, 1, -10),
			ZIndex = 10,
		}, card)
		corner(rimFrame, 10)
		stroke(rimFrame, WHITE, 2, Enum.ApplyStrokeMode.Border, 0.5)

		label(card, "Title", mountainConfig:GetDisplayName(mountainId), {
			Position = UDim2.fromOffset(18, 10),
			Size = UDim2.fromOffset(280, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			StrokeColor = Color3.fromRGB(10, 24, 40),
			StrokeThickness = 3,
			MaxTextSize = 32,
			ZIndex = 12,
		})
		local level = mountainConfig:GetDifficulty(mountainId)
		local levelName = mountainConfig:GetDifficultyName(mountainId)
		label(card, "Difficulty", if level and levelName then tostring(level) .. " · " .. levelName else "", {
			Position = UDim2.fromOffset(19, 54),
			Size = UDim2.fromOffset(160, 22),
			TextColor3 = Color3.fromRGB(255, 220, 80),
			TextXAlignment = Enum.TextXAlignment.Left,
			StrokeColor = Color3.fromRGB(74, 40, 8),
			StrokeThickness = 2.5,
			MaxTextSize = 20,
			ZIndex = 12,
		})
		local length = mountainConfig:GetLength(mountainId)
		label(card, "Length", if length then tostring(length):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. " m" else "", {
			Position = UDim2.fromOffset(19, 78),
			Size = UDim2.fromOffset(160, 20),
			TextColor3 = Color3.fromRGB(221, 238, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
			StrokeColor = Color3.fromRGB(10, 24, 40),
			StrokeThickness = 2,
			MaxTextSize = 18,
			ZIndex = 12,
		})

		-- GO! / HERE pill (label named TextLabel so HUD.luau's setButtonText drives it)
		local travel = plate(card, "Travel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(136, 50),
			ZIndex = 13,
		}, { Class = "TextButton", Radius = 12, Stroke = Color3.fromRGB(34, 71, 10), StrokeThickness = 3, Top = Color3.fromRGB(159, 255, 66), Bottom = Color3.fromRGB(64, 214, 0), Stud = 0.84, Rim = WHITE, RimTransparency = 0.55 })
		travel:SetAttribute("HoverScaleBound", true)
		label(travel, "TextLabel", "GO!", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 0, 34),
			StrokeColor = Color3.fromRGB(16, 22, 13),
			StrokeThickness = 2.5,
			MaxTextSize = 28,
			ZIndex = 16,
		})

		-- Locked overlay: dims the art, padlock + LOCKED pill + "BEAT <previous>" line
		local locked = mk("Frame", {
			Name = "Locked",
			BackgroundColor3 = Color3.fromRGB(6, 18, 32),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 14,
		}, card)
		corner(locked, 14)
		mk("ImageLabel", {
			Name = "Lock",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -160, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			Image = ICON_LOCK,
			ImageColor3 = Color3.fromRGB(221, 235, 242),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 16,
		}, locked)
		local lockPill = plate(locked, "Pill", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(136, 50),
			ZIndex = 15,
		}, { Radius = 12, Stroke = Color3.fromRGB(54, 62, 74), StrokeThickness = 3, Top = Color3.fromRGB(185, 194, 204), Bottom = Color3.fromRGB(122, 135, 148), Stud = 0.84 })
		label(lockPill, "Label", "LOCKED", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 0, 30),
			StrokeColor = Color3.fromRGB(16, 22, 13),
			StrokeThickness = 2.5,
			MaxTextSize = 24,
			ZIndex = 17,
		})
		label(locked, "LockText", "", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 8),
			Size = UDim2.fromOffset(200, 22),
			TextColor3 = Color3.fromRGB(255, 220, 80),
			TextXAlignment = Enum.TextXAlignment.Right,
			StrokeColor = Color3.fromRGB(74, 40, 8),
			StrokeThickness = 2.5,
			MaxTextSize = 18,
			ZIndex = 16,
		})
	end

	return string.format("built Mountains: %d descendants, %d cards", #root:GetDescendants(), #mountainConfig.MountainOrder)
end

return build()

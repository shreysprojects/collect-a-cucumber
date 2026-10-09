--[[
	Bookshelf  (ModuleScript, ReplicatedStorage.FunBehavioursClient)  2026-09-24
	Client half of the BOOKSHELF (fun-builds/CONTRACT.md, package HomeDining). The server's "Read a book" prompt
	fires Read {Book = "Book_NN", T = server time, Reader = UserId} to everyone:
	  * SLIDE - every client pulls that book (and its spine band Band_NN) 0.5 stud out toward the front, tipping
	    its top forward a few degrees like a finger pulling it, holds it, and pushes it home. Timed from T with
	    Kit.Now(), so every client shows the same book at the same moment; the pose is computed each frame from
	    the Hitbox (ctx:Step, idle when nothing slides), so a move / sale / break mid-slide always puts the book
	    back where it belongs (cleanup restores every rest pose).
	  * TOAST - the reader's client pops a small card near the top of the screen for CARD_SECONDS: a mini book
	    icon in the colour of the book that slid out, a silly book title and a random cucumber fact / joke
	    (FACTS, dealt from a shuffled bag so all 25 show before any repeats). Tap / click the card to close it.
	    One card per player, shared by every bookshelf (PlayerGui.BookshelfFactCard, ResetOnSpawn off).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Kit = require(Modules:WaitForChild("FunBuildKit"))
local okAssets, FunAssets = pcall(function() return require(Modules:WaitForChild("FunAssets", 10)) end)
if not okAssets or type(FunAssets) ~= "table" then FunAssets = {Sfx = {}} end

--..Config..--
local BOOK_PREFIX = "Book_"
local BAND_PREFIX = "Band_"
local SLIDE = 0.5               -- studs (x build scale) the book comes out
local TILT = math.rad(4)        -- its top tips toward the reader (small: tall books nearly touch the shelf above)
local OUT_TIME = 0.28
local HOLD_TIME = 1.15
local BACK_TIME = 0.35
local CARD_SECONDS = 4
local CARD_W, CARD_H = 440, 140 -- design size (px) before the viewport UIScale
local CARD_Y = 0.16             -- card top, fraction of the screen height (below the HUD top slot)

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(38, 22, 10)
local TITLE_COLOR = Color3.fromRGB(255, 226, 120)
local GREEN_A = Color3.fromRGB(69, 255, 0)
local GREEN_B = Color3.fromRGB(157, 255, 36)
local PAGE = Color3.fromRGB(242, 240, 234)
local GOLD = Color3.fromRGB(242, 193, 61)

--..Words (family friendly)..--
local FACTS = {
	"Cucumbers are about 96% water. The other 4% is pure crunch!",
	"Why did the cucumber blush? It saw the salad dressing!",
	"Cucumbers are technically fruits. Shh, don't tell them - they think they're veggies.",
	"Every pickle was once a cucumber. Some cucumbers dream of being pickles.",
	"What do you call a cucumber in trouble? A cucumber in a PICKLE!",
	"Cucumber vines climb with curly tendrils, like tiny green springs.",
	"Cucumbers are cousins of pumpkins, melons and squash. Family dinners are VERY green.",
	"What did the cucumber say to the zombie? \"Lettuce live in peace!\"",
	"Zombies never snack on cucumbers. Too crunchy, not enough brains.",
	"One cucumber plant can grow dozens of cucumbers in a single summer!",
	"People in India were growing cucumbers over 3,000 years ago. That's a LOT of salad.",
	"The Roman emperor Tiberius wanted a cucumber every single day. Relatable.",
	"Why was the cucumber calm during the zombie raid? It was cool as a cucumber.",
	"What's green and goes BOING BOING? A cucumber on a trampoline!",
	"A cucumber's favourite music? DILL-step, of course!",
	"Sea cucumbers aren't cucumbers at all - they're sea animals. Very confusing!",
	"Lemon cucumbers are round and yellow... but still 100% cucumber. Sneaky!",
	"Baby cucumbers are covered in tiny prickly bumps. Ouch... but cute!",
	"Cucumbers love warm sunshine and hate frost - just like you at the beach.",
	"How does a cucumber say goodbye? \"See you later, pickle-gator!\"",
	"What did the grumpy pickle say? \"I'm not DILL-ing with this!\"",
	"Where do cucumbers throw parties? At the GREEN-house!",
	"Cucumbers can't lift weights... but YOU can lift cucumbers. Keep training!",
	"Every cucumber seed is a whole new cucumber waiting to happen.",
	"None of the books on this shelf are about carrots. We checked. Twice.",
}
local TITLES = {
	"Pickles & Prejudice", "The Great Gherkin", "Moby Pickle", "War and Peas", "Around the Garden in 80 Days",
	"The Cucumber Chronicles", "Dill or No Dill", "A Tale of Two Pickles", "Cool as a Cucumber: A Memoir",
	"Twenty Thousand Seeds Under the Soil",
}

--..Shuffled bags: every entry once before any repeats..--
local bags = {}
local function Deal(list)
	local bag = bags[list]
	if not bag or #bag == 0 then
		bag = {}
		for i = 1, #list do bag[i] = i end
		for i = #bag, 2, -1 do
			local j = math.random(1, i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		bags[list] = bag
	end
	return list[table.remove(bag)]
end

--..Toast card (one per player, shared by every bookshelf)..--
local Card = {Serial = 0, Tweens = {}}

local function Fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.62, 1.35)
end

local function Corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
	return c
end

local function Stroke(parent, thickness, color, border)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function Label(parent, name, props, maxText)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = WHITE
	l.TextScaled = true
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do l[k] = v end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxText
	limit.MinTextSize = 10
	limit.Parent = l
	l.Parent = parent
	return l
end

local function CancelTweens()
	for _, t in ipairs(Card.Tweens) do t:Cancel() end
	table.clear(Card.Tweens)
end

local function Play(inst, info, goal)
	local t = TweenService:Create(inst, info, goal)
	table.insert(Card.Tweens, t)
	t:Play()
	return t
end

local function HideCard()
	local root = Card.Root
	if not (root and root.Parent and root.Visible) then return end
	local serial = Card.Serial
	CancelTweens()
	Card.Popping = true
	local t = Play(Card.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
	t.Completed:Connect(function()
		if Card.Serial == serial then
			root.Visible = false
			Card.Popping = false
		end
	end)
end

local function BuildCard()
	if Card.Gui and Card.Gui.Parent then return true end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BookshelfFactCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1500
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	--.. the card: a wooden book-cover panel; tap it to close
	local root = Instance.new("TextButton")
	root.Name = "Card"
	root.Text = ""
	root.AutoButtonColor = false
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, CARD_Y, 0)
	root.Size = UDim2.fromOffset(CARD_W, CARD_H)
	root.BackgroundColor3 = WHITE
	root.Visible = false
	root.Parent = gui
	Corner(root, 18)
	Stroke(root, 3, INK, true)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(128, 84, 44), Color3.fromRGB(86, 53, 26))
	grad.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root

	--.. mini book icon (cover = the colour of the book that slid out, pages, a gold band)
	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Position = UDim2.fromOffset(16, 18)
	cover.Size = UDim2.fromOffset(54, 76)
	cover.BackgroundColor3 = Color3.fromRGB(63, 121, 212)
	cover.Parent = root
	Corner(cover, 7)
	Stroke(cover, 2.5, INK, true)
	local pages = Instance.new("Frame")
	pages.Name = "Pages"
	pages.AnchorPoint = Vector2.new(1, 0.5)
	pages.Position = UDim2.new(1, -4, 0.5, 0)
	pages.Size = UDim2.new(0, 9, 1, -12)
	pages.BackgroundColor3 = PAGE
	pages.BorderSizePixel = 0
	pages.Parent = cover
	Corner(pages, 3)
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.Position = UDim2.new(0, 0, 0.2, 0)
	band.Size = UDim2.new(1, -13, 0, 7)
	band.BackgroundColor3 = GOLD
	band.BorderSizePixel = 0
	band.Parent = cover
	local cuke = Instance.new("Frame")
	cuke.Name = "Cucumber"
	cuke.AnchorPoint = Vector2.new(0.5, 0.5)
	cuke.Position = UDim2.new(0.42, 0, 0.62, 0)
	cuke.Size = UDim2.fromOffset(26, 11)
	cuke.Rotation = -30
	cuke.BackgroundColor3 = Color3.fromRGB(90, 168, 69)
	cuke.Parent = cover
	Corner(cuke, 6)
	Stroke(cuke, 1.5, INK, true)

	--.. words
	local title = Label(root, "Title", {
		Position = UDim2.fromOffset(84, 12),
		Size = UDim2.new(1, -100, 0, 30),
		TextColor3 = TITLE_COLOR,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, 26)
	Stroke(title, 2, INK)
	local body = Label(root, "Body", {
		Position = UDim2.fromOffset(84, 44),
		Size = UDim2.new(1, -100, 1, -66),
		TextYAlignment = Enum.TextYAlignment.Top,
	}, 22)
	Stroke(body, 1.6, INK)

	--.. how long the card stays (a shrinking green bar)
	local track = Instance.new("Frame")
	track.Name = "Timer"
	track.Position = UDim2.new(0, 84, 1, -16)
	track.Size = UDim2.new(1, -100, 0, 7)
	track.BackgroundColor3 = Color3.fromRGB(52, 32, 15)
	track.BorderSizePixel = 0
	track.Parent = root
	Corner(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Corner(fill, 4)
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new(GREEN_A, GREEN_B)
	fillGrad.Parent = fill

	local pop = Kit.MakeSound(FunAssets.Sfx.Sparkle or "Magic Shimmer", {Name = "CardPop", Volume = 0.45})
	pop.Parent = gui

	gui.Parent = playerGui
	Card.Gui, Card.Root, Card.Scale, Card.Cover, Card.Title, Card.Body, Card.Fill, Card.Pop =
		gui, root, scale, cover, title, body, fill, pop
	root.Activated:Connect(HideCard)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if Card.Scale and not Card.Popping then Card.Scale.Scale = Fit() end
		end)
	end
	return true
end

local function ShowCard(title, text, coverColor)
	if not BuildCard() then return end
	Card.Serial += 1
	local serial = Card.Serial
	CancelTweens()
	Card.Title.Text = title
	Card.Body.Text = text
	if typeof(coverColor) == "Color3" then Card.Cover.BackgroundColor3 = coverColor end
	Card.Root.Visible = true
	local fit = Fit()
	Card.Popping = true
	Card.Scale.Scale = fit * 0.55
	local grow = Play(Card.Scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = fit})
	grow.Completed:Connect(function()
		if Card.Serial == serial then Card.Popping = false end
	end)
	Card.Fill.Size = UDim2.fromScale(1, 1)
	Play(Card.Fill, TweenInfo.new(CARD_SECONDS, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(0, 1)})
	pcall(function() Card.Pop:Play() end)
	task.delay(CARD_SECONDS, function()
		if Card.Serial == serial then HideCard() end
	end)
end

--..Behaviour..--
local B = {}
B.Keys = {"Bookshelf"}
B.StepRange = 160

local function EaseOut(a) return 1 - (1 - a) * (1 - a) end
local function EaseInOut(a) return a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2 end

function B.Client(model, ctx)
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end

	--..Books: every movable book + its band, stored relative to the hitbox about the book's bottom-front edge..--
	local groups = {} -- [book name] = {Pivot = CFrame (hitbox space), Parts = {{Part, Rel (pivot space), Rest (hitbox space)}}, Color}
	for _, book in ipairs(Kit.Parts(model, BOOK_PREFIX)) do
		local pivotWorld = book.CFrame * CFrame.new(0, -book.Size.Y * 0.5, -book.Size.Z * 0.5)
		local members = {book}
		local band = Kit.Part(model, BAND_PREFIX .. book.Name:sub(#BOOK_PREFIX + 1))
		if band then table.insert(members, band) end
		local parts = {}
		for _, p in ipairs(members) do
			table.insert(parts, {Part = p, Rel = pivotWorld:ToObjectSpace(p.CFrame), Rest = hitbox.CFrame:ToObjectSpace(p.CFrame)})
		end
		groups[book.Name] = {Pivot = hitbox.CFrame:ToObjectSpace(pivotWorld), Parts = parts, Color = book.Color}
	end

	local slide = SLIDE * ctx.Scale
	local total = OUT_TIME + HOLD_TIME + BACK_TIME
	local active = {} -- [book name] = start (server time)
	local touched = {} -- [book name] = true once it has moved (cleanup puts these back)

	local function Pose(group, k)
		local base = hitbox.CFrame
		if k <= 0 then
			for _, e in ipairs(group.Parts) do
				if e.Part.Parent then e.Part.CFrame = base * e.Rest end
			end
			return
		end
		local pivot = (base * group.Pivot) + base.LookVector * (slide * k)
		local turned = pivot * CFrame.Angles(-TILT * k, 0, 0)
		for _, e in ipairs(group.Parts) do
			if e.Part.Parent then e.Part.CFrame = turned * e.Rel end
		end
	end

	ctx:Step(function(_, now)
		if next(active) == nil then return end
		for name, t0 in pairs(active) do
			local group = groups[name]
			local e = now - t0
			if not group then
				active[name] = nil
			elseif e >= total or e < -1 then
				Pose(group, 0)
				active[name] = nil
			elseif e < OUT_TIME then
				Pose(group, EaseOut(math.max(e, 0) / OUT_TIME))
			elseif e < OUT_TIME + HOLD_TIME then
				Pose(group, 1)
			else
				Pose(group, 1 - EaseInOut((e - OUT_TIME - HOLD_TIME) / BACK_TIME))
			end
		end
	end)

	--..A little whoosh from the shelf when a book comes out..--
	local spot = Kit.Pivot(model, "Read") or hitbox.Position
	local emitter = ctx:Part({Name = "BookshelfSfx", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(spot)})
	local whoosh = ctx:Sound(emitter, FunAssets.Sfx.Whoosh or "Whoosh", {Volume = 0.3, PlaybackSpeed = 1.35})

	--.. OnEvent (below) reaches these through the ctx
	ctx.Bookshelf = {
		Groups = groups,
		Read = function(name, t0)
			if not groups[name] then return end
			active[name] = tonumber(t0) or Kit.Now()
			touched[name] = true
			pcall(function() whoosh:Play() end)
		end,
	}

	return function()
		for name in pairs(touched) do Pose(groups[name], 0) end
		table.clear(active)
		table.clear(touched)
	end
end

function B.OnEvent(_, action, payload, ctx)
	if action ~= "Read" or type(payload) ~= "table" then return end
	local shelf = ctx.Bookshelf
	local name = type(payload.Book) == "string" and payload.Book or nil
	if shelf and name then shelf.Read(name, payload.T) end
	if payload.Reader == ctx.Player.UserId then
		local group = shelf and name and shelf.Groups[name]
		ShowCard(Deal(TITLES), Deal(FACTS), group and group.Color or nil)
	end
end

return B

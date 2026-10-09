--[[
	ShopDialogClient  (LocalScript, StarterPlayer.StarterPlayerScripts)
	DISABLED 2026-09-09 (user: "get rid of the dialogue, open the headband shop instantly"): the booth prompt
	now opens StarterPlayerScripts.HeadbandShopClient directly. This script is kept, Disabled, for reference.

	The shopkeeper chat at the "BUY YOUR TOOLS!" booth (Workspace.Map.Lobby.Shops["Buy Shop"]).
	A typed speech bubble pops over the booth and a column of clickable option pills fades in
	underneath it -- ported from Zombie Cucumber Game's ShopVendorClient (user 2026-09-09), with
	the same typing speed, the same '#N ["option"]' pill labels, the same staggered fade-in and
	the same hover grow.

	DIFFERENCE FROM THE SOURCE: that place authored the bubble and the choice column in StarterGui
	and only cloned a hidden ChoiceTemplate. This place has no authored ScreenGuis at all, so both
	are BUILT HERE in code to the source's exact properties (12 x 3 stud billboard, FredokaOne 44
	white on a solid black stroke; ChoiceFrame 0.48 x 0.40 anchored (0, 0.5) at 50 % / 60 %; pills
	AutomaticSize XY, black at 0.5 transparency, FredokaOne 30, UICorner 6, UIPadding 5/5/12/12).
	The source leaned on that place's HudScaler for phone scaling; there is no HudScaler here, so
	the ChoiceFrame's "AutoScale" UIScale is driven from this script off the same 1920 x 1080
	reference, clamped 0.3 .. 1.5.

	CONTRACTS
	  in   ReplicatedStorage.Remotes.OpenShopDialog (RemoteEvent, fired to one player by the booth
	       server script when the "Talk" prompt is triggered) -> starts the dialogue.
	  in   CollectionService tag "ShopBoothPrompt" on the booth's ProximityPrompt. Its parent part
	       (the server's "TalkAnchor", a child of the Buy Shop Model) is the bubble's Adornee. The
	       tag is watched, never a path: StreamingEnabled can take the booth out and back, and
	       ServerStorage.LobbyLayout slides the whole Shops folder along Z at every server start,
	       so nothing here caches a reference or a coordinate for long.
	  out  player attribute "OpenHeadbandShop" = os.clock(). Two LocalScripts cannot share a
	       BindableEvent through ReplicatedStorage, so this is the agreed handshake with
	       StarterPlayerScripts.HeadbandShopClient: it opens its shop on every change of this
	       attribute (the timestamp value only exists to make each press a fresh change).
	  out  ReplicatedStorage.Modules.Notify for the "defenses" placeholder toast.

	Option 2 ("Show me defenses") is deliberately not wired to anything yet -- it toasts and closes.

	Studio hooks (attribute "ShopDialogDev" on this script's ScreenGui, or on workspace):
	  "open" / "close" -- start or end the dialogue; "1" / "2" / "3" -- press that option.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--..Modules..--
local Notify = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Notify")) -- the game-wide notification style (user 2026-09-07)

--..Config..--
local PROMPT_TAG = "ShopBoothPrompt" -- the server tags the booth's ProximityPrompt with this
local REMOTE_NAME = "OpenShopDialog"
local HEADBAND_ATTRIBUTE = "OpenHeadbandShop" -- read by StarterPlayerScripts.HeadbandShopClient

local GREETING = "What do you wanna buy?" --.. user 2026-09-09: plain and short
local TYPE_SPEED = 0.035 -- seconds per character
local FADE_STAGGER = 0.07 -- seconds between one pill fading in and the next
local FADE_TWEEN = TweenInfo.new(0.2)
local HOVER_GROW = 1.08
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WALK_AWAY = 28 -- studs from the booth before the chat closes itself
local WALK_POLL = 0.3

--.. look, straight off the source's property dump
local INK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local DISPLAY_ORDER = 41 -- above the HUD, below Notify (2000)
local BUBBLE_SIZE = UDim2.new(12, 0, 3, 0) -- scale units on a BillboardGui are read as STUDS here
local BUBBLE_OFFSET = Vector3.new(0, 3.2, 0)
local BUBBLE_MAX_DISTANCE = 60
local BUBBLE_TEXT_SIZE = 44
local CHOICE_TEXT_SIZE = 30
local CHOICE_BG_TRANSPARENCY = 0.5
local CHOICE_STROKE_TRANSPARENCY = 0.35
local REF_X, REF_Y = 1920, 1080 -- the reference screen the pill sizes were designed against
local SCALE_MIN, SCALE_MAX = 0.3, 1.5

--..Variables..--
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local dialogToken = 0 -- bumped by every TypeLine / HideDialog; an in-flight typewriter bails when its copy goes stale
local boothPrompt = nil -- the tagged ProximityPrompt, re-resolved rather than cached long
local boothAnchor = nil -- its host BasePart (the server's TalkAnchor); the bubble's Adornee

--..The speech bubble..--
local bubble = Instance.new("BillboardGui")
bubble.Name = "ShopDialogBubble"
bubble.Size = BUBBLE_SIZE
bubble.StudsOffset = Vector3.zero
bubble.StudsOffsetWorldSpace = BUBBLE_OFFSET
bubble.AlwaysOnTop = true
bubble.LightInfluence = 0
bubble.MaxDistance = BUBBLE_MAX_DISTANCE
bubble.ResetOnSpawn = false
bubble.ZIndexBehavior = Enum.ZIndexBehavior.Global
bubble.Enabled = false -- nothing on screen until the player talks
bubble.Parent = playerGui

local bubbleLabel = Instance.new("TextLabel")
bubbleLabel.Name = "Label"
bubbleLabel.Size = UDim2.fromScale(1, 1)
bubbleLabel.BackgroundTransparency = 1
bubbleLabel.BorderSizePixel = 0
bubbleLabel.Font = Enum.Font.FredokaOne
bubbleLabel.TextSize = BUBBLE_TEXT_SIZE
bubbleLabel.TextScaled = false
bubbleLabel.TextColor3 = WHITE
bubbleLabel.TextStrokeColor3 = INK
bubbleLabel.TextStrokeTransparency = 0 -- solid black outline, like the source
bubbleLabel.TextXAlignment = Enum.TextXAlignment.Center
bubbleLabel.TextYAlignment = Enum.TextYAlignment.Center
bubbleLabel.Text = ""
bubbleLabel.Parent = bubble

--..The choice column..--
local gui = Instance.new("ScreenGui")
gui.Name = "ShopDialogUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local choicesLayer = Instance.new("Frame")
choicesLayer.Name = "DialogChoices"
choicesLayer.Size = UDim2.fromScale(1, 1)
choicesLayer.Position = UDim2.fromScale(0, 0)
choicesLayer.BackgroundTransparency = 1
choicesLayer.BorderSizePixel = 0
choicesLayer.Visible = false -- the script toggles only this
choicesLayer.Parent = gui

--.. Geometry copied from the source's authored ChoiceFrame and left alone from here on: a runtime
--.. re-pin to a clamped pixel width shoved the options into the left HUD and stretched each one
--.. into a full-width bar in that place. The AutoScale UIScale is the only thing that touches size.
local choiceFrame = Instance.new("Frame")
choiceFrame.Name = "ChoiceFrame"
choiceFrame.AnchorPoint = Vector2.new(0, 0.5)
choiceFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
choiceFrame.Size = UDim2.new(0.48, 0, 0.4, 0)
choiceFrame.BackgroundTransparency = 1
choiceFrame.BorderSizePixel = 0
choiceFrame.Parent = choicesLayer

local autoScale = Instance.new("UIScale")
autoScale.Name = "AutoScale"
autoScale.Scale = 1
autoScale.Parent = choiceFrame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = choiceFrame

--.. the hidden prototype every option pill is cloned from (AutomaticSize XY: it has no size at
--.. all until it has text)
local choiceTemplate = Instance.new("TextButton")
choiceTemplate.Name = "ChoiceTemplate"
choiceTemplate.Visible = false
choiceTemplate.Size = UDim2.new(0, 0, 0, 0)
choiceTemplate.AutomaticSize = Enum.AutomaticSize.XY
choiceTemplate.BackgroundColor3 = INK
choiceTemplate.BackgroundTransparency = CHOICE_BG_TRANSPARENCY
choiceTemplate.BorderSizePixel = 0
choiceTemplate.AutoButtonColor = false
choiceTemplate.Font = Enum.Font.FredokaOne
choiceTemplate.TextSize = CHOICE_TEXT_SIZE
choiceTemplate.TextScaled = false
choiceTemplate.TextColor3 = WHITE
choiceTemplate.TextStrokeColor3 = INK
choiceTemplate.TextStrokeTransparency = CHOICE_STROKE_TRANSPARENCY
choiceTemplate.TextXAlignment = Enum.TextXAlignment.Left
choiceTemplate.TextYAlignment = Enum.TextYAlignment.Center
choiceTemplate.Text = ""
choiceTemplate.Parent = choiceFrame

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = choiceTemplate

local padding = Instance.new("UIPadding") -- the inner breathing room AutomaticSize would not give
padding.PaddingTop = UDim.new(0, 5)
padding.PaddingBottom = UDim.new(0, 5)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = choiceTemplate

local hoverTemplateScale = Instance.new("UIScale") -- per-pill hover grow target; clones carry it
hoverTemplateScale.Scale = 1
hoverTemplateScale.Parent = choiceTemplate

--..Functions..--
--.. phone scaling: this place has no HudScaler, so drive the AutoScale UIScale off the same
--.. 1920 x 1080 reference the source's HudScaler used
local function ApplyScale()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	autoScale.Scale = math.clamp(math.min(viewport.X / REF_X, viewport.Y / REF_Y), SCALE_MIN, SCALE_MAX)
end

--.. the nearest BasePart above the prompt: the server's TalkAnchor, whatever it ends up named
local function AnchorOf(prompt)
	local host = prompt.Parent
	while host and not host:IsA("BasePart") do
		host = host.Parent
	end
	return host
end

--.. Re-resolve the booth's prompt + anchor from the tag whenever they are needed. Deliberately not
--.. cached across calls: the server builds both at run time, and streaming can take the booth out
--.. and bring back a different instance while the player stands there.
local function Resolve()
	if boothPrompt and boothPrompt.Parent and boothAnchor and boothAnchor.Parent then
		return boothPrompt, boothAnchor
	end
	boothPrompt, boothAnchor = nil, nil
	for _, prompt in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		if prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(workspace) then
			local anchor = AnchorOf(prompt)
			if anchor then
				boothPrompt, boothAnchor = prompt, anchor
				break
			end
		end
	end
	bubble.Adornee = boothAnchor -- nil adornee = the bubble simply does not draw
	return boothPrompt, boothAnchor
end

--.. The "Talk" prompt otherwise floats over the dialogue the whole time it is open. Hidden
--.. CLIENT-SIDE ONLY, so it stays visible to everyone else standing at the same booth.
local function SetTalkPrompt(shown)
	local prompt = Resolve()
	if prompt then
		prompt.Enabled = shown
	end
end

local function ClearChoices()
	for _, child in ipairs(choiceFrame:GetChildren()) do
		if child:IsA("TextButton") and child ~= choiceTemplate then
			child:Destroy()
		end
	end
end

local function HideDialog()
	dialogToken += 1 -- kills any typewriter still running
	bubble.Enabled = false
	choicesLayer.Visible = false
	ClearChoices()
	SetTalkPrompt(true)
end

local function ShowChoices(options)
	ClearChoices()
	choicesLayer.Visible = true
	for i, option in ipairs(options) do
		local button = choiceTemplate:Clone()
		button.Name = "Choice" .. i
		button.Text = "#" .. i .. ' ["' .. option.text .. '"]'
		button.LayoutOrder = i
		--.. start fully faded, then tween back to the template's designed look
		button.TextTransparency = 1
		button.TextStrokeTransparency = 1
		button.BackgroundTransparency = 1
		button.Visible = true
		button.Parent = choiceFrame

		local hoverScale = button:FindFirstChildOfClass("UIScale")
		if hoverScale then
			button.MouseEnter:Connect(function()
				TweenService:Create(hoverScale, HOVER_TWEEN, { Scale = HOVER_GROW }):Play()
			end)
			button.MouseLeave:Connect(function()
				TweenService:Create(hoverScale, HOVER_TWEEN, { Scale = 1 }):Play()
			end)
		end

		button.Activated:Connect(function()
			if option.action then option.action() end
		end)

		task.delay(i * FADE_STAGGER, function()
			if not button.Parent then return end
			TweenService:Create(button, FADE_TWEEN, {
				TextTransparency = 0,
				TextStrokeTransparency = CHOICE_STROKE_TRANSPARENCY,
				BackgroundTransparency = CHOICE_BG_TRANSPARENCY,
			}):Play()
		end)
	end
end

local function TypeLine(text, onDone)
	dialogToken += 1
	local myToken = dialogToken
	choicesLayer.Visible = false
	ClearChoices()
	bubble.Enabled = true
	bubbleLabel.Text = ""
	SetTalkPrompt(false)
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

--..The options..--
--.. The headband shop lives in its own LocalScript (StarterPlayerScripts.HeadbandShopClient) and a
--.. BindableEvent in ReplicatedStorage would not carry client to client, so the handshake is a
--.. player attribute: stamping os.clock() makes every press a change the shop can hear.
local function OpenHeadbands()
	HideDialog()
	player:SetAttribute(HEADBAND_ATTRIBUTE, os.clock())
end

--.. Placeholder: there is no defense system yet (user 2026-09-09). Toast and close, build nothing.
local function OpenDefenses()
	HideDialog()
	Notify.Show("Defenses are coming soon!", Notify.COLORS.Info)
end

local CHOICES = {
	{ text = "Show me headbands", action = OpenHeadbands },
	{ text = "Show me defenses", action = OpenDefenses },
	{ text = "Nevermind", action = HideDialog },
}

local function StartDialog()
	if not Resolve() then return end -- the booth has not streamed in; nothing to talk to
	TypeLine(GREETING, function()
		ShowChoices(CHOICES)
	end)
end

--..Wiring..--
do
	local connection
	local function WatchViewport()
		if connection then connection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(ApplyScale)
		end
		ApplyScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(WatchViewport)
	WatchViewport()
end

Resolve()
CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(function()
	Resolve()
	--.. a prompt that streams back in arrives Enabled from the server; hide it again mid-chat
	if bubble.Enabled or choicesLayer.Visible then
		SetTalkPrompt(false)
	end
end)
CollectionService:GetInstanceRemovedSignal(PROMPT_TAG):Connect(function(prompt)
	if prompt ~= boothPrompt then return end
	boothPrompt, boothAnchor = nil, nil
	bubble.Adornee = nil
	if bubble.Enabled or choicesLayer.Visible then
		HideDialog()
	end
end)

--.. close the chat if the player wanders off; the booth's position is read from the anchor every
--.. poll, never from a stored coordinate (LobbyLayout moves the Shops folder at every server start)
task.spawn(function()
	while true do
		task.wait(WALK_POLL)
		if bubble.Enabled or choicesLayer.Visible then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local anchor = boothAnchor
			if not root or not anchor or not anchor.Parent
				or (root.Position - anchor.Position).Magnitude > WALK_AWAY then
				HideDialog()
			end
		end
	end
end)

--.. the booth server fires this to one player when the "Talk" prompt is triggered, so two players
--.. can hold independent conversations at the same booth
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	local openShopDialog = remotes and remotes:WaitForChild(REMOTE_NAME, 60)
	if not openShopDialog then
		warn("[ShopDialog] Remotes." .. REMOTE_NAME .. " never arrived; the booth prompt cannot open the chat")
		return
	end
	openShopDialog.OnClientEvent:Connect(StartDialog)
end)

--.. Studio only: ShopDialogDev = "open" / "close" / "1".."3" on this ScreenGui or on workspace
if RunService:IsStudio() then
	local function Dev(host)
		local command = host:GetAttribute("ShopDialogDev")
		if command == nil then return end
		host:SetAttribute("ShopDialogDev", nil) -- on workspace this clear is local to this client
		command = tostring(command)
		if command == "open" then
			StartDialog()
		elseif command == "close" then
			HideDialog()
		else
			local option = CHOICES[tonumber(command) or 0]
			if option and option.action then option.action() end
		end
	end
	gui:GetAttributeChangedSignal("ShopDialogDev"):Connect(function() Dev(gui) end)
	workspace:GetAttributeChangedSignal("ShopDialogDev"):Connect(function() Dev(workspace) end)
end

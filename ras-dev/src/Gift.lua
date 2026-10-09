--[[---------------------------------------DESCRIPTION------------------------------------------
	"2x power!" gift panel. GUIFramework spawns the ScreenGui template
	(ServerStorage.Assets.UserInterfaces.Gift.Interface, built by extras/panels/build_panels.lua)
	straight into PlayerGui as "Gift" (self.UI, manifest Parent = {}). Its Gift frame opens when
	the player walks into the GiftCircle ring by the present in the lobby (the same NeonRing /
	InnerCylinder volume the HUD reads for its circles), pops in like the HUD panels, registers
	with PanelManager (one panel at a time, FOV + blur), hides the HUD's MainUI while open and
	sets the PlayerGui attribute PanelOpen = "Gift" (hold-to-launch and the race bar read it).

	Checklist (the server's truth is the player attributes GiftFavorited / GiftInGroup /
	GiftClaimed, SERV_Gift):
	  Like & Favorite  AvatarEditorService: PromptAllowInventoryReadAccess, then
	                   GetFavoriteAsync(game.PlaceId); not favorited -> PromptSetFavorite; a
	                   Success result is reported to the server (GiftFavorited). No API can read
	                   or prompt a like, so the row asks for both and checks the favorite.
	  Join the group   GroupService:PromptJoinAsync(PlayerProgress.GIFT_GROUP_ID) unless the
	                   server already says the player is in the group; the server re-checks
	                   membership afterwards (GiftStatus with force).
	  CLAIM            ReFunction GiftClaim: the server verifies both and grants the permanent
	                   PlayerProgress.GIFT_POWER (2x) on coins and XP.
	Studio dev hooks (PlayerGui attributes): DevGift = "Open" / "Close" / "Favorite" / "Group" /
	"Claim" presses that control; DevGiftFavorited = true marks the favorite row done without
	the Roblox prompt (an eval cannot click it).

--------------------------------------------------------------------------------------------]]--

local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()
local PanelManager = require(ReplicatedStorage.Assets.Modules.Client.UI.PanelManager)
local PurchaseFX = require(ReplicatedStorage.Assets.Modules.Client.UI.PurchaseFX)
local Notify = require(ReplicatedStorage.Assets.Modules.Client.UI.Notify)
local UIUtils = require(ReplicatedStorage.Assets.Modules.Client.UI.UIUtils)
local Audio = require(ReplicatedStorage.Assets.Modules.Client.Audio)

local PANEL = "Gift"
local RING = "GiftCircle" -- lobby ring model (attribute LobbyRing) by the present
local RING_HEIGHT_PAD = 12
local POP_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_START_SCALE = 0.85
local BUTTON_FAVORITE = "FAVORITE"
local BUTTON_JOIN = "JOIN"
local BUTTON_DONE = "DONE"
local BUTTON_CLAIM = "CLAIM"
local BUTTON_CLAIMED = "CLAIMED"
local NOTE_TODO = "Do both, then claim your permanent 2x power on coins and XP!"
local NOTE_DONE = "2x power is yours! Every run pays double coins and XP."
local TOAST_CLAIMED = "2x power claimed!"
local TOAST_FAVORITED = "Thanks for the favorite!"
local TOAST_JOINED = "Welcome to %s!"
local TOAST_NOT_FAVORITED = "Favorite the game to tick this off"
local TOAST_NOT_IN_GROUP = "Join %s to tick this off"
local TOAST_PENDING = "Join request sent - come back once it is accepted"

local api = {}
api.Connections = {}

local function getPlayerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function hudModule()
	local source = ReplicatedStorage.Assets.UserInterfaces:FindFirstChild("Modules")
	source = source and source:FindFirstChild("HUD")
	if not source then
		return nil
	end
	local ok, hud = pcall(require, source)
	return ok and hud or nil
end

local function isRiding()
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	return folder ~= nil and folder:FindFirstChild(Players.LocalPlayer.Name .. "_Snowball") ~= nil
end

local function setGuiText(gui, text)
	if gui and (gui:IsA("TextLabel") or gui:IsA("TextButton")) then
		gui.Text = text
	end
end

-- A button's TextLabel + TextShadow pair (the builder's shape).
local function setButtonText(button, text)
	if not button then
		return
	end
	setGuiText(button:FindFirstChild("TextLabel"), text)
	setGuiText(button:FindFirstChild("TextShadow"), text)
end

local function eachGradient(button, fn)
	for _, child in button:GetChildren() do
		if child:IsA("UIGradient") then
			fn(child)
		end
	end
end

local function grayColor(color)
	local luminance = (color.R * 0.299 + color.G * 0.587 + color.B * 0.114) * 0.62
	return Color3.new(luminance, luminance, luminance)
end

-- Remembers each gradient's authored colours once, then tints it green (authored) or gray.
function api:TintButton(button, enabled)
	if not button then
		return
	end
	self.Looks = self.Looks or {}
	eachGradient(button, function(gradient)
		local look = self.Looks[gradient]
		if not look then
			local keypoints = {}
			for index, keypoint in gradient.Color.Keypoints do
				keypoints[index] = ColorSequenceKeypoint.new(keypoint.Time, grayColor(keypoint.Value))
			end
			look = { Authored = gradient.Color, Gray = ColorSequence.new(keypoints) }
			self.Looks[gradient] = look
		end
		gradient.Color = if enabled then look.Authored else look.Gray
	end)
	button.AutoButtonColor = enabled
	button:SetAttribute("ShopCanBuy", enabled) -- the hover scale reads this
end

----------------------------------------------------------------------------------------------
-- Panel plumbing (the HUD's OpenPanel / HidePanel, for one frame).
----------------------------------------------------------------------------------------------

function api:GetPanel()
	local gui = self.UI
	return gui and gui:FindFirstChild(PANEL)
end

local function getPanelScale(panel)
	local named = panel:FindFirstChild("PanelScale")
	if named and named:IsA("UIScale") then
		return named
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "PanelScale"
	uiScale.Parent = panel
	return uiScale
end

function api:Open()
	local panel = self:GetPanel()
	if not panel or self.Shown then
		return panel
	end
	if not self.Registered then
		self.Registered = true
		PanelManager.register(PANEL, function()
			self:Close()
		end)
	end
	Audio.Play("UIOpen")
	PanelManager.notifyOpened(PANEL)
	local hud = hudModule()
	if hud and hud.SetMainVisible then
		hud:SetMainVisible(false)
	end
	getPlayerGui():SetAttribute("PanelOpen", PANEL)

	if self.PopTween then
		self.PopTween:Cancel()
	end
	local uiScale = getPanelScale(panel)
	self.Shown = true
	uiScale.Scale = POP_START_SCALE
	panel.Visible = true
	self.PopTween = TweenService:Create(uiScale, POP_IN, { Scale = 1 })
	self.PopTween:Play()
	self:Refresh(true)
	return panel
end

function api:Close()
	local panel = self:GetPanel()
	if not panel or not self.Shown then
		return
	end
	self.Shown = false
	PanelManager.notifyClosed(PANEL)
	Audio.Play("UIClose")
	local playerGui = getPlayerGui()
	if playerGui:GetAttribute("PanelOpen") == PANEL then
		playerGui:SetAttribute("PanelOpen", nil)
	end
	local hud = hudModule()
	if hud and hud.SetMainVisible then
		hud:SetMainVisible(true)
	end

	if self.PopTween then
		self.PopTween:Cancel()
	end
	local uiScale = getPanelScale(panel)
	local tween = TweenService:Create(uiScale, POP_OUT, { Scale = POP_START_SCALE })
	self.PopTween = tween
	tween:Play()
	tween.Completed:Once(function()
		if self.PopTween == tween then
			self.PopTween = nil
		end
		if not self.Shown then
			panel.Visible = false
			uiScale.Scale = 1
		end
	end)
end

----------------------------------------------------------------------------------------------
-- Checklist state
----------------------------------------------------------------------------------------------

function api:Widgets()
	local panel = self:GetPanel()
	if not panel then
		return nil
	end
	local function row(name)
		local frame = panel:FindFirstChild(name, true)
		return frame, frame and frame:FindFirstChild("Check", true), frame and frame:FindFirstChild("Button", true)
	end
	local favoriteRow, favoriteCheck, favoriteButton = row("Favorite")
	local groupRow, groupCheck, groupButton = row("Group")
	return {
		FavoriteRow = favoriteRow,
		FavoriteCheck = favoriteCheck,
		FavoriteButton = favoriteButton,
		GroupRow = groupRow,
		GroupCheck = groupCheck,
		GroupButton = groupButton,
		Claim = panel:FindFirstChild("Claim", true),
		Note = panel:FindFirstChild("Note", true),
	}
end

local function setCheck(check, done)
	if not check then
		return
	end
	local mark = check:FindFirstChild("Mark")
	if mark then
		mark.Visible = done
	end
end

-- Asks the server (force = re-check the group) and redraws.
function api:Refresh(force)
	local player = Players.LocalPlayer
	if force then
		task.spawn(function()
			local ok, status = pcall(function()
				return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("GiftStatus", force == true)
			end)
			if ok and type(status) == "table" then
				self:Draw(status)
			end
		end)
	end
	self:Draw({
		Favorited = player:GetAttribute("GiftFavorited") == true,
		InGroup = player:GetAttribute("GiftInGroup") == true,
		Claimed = player:GetAttribute("GiftClaimed") == true,
	})
end

function api:Draw(status)
	local w = self:Widgets()
	if not w then
		return
	end
	local favorited = status.Favorited == true
	local inGroup = status.InGroup == true
	local claimed = status.Claimed == true

	setCheck(w.FavoriteCheck, favorited)
	setCheck(w.GroupCheck, inGroup)
	if w.FavoriteButton then
		setButtonText(w.FavoriteButton, if favorited then BUTTON_DONE else BUTTON_FAVORITE)
		self:TintButton(w.FavoriteButton, not favorited and not self.Busy)
	end
	if w.GroupButton then
		setButtonText(w.GroupButton, if inGroup then BUTTON_DONE else BUTTON_JOIN)
		self:TintButton(w.GroupButton, not inGroup and not self.Busy)
	end
	if w.Claim then
		setButtonText(w.Claim, if claimed then BUTTON_CLAIMED else BUTTON_CLAIM)
		self:TintButton(w.Claim, favorited and inGroup and not claimed and not self.Busy)
	end
	setGuiText(w.Note, if claimed then NOTE_DONE else NOTE_TODO)
end

----------------------------------------------------------------------------------------------
-- Presses
----------------------------------------------------------------------------------------------

local function reportFavorite()
	local ok, result = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("GiftFavorited")
	end)
	return ok and result == true
end

-- true when the local player favorites the experience by the end of this call.
local function ensureFavorite()
	local placeId = game.PlaceId
	local itemType = Enum.AvatarItemType.Asset

	-- Reading favorites needs the inventory read permission for this session.
	local access = nil
	local ok = pcall(function()
		AvatarEditorService:PromptAllowInventoryReadAccess()
		access = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Wait()
	end)
	if ok and access == Enum.AvatarPromptResult.Success then
		local okRead, favorited = pcall(function()
			return AvatarEditorService:GetFavoriteAsync(placeId, itemType)
		end)
		if okRead and favorited == true then
			return true
		end
	end

	-- Not favorited (or unreadable): ask.
	local result = nil
	local okPrompt = pcall(function()
		AvatarEditorService:PromptSetFavorite(placeId, itemType, true)
		local _, _, promptResult = AvatarEditorService.PromptSetFavoriteCompleted:Wait()
		result = promptResult
	end)
	return okPrompt and result == Enum.AvatarPromptResult.Success
end

function api:PressFavorite(button)
	if self.Busy then
		return
	end
	if Players.LocalPlayer:GetAttribute("GiftFavorited") == true then
		return
	end
	PurchaseFX.Press(button)
	self.Busy = true
	self:Refresh(false)
	local favorited = ensureFavorite()
	if favorited then
		favorited = reportFavorite()
	end
	self.Busy = false
	self:Refresh(false)
	if favorited then
		PurchaseFX.Success(button)
		Notify.Success(TOAST_FAVORITED)
	else
		PurchaseFX.Fail(button)
		Notify.Info(TOAST_NOT_FAVORITED)
	end
end

function api:PressGroup(button)
	if self.Busy then
		return
	end
	if Players.LocalPlayer:GetAttribute("GiftInGroup") == true then
		return
	end
	PurchaseFX.Press(button)
	self.Busy = true
	self:Refresh(false)
	local status = nil
	local ok, err = pcall(function()
		status = GroupService:PromptJoinAsync(playerProgress.GIFT_GROUP_ID)
	end)
	if not ok then
		warn("[CLIENT]: Group join prompt failed:", err)
	end
	-- The server decides; a fresh check right after the prompt.
	local okStatus, serverStatus = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("GiftStatus", true)
	end)
	self.Busy = false
	local inGroup = okStatus and type(serverStatus) == "table" and serverStatus.InGroup == true
	self:Refresh(false)
	if inGroup then
		PurchaseFX.Success(button)
		Notify.Success(string.format(TOAST_JOINED, playerProgress.GIFT_GROUP_NAME))
	elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
		PurchaseFX.Fail(button)
		Notify.Info(TOAST_PENDING)
	else
		PurchaseFX.Fail(button)
		Notify.Info(string.format(TOAST_NOT_IN_GROUP, playerProgress.GIFT_GROUP_NAME))
	end
end

function api:PressClaim(button)
	if self.Busy then
		return
	end
	local player = Players.LocalPlayer
	PurchaseFX.Press(button)
	if player:GetAttribute("GiftClaimed") == true then
		return
	end
	if player:GetAttribute("GiftFavorited") ~= true then
		PurchaseFX.Fail(button)
		Notify.Error(TOAST_NOT_FAVORITED)
		return
	end
	if player:GetAttribute("GiftInGroup") ~= true then
		PurchaseFX.Fail(button)
		Notify.Error(string.format(TOAST_NOT_IN_GROUP, playerProgress.GIFT_GROUP_NAME))
		return
	end
	self.Busy = true
	self:Refresh(false)
	local invoked, ok, err = pcall(function()
		return ReplicatedStorage.ReEvent.ReFunction:InvokeServer("GiftClaim")
	end)
	self.Busy = false
	self:Refresh(false)
	if invoked and ok then
		PurchaseFX.Success(button)
		PurchaseFX.FloatText(button, "2x POWER!")
		Audio.Play("Rebirth")
		Notify.Success(TOAST_CLAIMED)
	else
		warn("[CLIENT]: Gift claim failed:", if invoked then err else ok)
		PurchaseFX.Fail(button)
		Notify.Error(if invoked and type(err) == "string" then err else "Claim failed")
	end
end

----------------------------------------------------------------------------------------------
-- The ring by the present
----------------------------------------------------------------------------------------------

local function findRing()
	local mountain = workspace:FindFirstChild(mountainConfig.WORKSPACE_NAME)
	return mountain and mountain:FindFirstChild(RING, true)
end

local function ringVolume(ring)
	local inst = ring:FindFirstChild("NeonRing", true) or ring:FindFirstChild("InnerCylinder", true) or ring
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	return nil
end

local function isInside(position, cf, size)
	local localPoint = cf:PointToObjectSpace(position)
	local radius = math.max(size.X, size.Z) * 0.5
	local halfH = size.Y * 0.5
	return localPoint.X * localPoint.X + localPoint.Z * localPoint.Z <= radius * radius
		and localPoint.Y >= -halfH - 2
		and localPoint.Y <= halfH + RING_HEIGHT_PAD
end

function api:WatchRing()
	self.Inside = false
	local ring = nil
	table.insert(self.Connections, RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or isRiding() then
			self.Inside = false
			return
		end
		if not (ring and ring.Parent and ring:IsDescendantOf(workspace)) then
			ring = findRing()
			if not ring then
				return
			end
		end
		local cf, size = ringVolume(ring)
		local inside = cf ~= nil and isInside(hrp.Position, cf, size)
		if inside and not self.Inside then
			self:Open()
		end
		self.Inside = inside
	end))
end

----------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------

function api:DisconnectEvents()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

function api:ConnectEvents()
	self:DisconnectEvents()
end

function api:DevPress(request)
	if request == "Open" then
		self:Open()
	elseif request == "Close" then
		self:Close()
	else
		local w = self:Widgets()
		if not w then
			return
		end
		self:Open()
		if request == "Favorite" and w.FavoriteButton then
			self:PressFavorite(w.FavoriteButton)
		elseif request == "Group" and w.GroupButton then
			self:PressGroup(w.GroupButton)
		elseif request == "Claim" and w.Claim then
			self:PressClaim(w.Claim)
		end
	end
end

function api:Initialize()
	local gui = self.UI
	if not (gui and gui:IsA("ScreenGui")) then
		warn("[CLIENT]: Gift interface missing")
		return
	end
	self:DisconnectEvents()
	local panel = gui:FindFirstChild(PANEL)
	if not panel then
		warn("[CLIENT]: Gift frame missing (ServerStorage.Assets.UserInterfaces.Gift.Interface.Gift)")
		return
	end
	panel.Visible = false
	self.Shown = false
	self.Busy = false

	local w = self:Widgets()
	local close = panel:FindFirstChild("X", true)
	if close and close:IsA("GuiButton") then
		table.insert(self.Connections, close.Activated:Connect(function()
			self:Close()
		end))
	end
	if w.FavoriteButton then
		table.insert(self.Connections, w.FavoriteButton.Activated:Connect(function()
			self:PressFavorite(w.FavoriteButton)
		end))
	end
	if w.GroupButton then
		table.insert(self.Connections, w.GroupButton.Activated:Connect(function()
			self:PressGroup(w.GroupButton)
		end))
	end
	if w.Claim then
		table.insert(self.Connections, w.Claim.Activated:Connect(function()
			self:PressClaim(w.Claim)
		end))
	end
	local hoverWatch = UIUtils.bindHoverScaleAll(panel, nil, true)
	if hoverWatch then
		table.insert(self.Connections, hoverWatch)
	end

	local player = Players.LocalPlayer
	for _, name in { "GiftFavorited", "GiftInGroup", "GiftClaimed" } do
		table.insert(self.Connections, player:GetAttributeChangedSignal(name):Connect(function()
			self:Refresh(false)
		end))
	end

	local playerGui = getPlayerGui()
	table.insert(self.Connections, playerGui:GetAttributeChangedSignal("DevGift"):Connect(function()
		local request = playerGui:GetAttribute("DevGift")
		if typeof(request) == "string" and request ~= "" then
			playerGui:SetAttribute("DevGift", nil)
			self:DevPress(request)
		end
	end))
	if RunService:IsStudio() then
		table.insert(self.Connections, playerGui:GetAttributeChangedSignal("DevGiftFavorited"):Connect(function()
			if playerGui:GetAttribute("DevGiftFavorited") == true then
				task.spawn(function()
					if reportFavorite() then
						self:Refresh(false)
					end
				end)
			end
		end))
	end

	self:WatchRing()
	self:Refresh(false)
	-- The group answer comes from the server once it has the profile.
	task.delay(2, function()
		self:Refresh(true)
	end)
	print("[CLIENT]: Gift panel ready")
end

return api

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local UserInterfaceLoader = require(ReplicatedStorage.Modules.UserInterfaceLoader)
local PanelMetrics = require(ReplicatedStorage.Modules.PanelMetrics)
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")
local SoundController = ControllerLoader.GetController("SoundController")
local MusicManager = require(ReplicatedStorage.Modules.MusicManager)
local HapticUtil = require(ReplicatedStorage.Modules.HapticUtil)

local Player = Players.LocalPlayer

--=====================================================================
-- Responsive contract (see ReplicatedStorage.Modules.PanelMetrics).
-- The panel is a FIXED-PIXEL canvas driven by one root UIScale, exactly like
-- Pets / Shop / Settings / Vault / Door. The canvas is the design's own
-- 1920x1080 footprint, which is what makes the shared close button land at
-- 72x72 here just as it does on every other figma panel.
--
-- This replaced `frame.Size = UDim2.fromOffset(ViewportSize.X * 0.2864, ...)`,
-- which (a) scaled off viewport WIDTH only, so a short window pushed the panel
-- off the top and bottom edges, (b) left every UIStroke frozen at its authored
-- pixel width, and (c) had no guard against the 1x1 placeholder viewport the
-- camera reports on the first frames -- when it hit that, the panel was set to
-- 0x0 and stayed there.
--=====================================================================
local DESIGN_W, DESIGN_H = 550, 550
--.. Content box in design px: the heading overhangs 84px above the panel and
--.. the close button 36px past its right edge; both must stay on screen.
local CONTENT_TOP, CONTENT_RIGHT = -84, 586

local Module = {}
local frame, rebirthButton
local rebirthLabel, requiredLabel, ownedLabel, amountLabel, informationLabel, vaultLabel
local busy, armed = false, false

local function suffix(value) return NumberController.SuffixNumber(value or 0) end
local function setButton(text)
	local holder = rebirthButton and rebirthButton:FindFirstChild("Frame")
	local label = holder and holder:FindFirstChildWhichIsA("TextLabel")
	if label then label.Text = text end
end

function Module.Refresh()
	if not frame then return end
	local ok, info = pcall(function() return Network:InvokeServer("GetRebirthInfo") end)
	if not ok or type(info) ~= "table" then return end
	rebirthLabel.Text = string.format("%d REBIRTHS", info.Rebirths or 0)
	requiredLabel.Text = suffix(info.Cost)
	ownedLabel.Text = "(YOU HAVE " .. suffix(info.Coins) .. ")"
	amountLabel.Text = suffix(info.Cost)
	--.. current number in red, arrow, next number in the line's lime
	if info.AtMax then
		informationLabel.Text = string.format("CUCUMBERS & SELL VALUE +%d%% (MAX)", info.Bonus or 0)
	else
		informationLabel.Text = string.format('CUCUMBERS & SELL VALUE <font color="#FF4545">+%d%%</font> \u{2192} +%d%%', info.Bonus or 0, info.NextBonus or 0)
	end
	if vaultLabel and info.VaultSlots then
		if info.AtMax then
			vaultLabel.Text = string.format("SLOTS IN VAULT: %d \u{2022} %d FLOORS (MAX)", info.VaultSlots, info.VaultFloors or 1)
		elseif (info.NextVaultFloors or 1) > (info.VaultFloors or 1) then
			--.. the next rebirth's slot opens a whole new storey: shout it
			vaultLabel.Text = string.format('SLOTS IN VAULT: <font color="#FF4545">%d</font> \u{2192} %d (+FLOOR %d!)', info.VaultSlots, info.NextVaultSlots or info.VaultSlots, info.NextVaultFloors)
		else
			vaultLabel.Text = string.format('SLOTS IN VAULT: <font color="#FF4545">%d</font> \u{2192} %d', info.VaultSlots, info.NextVaultSlots or info.VaultSlots)
		end
	end
	armed = false
	setButton(info.CanAfford and "REBIRTH NOW!" or "KEEP FARMING...")
end
function Module.OnOpen() Module.Refresh() end
function Module.OnClose() armed = false end
function Module.GetModules() end

--=====================================================================
-- Rebirth celebration (SFX pass 2026-08-26). ONE function for BOTH paths:
-- the panel's DoRebirth success branch below, and the server-fired
-- "RebirthFX" net event (free playtime rebirths -> RebirthService.GrantFree),
-- which ClientNetwork routes here. info = {Before = rebirth count before}.
--=====================================================================
local CelebrationBusy = false
function Module.PlayCelebration(info)
	if CelebrationBusy then return end
	CelebrationBusy = true
	task.delay(8, function() CelebrationBusy = false end)

	local beforeCount = type(info) == "table" and tonumber(info.Before) or nil

	--.. (a) fanfare: full until t=5s, fade to 0 over 1.5s, then stop
	local Fanfare = SoundController.PlayFX("Rebirth Fanfare", {Volume = 0.6; Key = "RebirthFanfare"; MinInterval = 5; MaxLife = 8;})
	if Fanfare then
		task.delay(5, function()
			if not Fanfare.Parent then return end
			TweenService:Create(Fanfare, TweenInfo.new(1.5), {Volume = 0}):Play()
			task.delay(1.5, function()
				pcall(function()
					Fanfare:Stop()
					Fanfare:Destroy()
				end)
			end)
		end)
	end

	--.. (b) duck all music during the big moment
	pcall(function() MusicManager.SetDuck("Rebirth", 0.25, 0.3) end)
	task.delay(6, function()
		pcall(function() MusicManager.ClearDuck("Rebirth", 1) end)
	end)

	pcall(HapticUtil.Pulse, 1, 0.4, "Large")

	--.. the vault rebuild lands
	task.delay(1.2, function()
		SoundController.PlayFX("Big Thud", {Volume = 0.4})
	end)

	local PlayerGui = Player:FindFirstChild("PlayerGui")

	--.. (c) white -> gold full-screen bloom (SellBloom recipe, tinted gold, ~1.2s)
	task.spawn(function()
		local SellScreen = PlayerGui and PlayerGui:FindFirstChild("SellBloom")
		local Bloom = SellScreen and SellScreen:FindFirstChild("SellBloom")
		if not Bloom then return end
		Bloom.ImageColor3 = Color3.fromRGB(255, 255, 255)
		Bloom.ImageTransparency = 1
		SellScreen.Enabled = true
		local t = TweenService:Create(Bloom, TweenInfo.new(0.25), {ImageTransparency = 0.3})
		t:Play()
		t.Completed:Wait()
		TweenService:Create(Bloom, TweenInfo.new(0.95), {
			ImageTransparency = 1;
			ImageColor3 = Color3.fromRGB(255, 200, 40);
		}):Play()
	end)

	--.. (d) light radial star burst + (e) "REBIRTH N -> N+1" for 2s
	task.spawn(function()
		if not PlayerGui then return end
		local Gui = Instance.new("ScreenGui")
		Gui.Name = "RebirthCelebration"
		Gui.DisplayOrder = 10001
		Gui.IgnoreGuiInset = true
		Gui.ResetOnSpawn = false
		Gui.Parent = PlayerGui

		for i = 1, 10 do
			local Star = Instance.new("ImageLabel")
			Star.BackgroundTransparency = 1
			Star.Image = "rbxasset://textures/particles/sparkles_main.dds"
			Star.ImageColor3 = Color3.fromRGB(255, 220, 90)
			Star.AnchorPoint = Vector2.new(0.5, 0.5)
			Star.Position = UDim2.fromScale(0.5, 0.5)
			Star.Size = UDim2.fromOffset(46, 46)
			Star.Rotation = math.random(-180, 180)
			Star.Parent = Gui
			local Angle = (i / 10) * math.pi * 2 + math.random() * 0.4
			local Distance = math.random(220, 420)
			TweenService:Create(Star, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(Angle) * Distance, 0.5, math.sin(Angle) * Distance);
				ImageTransparency = 1;
				Rotation = Star.Rotation + math.random(-200, 200);
				Size = UDim2.fromOffset(14, 14);
			}):Play()
		end

		local Label = Instance.new("TextLabel")
		Label.BackgroundTransparency = 1
		Label.AnchorPoint = Vector2.new(0.5, 0.5)
		Label.Position = UDim2.fromScale(0.5, 0.42)
		Label.Size = UDim2.fromScale(0.6, 0.12)
		Label.Font = Enum.Font.FredokaOne
		Label.TextScaled = true
		Label.TextColor3 = Color3.fromRGB(255, 220, 80)
		Label.Text = beforeCount and string.format("REBIRTH %d \u{2192} %d", beforeCount, beforeCount + 1) or "REBIRTH!"
		local Stroke = Instance.new("UIStroke")
		Stroke.Thickness = 3
		Stroke.Color = Color3.fromRGB(120, 60, 0)
		Stroke.Parent = Label
		local LabelScale = Instance.new("UIScale")
		LabelScale.Scale = 0
		LabelScale.Parent = Label
		Label.Parent = Gui
		TweenService:Create(LabelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		task.wait(2)
		TweenService:Create(Label, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(Stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.wait(0.4)
		Gui:Destroy()
	end)

	--.. (f) short camera pan toward the vault, restored EXACTLY afterward.
	--.. Skips cleanly when the bank is missing or the camera is already
	--.. scripted (e.g. a hatch reveal owns it).
	task.spawn(function()
		local Camera = workspace.CurrentCamera
		if not Camera or Camera.CameraType == Enum.CameraType.Scriptable then return end
		local Bank = workspace:FindFirstChild("CucumberBank")
		local Slab = Bank and Bank:FindFirstChild("DeckSlab", true)
		if not (Slab and Slab:IsA("BasePart")) then return end
		local SavedType = Camera.CameraType
		local SavedCFrame = Camera.CFrame
		Camera.CameraType = Enum.CameraType.Scriptable
		pcall(function()
			local Goal = CFrame.lookAt(Slab.Position + Vector3.new(0, 22, 34), Slab.Position)
			local Value = Instance.new("CFrameValue")
			Value.Value = Camera.CFrame
			--.. TweenService silently never plays tweens on UNPARENTED instances
			--.. (this hung Completed:Wait() forever and stranded the camera in
			--.. Scriptable -- caught in the 2026-08-26 SFX-pass playtest)
			Value.Parent = Camera
			local Conn = Value:GetPropertyChangedSignal("Value"):Connect(function()
				Camera.CFrame = Value.Value
			end)
			local Tween = TweenService:Create(Value, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Value = Goal})
			local Done = false
			Tween.Completed:Once(function() Done = true end)
			Tween:Play()
			local T0 = os.clock()
			while not Done and os.clock() - T0 < 2.5 do task.wait(0.05) end
			task.wait(0.6)
			Conn:Disconnect()
			Value:Destroy()
		end)
		--.. restore OUTSIDE the pcall: no error path may strand the camera
		Camera.CFrame = SavedCFrame
		Camera.CameraType = SavedType
	end)
end

function Module.OnStart(interface)
	frame = interface
	frame.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
	PanelMetrics.bind(frame, {
		DesignW = DESIGN_W,
		DesignH = DESIGN_H,
		ContentTop = CONTENT_TOP,
		ContentRight = CONTENT_RIGHT,
	})

	local infoPanel = frame:WaitForChild("InnerFrame")
	rebirthLabel = infoPanel:WaitForChild("RebirthText")
	informationLabel = infoPanel:WaitForChild("InformationText")
	vaultLabel = infoPanel:WaitForChild("VaultValue")
	--.. both lines mix red current numbers into lime text via RichText. A
	--.. UIGradient MULTIPLIES RichText colors (red under the lime gradient
	--.. renders as mud), so the gradient is swapped for its own flat lime.
	for _, lbl in ipairs({informationLabel, vaultLabel}) do
		local grad = lbl:FindFirstChildOfClass("UIGradient")
		if grad then grad.Enabled = false end
		lbl.TextColor3 = Color3.fromRGB(96, 247, 24)
		lbl.RichText = true
	end
	local cost = infoPanel:WaitForChild("InnerFrame")
	requiredLabel = cost:WaitForChild("RequiredAmountText")
	ownedLabel = cost:WaitForChild("OwnedAmountText")
	--.. NOTE: Amount / Icon / Description are leftovers from the Vault panel
	--.. this canvas was branched from. They sit inside InnerFrame's rect at a
	--.. lower ZIndex, so InnerFrame's opaque BG covers them completely. Kept
	--.. (and still written to) so nothing here can throw; delete them in the
	--.. explorer if the design is ever revisited.
	amountLabel = frame:WaitForChild("Amount")
	--.. no KeepFarmingButton anymore (removed 2026-08-25): the live panel never
	--.. had one, so the old WaitForChild here hung forever and left the whole
	--.. panel inert. Closing is the shared X -- Main wires every frame's
	--.. CloseButton generically.
	rebirthButton = frame:WaitForChild("RebirthButton")

	local scale = rebirthButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", rebirthButton)
	rebirthButton.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(.12, Enum.EasingStyle.Quad), {Scale=1.08}):Play() end)
	rebirthButton.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(.12, Enum.EasingStyle.Quad), {Scale=1}):Play() end)
	rebirthButton.Activated:Connect(function()
		if busy then return end
		if not armed then
			armed=true; setButton("CLICK AGAIN TO CONFIRM!")
			task.delay(3,function() if armed then armed=false; Module.Refresh() end end)
			return
		end
		armed,busy=false,true
		local before=Network:InvokeServer("GetRebirthInfo")
		local result=Network:InvokeServer("DoRebirth")
		busy=false
		if before and type(result)=="number" and result>(before.Rebirths or 0) then
			Module.PlayCelebration({Before = before.Rebirths or 0})
			UserInterfaceLoader.GetInterface("Main").OpenFrame("Rebirth")
		else Module.Refresh() end
	end)
	Module.Refresh()
end
return Module

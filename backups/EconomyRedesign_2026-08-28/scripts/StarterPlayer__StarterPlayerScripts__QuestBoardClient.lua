--[[
	QuestBoardClient (2026-08-27) -- renders workspace.QuestBoard for this player.
	Reads the JSON "QuestState" player attribute QuestBoardService maintains:
	fills the three QuestList cards (title / progress / DONE), swaps the catch
	card's IconSlot for a ViewportFrame showing the target cucumber (model from
	ReplicatedStorage.QuestTargetModels), arms the green button as a CLAIM
	button when a quest finishes (fires "QuestClaim"), toasts newly finished
	quests with the DoorArrowClient affordToast style, and while every quest is
	claimed shows a local-only overhead billboard counting down
	"Resets in hh:mm:ss" (server rerolls when the window lapses).
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

local player = Players.LocalPlayer
local board = workspace:WaitForChild("QuestBoard", 30)
local boardPart = board and board:WaitForChild("Board", 10)
local sharedGui = boardPart and boardPart:WaitForChild("SurfaceGui", 10)
if not (sharedGui and sharedGui:WaitForChild("QuestList", 10)) then
	warn("[QuestBoardClient] quest board gui unavailable; wiring skipped.")
	return
end
--.. ViewportFrames never draw inside a workspace-parented SurfaceGui: adopt a
--.. PlayerGui clone ADORNED to the board part (same render spot, viewports and
--.. button input both fully supported) and hide the authored face locally.
local gui = sharedGui:Clone()
gui.Name = "QuestBoardGuiLocal"
gui.ResetOnSpawn = false
gui.Adornee = boardPart
gui.Parent = player:WaitForChild("PlayerGui")
sharedGui.Enabled = false
local list = gui:WaitForChild("QuestList", 10)
local targetModels = ReplicatedStorage:WaitForChild("QuestTargetModels", 20)

local DONE_COLOR = Color3.fromRGB(90, 230, 100)
local CLAIMED_BTN = "\u{2705} CLAIMED"
local function minutesOf(q)
	return math.floor((q.Reward or 300) / 60)
end

local baseStatColors = {}
for i = 1, 3 do
	local card = list:FindFirstChild("QuestCard" .. i)
	local stat = card and card:FindFirstChild("StatPanel") and card.StatPanel:FindFirstChild("Value")
	if stat then baseStatColors[i] = stat.TextColor3 end
	--.. green button = the claim control (server re-validates every fire)
	local btn = card and card:FindFirstChild("UpgradeButton")
	if btn then
		btn.Activated:Connect(function()
			Network:FireServer("QuestClaim", i)
		end)
	end
end

--.. DoorArrowClient affordToast recipe (2026-08-22), retinted for quests
local function questToast(text)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local toast = Instance.new("ScreenGui")
	toast.Name = "QuestToast"
	toast.ResetOnSpawn = false
	toast.DisplayOrder = 42
	toast.Parent = pg
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.16, 0)
	label.Size = UDim2.new(0.85, 0, 0.07, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Color3.fromRGB(150, 255, 150)
	label.Parent = toast
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(25, 45, 25)
	stroke.Parent = label
	task.delay(7, function() toast:Destroy() end)
end

--.. catch card: swap the flat IconSlot for a live viewport of the target
local currentViewportTarget
local function setCatchViewport(card, targetName)
	local icon = card:FindFirstChild("IconSlot")
	local vp = card:FindFirstChild("TargetViewport", true)
	if not vp then
		vp = Instance.new("ViewportFrame")
		vp.Name = "TargetViewport"
		vp.BackgroundTransparency = 1
		if icon then
			--.. nest inside the authored icon slot so the produce sits on the
			--.. same rounded dark backdrop as the other quest icons (the slot's
			--.. aspect constraint already squares it; small inset clears the stroke)
			vp.Size = UDim2.new(1, -6, 1, -6)
			vp.Position = UDim2.new(0.5, 0, 0.5, 0)
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Parent = icon
		else
			vp.Size = UDim2.new(0.2, 0, 0.8, 0)
			vp.Position = UDim2.new(0.02, 0, 0.1, 0)
			vp.Parent = card
		end
	end
	if currentViewportTarget == targetName then return end
	currentViewportTarget = targetName
	--.. keep the UI constraints (the aspect ratio IS the frame's width);
	--.. only the old scene gets rebuilt
	for _, c in ipairs(vp:GetChildren()) do
		if c:IsA("WorldModel") or c:IsA("Camera") then c:Destroy() end
	end
	local template = targetModels and targetModels:FindFirstChild(targetName)
	if not template then
		task.delay(3, function()
			--.. the server publishes the model moments after rolling; retry once
			if currentViewportTarget == targetName and targetModels then
				local late = targetModels:FindFirstChild(targetName)
				if late then
					currentViewportTarget = nil
					setCatchViewport(card, targetName)
				end
			end
		end)
		return
	end
	local model = template:Clone()
	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	model.Parent = wm
	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z, 1)
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.15, 0.25, 1).Unit * extent * 0.95, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

local resetGui, resetLabel
local function ensureResetGui()
	if resetGui then return end
	resetGui = Instance.new("BillboardGui")
	resetGui.Name = "QuestResetGui"
	resetGui.Adornee = boardPart
	resetGui.Size = UDim2.new(0, 260, 0, 48)
	resetGui.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	resetGui.AlwaysOnTop = false
	resetGui.MaxDistance = 90
	resetLabel = Instance.new("TextLabel")
	resetLabel.Size = UDim2.new(1, 0, 1, 0)
	resetLabel.BackgroundTransparency = 1
	resetLabel.Font = Enum.Font.FredokaOne
	resetLabel.TextScaled = true
	resetLabel.TextColor3 = Color3.fromRGB(255, 221, 84)
	resetLabel.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(35, 30, 20)
	stroke.Parent = resetLabel
	resetLabel.Parent = resetGui
	resetGui.Parent = boardPart -- created locally, so only this player sees it
end

local currentResetAt
local lastDone = {}

local function refresh()
	local raw = player:GetAttribute("QuestState")
	if type(raw) ~= "string" then return end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(data) ~= "table" then return end
	for i = 1, 3 do
		local card = list:FindFirstChild("QuestCard" .. i)
		local q = data.Quests and data.Quests[i]
		if card and q then
			local title = card:FindFirstChild("UpgradeName")
			local stat = card:FindFirstChild("StatPanel") and card.StatPanel:FindFirstChild("Value")
			local btn = card:FindFirstChild("UpgradeButton")
			local price = btn and btn:FindFirstChild("Price")
			if title then
				if q.Type == "Smash" then
					title.Text = ("SMASH %d CUCUMBERS"):format(q.Need or 0)
				elseif q.Type == "Chests" then
					title.Text = ("COLLECT %d CHESTS"):format(q.Need or 0)
				elseif q.Type == "Catch" then
					title.Text = ("CATCH A %s"):format(string.upper(q.Target or "CUCUMBER"))
				end
			end
			if q.Type == "Catch" and q.Target then
				setCatchViewport(card, q.Target)
			end
			if stat then
				if q.Done then
					stat.Text = "\u{2705} DONE"
					stat.TextColor3 = DONE_COLOR
				else
					stat.Text = ("%d/%d"):format(q.Have or 0, q.Need or 0)
					stat.TextColor3 = baseStatColors[i] or stat.TextColor3
				end
			end
			if btn and price then
				if q.Done and not q.Claimed then
					price.Text = ("\u{23F1} CLAIM %d MIN TIME SKIP!"):format(minutesOf(q))
					btn.Active = true
					btn.AutoButtonColor = true
				elseif q.Done and q.Claimed then
					price.Text = CLAIMED_BTN
					btn.Active = false
					btn.AutoButtonColor = false
				else
					price.Text = ("\u{23F1} %d MIN TIME SKIP"):format(minutesOf(q))
					btn.Active = false
					btn.AutoButtonColor = false
				end
			end
			--.. big-toast newly finished quests (DoorArrowClient style)
			if q.Done and lastDone[i] == false then
				questToast("\u{1F3AF} QUEST COMPLETE! CLAIM YOUR TIME SKIP AT THE QUEST BOARD!")
			end
			lastDone[i] = q.Done and true or false
		end
	end
	currentResetAt = data.ResetAt
end

player:GetAttributeChangedSignal("QuestState"):Connect(refresh)
refresh()

task.spawn(function()
	while true do
		task.wait(1)
		local left = currentResetAt and (currentResetAt - os.time()) or 0
		if left > 0 then
			ensureResetGui()
			resetGui.Enabled = true
			resetLabel.Text = ("Resets in %02d:%02d:%02d"):format(
				math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
		elseif resetGui then
			resetGui.Enabled = false
		end
	end
end)

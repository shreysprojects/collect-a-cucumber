-- SelectingRewardClient  (LocalScript, StarterGui.SelectingReward)  New Map port 2026-09-23
-- Drives the imported "SelectingReward" reward reel (design from Place1, transferred from the Zombie
-- Cucumber Game) as the New Map's PORTAL REWARD spinner. Same Play/Ready interface as the zombie one:
-- RewardSpinnerClient invokes the Play BindableFunction with the server-chosen selection, the horizontal
-- reel spins and lands the matching tile under the Arrow, then the heading reveals the reward.
-- Reward ids (RewardSpinnerService): cash_<d> / strength_<d> (shown as their VALUE: "+$2.5M" / "+12.3K
-- Strength", never as a time skip) and item_<Key> (one drop item, drawn as its real model).
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gui = script.Parent
local frame = gui:WaitForChild("RewardFrame")
local upper = frame:WaitForChild("Upper")
local heading = upper:WaitForChild("Heading")
local lower = frame:WaitForChild("Lower")
local arrow = lower:WaitForChild("Arrow")
local container = lower:WaitForChild("Container")
local template = container:WaitForChild("TemplateFrame")

gui.DisplayOrder = 10000
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))
local SoundController = require(Modules:WaitForChild("SoundController"))
local Items = require(Modules:WaitForChild("ItemsCatalog"))

local CASH_ICON = "rbxassetid://15402858705" -- the HUD's cash icon
local STRENGTH_ICON = "rbxassetid://15403007921" -- the HUD's strength arm
local DURATIONS = {["1m"] = 60, ["2m"] = 120, ["5m"] = 300, ["10m"] = 600, ["15m"] = 900, ["30m"] = 1800, ["1h"] = 3600}
local RARITY_BY_SECONDS = {{1800, "Epic"}, {600, "Rare"}, {300, "Uncommon"}, {0, "Common"}}
local ORDER = {
	"cash_1m", "cash_2m", "cash_5m", "cash_10m", "cash_15m", "cash_30m", "cash_1h",
	"strength_1m", "strength_2m", "strength_5m", "strength_10m", "strength_15m", "strength_30m",
	"item_SpeedPotion", "item_StrengthPotion", "item_CashPotion", "item_WarpPearl", "item_HolyWater",
	"item_GoldenSeed", "item_RedemptionToken", "item_ZombieEgg", "item_VoidSeed",
}
local SPIN_SECONDS = 6
local REWARD_SECONDS = 3
local PADDING = 22
local TOTAL = 48
local MODEL_VIEW = {dir = Vector3.new(0.35, 0.166, 0.92), zoom = 2.1}

local function rarityForSeconds(seconds)
	for _, row in ipairs(RARITY_BY_SECONDS) do
		if seconds >= row[1] then return row[2] end
	end
	return "Common"
end

--.. one reward id -> how its tile reads {amount, rarity, icon | model}
local function resolveReward(id, selection)
	if type(id) ~= "string" then return nil end
	local kind, rest = id:match("^(%a+)_(.+)$")
	if kind == "cash" and DURATIONS[rest] then
		local amounts = type(selection) == "table" and selection.cashAmounts or nil
		local amount = type(amounts) == "table" and tonumber(amounts[id])
		return {amount = amount and ("+$" .. NumberAbbrev.Abbrev(math.floor(amount)) .. " Cash") or "+Cash", rarity = rarityForSeconds(DURATIONS[rest]), icon = CASH_ICON}
	end
	if kind == "strength" and DURATIONS[rest] then
		local amounts = type(selection) == "table" and selection.strengthAmounts or nil
		local amount = type(amounts) == "table" and tonumber(amounts[id])
		return {amount = amount and ("+" .. NumberAbbrev.Abbrev(math.floor(amount)) .. " Strength") or "+Strength", rarity = rarityForSeconds(DURATIONS[rest]), icon = STRENGTH_ICON}
	end
	if kind == "item" then
		local def = Items.Get(rest)
		local info = type(selection) == "table" and type(selection.items) == "table" and selection.items[id] or nil
		local name = (info and info.Name) or (def and def.Name) or rest
		local rarity = (info and info.Rarity) or (def and def.Rarity) or "Rare"
		if def or info then return {amount = "+1 " .. name, rarity = rarity, model = rest} end
	end
	return nil
end

--.. take manual control of the reel: drop the auto layout, keep the tile as an off-screen template, and
--.. add a holder frame we can slide left to spin
local layout = container:FindFirstChildOfClass("UIListLayout")
if layout then layout:Destroy() end
template.Parent = gui
template.Visible = false
for _, extra in ipairs(container:GetChildren()) do
	if extra.Name == "TemplateFrame" then extra:Destroy() end
end
local holder = container:FindFirstChild("SpinHolder")
if not holder then
	holder = Instance.new("Frame")
	holder.Name = "SpinHolder"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.fromScale(0, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = false
	holder.Parent = container
end

--.. end-of-spin reveal: the panel hides and only this centred text shows the won reward
local revealLabel = gui:FindFirstChild("RewardRevealText")
if not revealLabel then
	revealLabel = heading:Clone()
	revealLabel.Name = "RewardRevealText"
	revealLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	revealLabel.Position = UDim2.fromScale(0.5, 0.5)
	revealLabel.Size = UDim2.fromScale(0.72, 0.13)
	revealLabel.Visible = false
	revealLabel.Parent = gui
end

local rewardSound = gui:FindFirstChild("RewardSound")
if not rewardSound then
	rewardSound = Instance.new("Sound")
	rewardSound.Name = "RewardSound"
	rewardSound.SoundId = "rbxassetid://7933571710"
	rewardSound.Parent = gui
end
rewardSound.Volume = 1.0

--.. the tile has two TextLabels both named "Amount": the top one is the amount, the lower one the rarity
local function tileLabels(tile)
	local amount, rarity
	local low = tile:FindFirstChild("Lower")
	if low then
		for _, c in ipairs(low:GetChildren()) do
			if c:IsA("TextLabel") then
				if c.Position.Y.Scale < 0.5 then amount = c else rarity = c end
			end
		end
	end
	return amount, rarity
end

local function itemModel(key)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Items")
	return folder and folder:FindFirstChild(key) or nil
end

local function setTile(tile, id, selection)
	local d = resolveReward(id, selection)
	if not d then return end
	local a, r = tileLabels(tile)
	if a then a.Text = d.amount end
	if r then r.Text = d.rarity end
	local iconLabel = tile:FindFirstChild("RewardIcon")
	if iconLabel then
		iconLabel.Image = d.icon or ""
		iconLabel.Visible = d.icon ~= nil
	end
	--.. 3D rewards render the actual item model; tiles are cloned per spin and destroyed by clearGenerated
	if d.model then
		local source = itemModel(d.model)
		if source then
			local vp = Instance.new("ViewportFrame")
			vp.Name = "RewardModel"
			vp.BackgroundTransparency = 1
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Position = UDim2.fromScale(0.5, 0.36)
			vp.Size = UDim2.fromScale(0.66, 0.58)
			vp.Ambient = Color3.fromRGB(220, 220, 220)
			vp.LightColor = Color3.fromRGB(255, 255, 255)
			vp.LightDirection = Vector3.new(-1, -1, -1)
			vp.ZIndex = 6
			local world = Instance.new("WorldModel")
			world.Parent = vp
			local clone = source:Clone()
			clone.Parent = world
			local cf, size = clone:GetBoundingBox()
			clone:PivotTo(clone:GetPivot() - cf.Position)
			local camera = Instance.new("Camera")
			camera.FieldOfView = 32
			camera.CFrame = CFrame.lookAt(MODEL_VIEW.dir.Unit * (math.max(size.X, size.Y, size.Z, 0.5) * MODEL_VIEW.zoom), Vector3.zero)
			camera.Parent = vp
			vp.CurrentCamera = camera
			vp.Parent = tile
		end
	end
end

local generated = {}
local function clearGenerated()
	for _, t in ipairs(generated) do
		if t.Parent then t:Destroy() end
	end
	table.clear(generated)
end

local busy = false

local function play(selection)
	local selectedId = type(selection) == "table" and selection.id or selection
	if busy then return selectedId end
	busy = true

	gui.Enabled = true
	frame.Visible = true
	revealLabel.Visible = false
	heading.Text = "SELECTING REWARD..."
	holder.Position = UDim2.fromScale(0, 0.5)
	clearGenerated()

	RunService.RenderStepped:Wait()
	local itemW = template.Size.X.Scale * math.max(1, container.AbsoluteSize.X)
	local stride = itemW + PADDING

	local winner = resolveReward(selectedId, selection) and selectedId or ORDER[math.random(1, #ORDER)]
	local targetIndex = TOTAL - math.random(3, 7)

	--.. filler tiles: skip rate cards the server did not quote (nothing placed = no "+$0 Cash" card)
	local fillerOrder = {}
	for _, fillerId in ipairs(ORDER) do
		local kind = fillerId:match("^(%a+)_")
		local quoted = true
		if kind == "cash" then quoted = type(selection) == "table" and type(selection.cashAmounts) == "table" and tonumber(selection.cashAmounts[fillerId]) ~= nil end
		if kind == "strength" then quoted = type(selection) == "table" and type(selection.strengthAmounts) == "table" and tonumber(selection.strengthAmounts[fillerId]) ~= nil end
		if quoted then table.insert(fillerOrder, fillerId) end
	end
	if #fillerOrder == 0 then fillerOrder = {winner} end

	for i = 1, TOTAL do
		local tile = template:Clone()
		tile.Name = "RewardTile" .. i
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, stride * (i - 1), 0.5, 0)
		tile.Visible = true
		local id = (i == targetIndex) and winner or fillerOrder[math.random(1, #fillerOrder)]
		setTile(tile, id, selection)
		tile.Parent = holder
		generated[i] = tile
	end

	RunService.RenderStepped:Wait()
	local target = generated[targetIndex]
	local targetCenter = target.AbsolutePosition.X + target.AbsoluteSize.X * 0.5
	local markerCenter = arrow.AbsolutePosition.X + arrow.AbsoluteSize.X * 0.5
	local destination = holder.Position - UDim2.fromOffset(targetCenter - markerCenter, 0)

	local tween = TweenService:Create(holder, TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = destination})
	--.. case-opening ticks: one EggClick each time a new tile crosses under the arrow, pitch creeping up
	local lastTickIndex, tickCount = nil, 0
	local tickConn = RunService.RenderStepped:Connect(function()
		local index = math.floor((markerCenter - holder.AbsolutePosition.X) / stride)
		if index ~= lastTickIndex then
			if lastTickIndex ~= nil then
				tickCount += 1
				pcall(SoundController.PlayFX, "EggClick", {Volume = 0.35, Speed = 1 + 0.02 * tickCount, Key = "RewardReelTick", MinInterval = 0.02})
			end
			lastTickIndex = index
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	tickConn:Disconnect()

	--.. winner beat: white flash + a quick wobble on the landed tile, THEN the cut
	do
		local tile = generated[targetIndex]
		if tile then
			local flash = Instance.new("Frame")
			flash.Name = "WinnerFlash"
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
			flash.BorderSizePixel = 0
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundTransparency = 0.1
			flash.ZIndex = 20
			flash.Parent = tile
			TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
			for _, rotation in ipairs({6, -5, 3, 0}) do
				TweenService:Create(tile, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = rotation}):Play()
				task.wait(0.08)
			end
			task.wait(0.1)
		end
	end

	--.. reveal: hide the reel and show only the reward's name, centred on screen
	local d = resolveReward(winner, selection)
	frame.Visible = false
	clearGenerated()
	revealLabel.Text = (d and d.amount or "REWARD") .. "!"
	revealLabel.Visible = true
	pcall(function() rewardSound:Play() end)
	task.wait(REWARD_SECONDS)

	revealLabel.Visible = false
	gui.Enabled = false
	clearGenerated()
	gui:SetAttribute("LastReward", winner)
	busy = false
	return winner
end

local playFn = gui:FindFirstChild("Play")
if not playFn then
	playFn = Instance.new("BindableFunction")
	playFn.Name = "Play"
	playFn.Parent = gui
end
playFn.OnInvoke = play

frame.Visible = false
gui.Enabled = false
gui:SetAttribute("Ready", true)
pcall(function()
	ContentProvider:PreloadAsync({arrow, upper:FindFirstChild("Ray")})
end)
print("[SelectingRewardClient] reward reel ready (cash / strength values + drop items)")

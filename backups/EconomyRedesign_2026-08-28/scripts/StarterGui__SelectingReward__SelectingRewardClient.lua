-- SelectingRewardClient
-- Drives the imported "SelectingReward" reward spinner (design from Place1) as the
-- minigame completion reward UI. Exposes the SAME Play/Ready interface the old
-- RewardSpinnerGui had, so MinigameCompletionClient drives it unchanged: it invokes the
-- Play BindableFunction with the server-chosen reward id, the horizontal reel spins and
-- lands the matching tile under the Arrow, then the heading reveals the reward.
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

--.. Reward ids the server hands us, mapped to tile presentation. Every cucumber
--.. amount is supplied by the server from the player's current production rate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local NumberController = ControllerLoader.GetController("NumberController")
local SoundController = ControllerLoader.GetController("SoundController")
local SettingsController = ControllerLoader.GetController("SettingsController")
local CUCUMBER_ICON = "rbxassetid://130860765613379" -- wallet/store cucumber pile
local SHARD_ICON = "rbxassetid://15402964203" -- the ShardEffect pickup burst shard
local COIN_ICON = "rbxassetid://15402839520" -- the wallet coin (same art as the store's coin tab)
local CUCUMBER_REWARDS = {
	cucumber_1m = true, cucumber_2m = true, cucumber_3m = true, cucumber_5m = true,
	cucumber_10m = true, cucumber_15m = true, cucumber_30m = true, cucumber_1h = true,
}
--.. coin prizes: exact amounts are quoted server-side from the player's vault
local COIN_REWARDS = {
	coins_2m = true, coins_5m = true, coins_15m = true, coins_30m = true,
}
local REWARDS = {
	cucumber_1m  = { amount = "+Cucumbers", rarity = "Common", icon = CUCUMBER_ICON },
	cucumber_2m  = { amount = "+Cucumbers", rarity = "Common", icon = CUCUMBER_ICON },
	cucumber_3m  = { amount = "+Cucumbers", rarity = "Uncommon", icon = CUCUMBER_ICON },
	cucumber_5m  = { amount = "+Cucumbers", rarity = "Uncommon", icon = CUCUMBER_ICON },
	cucumber_10m = { amount = "+Cucumbers", rarity = "Rare", icon = CUCUMBER_ICON },
	cucumber_15m = { amount = "+Cucumbers", rarity = "Rare", icon = CUCUMBER_ICON },
	cucumber_30m = { amount = "+Cucumbers", rarity = "Epic", icon = CUCUMBER_ICON },
	cucumber_1h  = { amount = "+Cucumbers", rarity = "Epic", icon = CUCUMBER_ICON },
	coins_2m     = { amount = "+Coins", rarity = "Uncommon", icon = COIN_ICON },
	coins_5m     = { amount = "+Coins", rarity = "Rare", icon = COIN_ICON },
	coins_15m    = { amount = "+Coins", rarity = "Epic", icon = COIN_ICON },
	coins_30m    = { amount = "+Coins", rarity = "Epic", icon = COIN_ICON },
	shard_1      = { amount = "+1 Boss Shard", rarity = "Rare", icon = SHARD_ICON },
	shard_3      = { amount = "+3 Boss Shards", rarity = "Epic", icon = SHARD_ICON },
	foodegg_1    = { amount = "+1 Food Cuke Egg", rarity = "Epic", model = "FoodEgg" },
}
--.. shard rewards arrive as composite ids ("shard_3_Volcano"): the server resolves
--.. WHICH boss's shard at pick time, and this map (mirror of BreakablesService's
--.. BOSS_PETS) turns the zone into the boss pet's name on the card and reveal.
local BOSS_PETS = {
	Spawn = "Colossal Cucumber"; Desert = "Cactus Colossus";
	Samurai = "Shogun Colossus"; Farm = "Harvest Colossus";
	Snow = "Frozen Colossus"; Underwater = "Abyssal Colossus";
	Volcano = "Magma Colossus"; Narmek = "Cosmic Colossus";
}
local function resolveReward(id, cucumberAmounts, coinAmounts)
	local d = REWARDS[id]
	if d and CUCUMBER_REWARDS[id] then
		local amount = type(cucumberAmounts) == "table" and tonumber(cucumberAmounts[id])
		return {
			amount = amount and ("+" .. NumberController.SuffixNumber(amount) .. " Cucumbers") or "+Cucumbers",
			rarity = d.rarity,
			icon = CUCUMBER_ICON,
		}
	end
	if d and COIN_REWARDS[id] then
		local amount = type(coinAmounts) == "table" and tonumber(coinAmounts[id])
		return {
			amount = amount and ("+$" .. NumberController.SuffixNumber(amount) .. " Coins") or "+Coins",
			rarity = d.rarity,
			icon = COIN_ICON,
		}
	end
	if d then return d end
	if type(id) == "string" then
		local count, zone = id:match("^shard_(%d+)_(%a+)$")
		if count then
			local base = REWARDS["shard_" .. count]
			return {
				amount = ("+%s %s Shard%s"):format(count, BOSS_PETS[zone] or "Boss", count == "1" and "" or "s"),
				rarity = base and base.rarity or "Epic",
				icon = SHARD_ICON,
			}
		end
	end
	return nil
end

--.. The egg reads best from the classic 3/4 camera angle.
local MODEL_SOURCES = {
	FoodEgg = {
		dir = Vector3.new(0.55, 0.4, 1),
		zoom = 1.4,
		get = function()
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			local eggs = assets and assets:FindFirstChild("Eggs")
			return eggs and eggs:FindFirstChild("Food Cuke Egg")
		end,
	},
}
local ORDER = {
	"cucumber_1m", "cucumber_2m", "cucumber_3m", "cucumber_5m",
	"cucumber_10m", "cucumber_15m", "cucumber_30m", "cucumber_1h",
	"coins_2m", "coins_5m", "coins_15m", "coins_30m",
	"shard_1", "shard_3", "foodegg_1",
}

local SPIN_SECONDS = 6
local REWARD_SECONDS = 3
local PADDING = 22
local TOTAL = 48

--.. take manual control of the reel: drop the auto layout, keep the tile as an
--.. off-screen template, and add a holder frame we can slide left to spin
local layout = container:FindFirstChildOfClass("UIListLayout")
if layout then layout:Destroy() end
template.Parent = gui
template.Visible = false
--.. the imported design shipped SEVERAL example cards named TemplateFrame; any left in
--.. the container after adopting the first would sit visibly behind the spinning reel
for _, extra in ipairs(container:GetChildren()) do
	if extra.Name == "TemplateFrame" then
		extra:Destroy()
	end
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

--.. end-of-spin reveal: the whole panel hides and ONLY this centered text shows
--.. the won reward's name. Cloned from the Heading so the font/stroke styling
--.. always matches the design.
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
--.. raw id (not in Assets.Sounds), so PlayFX can't route it: volume is pinned
--.. here and the play site below is gated on the SFX setting instead
rewardSound.Volume = 1.0

--.. the tile has two TextLabels both named "Amount": the top one is the amount, the
--.. lower one is the rarity -- tell them apart by their Y position
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

local function setTile(tile, id, cucumberAmounts, coinAmounts)
	local d = resolveReward(id, cucumberAmounts, coinAmounts)
	if not d then return end
	local a, r = tileLabels(tile)
	if a then a.Text = d.amount end
	if r then r.Text = d.rarity end

	local iconLabel = tile:FindFirstChild("RewardIcon")
	if iconLabel then
		iconLabel.Image = d.icon or ""
		iconLabel.Visible = d.icon ~= nil
	end

	--.. 3D rewards render the actual in-game model, mirroring the Playtime board.
	--.. Tiles are freshly cloned per spin and destroyed by clearGenerated, so the
	--.. viewport + model clone never outlive the reel.
	if d.model then
		local view = MODEL_SOURCES[d.model]
		local source = view and view.get()
		if source then
			local vp = Instance.new("ViewportFrame")
			vp.Name = "RewardModel"
			vp.BackgroundTransparency = 1
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Position = UDim2.fromScale(0.5, 0.36)
			vp.Size = UDim2.fromScale(0.66, 0.58)
			vp.Ambient = Color3.fromRGB(255, 255, 255)
			vp.LightColor = Color3.fromRGB(255, 255, 255)
			vp.LightDirection = Vector3.new(-1, -1, -1)
			vp.ZIndex = 6
			local clone = source:Clone()
			local boundsCFrame, boundsSize = clone:GetBoundingBox()
			clone.Parent = vp
			local camera = Instance.new("Camera")
			camera.FieldOfView = 40
			local dist = boundsSize.Magnitude * view.zoom
			camera.CFrame = CFrame.new(boundsCFrame.Position + view.dir.Unit * dist, boundsCFrame.Position)
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
	local cucumberAmounts = type(selection) == "table" and selection.cucumberAmounts or nil
	local coinAmounts = type(selection) == "table" and selection.coinAmounts or nil
	if busy then return selectedId end
	busy = true

	gui.Enabled = true
	frame.Visible = true
	revealLabel.Visible = false
	heading.Text = "SELECTING REWARD..."
	holder.Position = UDim2.fromScale(0, 0.5)
	clearGenerated()

	RunService.RenderStepped:Wait()
	--.. tile width is a scale of the container, so derive it from the container's real
	--.. width (robust even though the template now lives off-screen)
	local itemW = template.Size.X.Scale * math.max(1, container.AbsoluteSize.X)
	local stride = itemW + PADDING

	local winner = resolveReward(selectedId, cucumberAmounts, coinAmounts) and selectedId or ORDER[math.random(1, #ORDER)]
	local targetIndex = TOTAL - math.random(3, 7)

	--.. filler tiles: skip coin cards the server didn't quote (an empty vault
	--.. quotes nothing, and a "+0 Coins" card on the reel reads as a bug)
	local fillerOrder = {}
	for _, fillerId in ipairs(ORDER) do
		if not COIN_REWARDS[fillerId]
			or (type(coinAmounts) == "table" and tonumber(coinAmounts[fillerId])) then
			table.insert(fillerOrder, fillerId)
		end
	end
	--.. when the winner is a zone-specific shard, retarget the generic shard filler
	--.. tiles to the same boss so every shard card on the reel names that boss
	local shardZone = tostring(winner):match("^shard_%d+_(%a+)$")
	if shardZone then
		for i, fillerId in ipairs(fillerOrder) do
			local count = fillerId:match("^shard_(%d+)$")
			if count then
				fillerOrder[i] = "shard_" .. count .. "_" .. shardZone
			end
		end
	end

	for i = 1, TOTAL do
		local tile = template:Clone()
		tile.Name = "RewardTile" .. i
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, stride * (i - 1), 0.5, 0)
		tile.Visible = true
		local id = (i == targetIndex) and winner or fillerOrder[math.random(1, #fillerOrder)]
		setTile(tile, id, cucumberAmounts, coinAmounts)
		tile.Parent = holder
		generated[i] = tile
	end

	RunService.RenderStepped:Wait()
	local target = generated[targetIndex]
	local targetCenter = target.AbsolutePosition.X + target.AbsoluteSize.X * 0.5
	local markerCenter = arrow.AbsolutePosition.X + arrow.AbsoluteSize.X * 0.5
	local destination = holder.Position - UDim2.fromOffset(targetCenter - markerCenter, 0)

	local tween = TweenService:Create(
		holder,
		TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = destination }
	)
	--.. case-opening ticks (SFX pass 2026-08-26): one EggClick each time a new
	--.. tile crosses under the arrow; pitch creeps up per tick, and the Quart
	--.. easing naturally slows the tick rate to a crawl near the landing
	local lastTickIndex, tickCount = nil, 0
	local tickConn = RunService.RenderStepped:Connect(function()
		local index = math.floor((markerCenter - holder.AbsolutePosition.X) / stride)
		if index ~= lastTickIndex then
			if lastTickIndex ~= nil then
				tickCount += 1
				SoundController.PlayFX("EggClick", {Volume = 0.35; Speed = 1 + 0.02 * tickCount; Key = "RewardReelTick"; MinInterval = 0.02;})
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

	--.. reveal: hide the whole spinner panel and show only the reward's name,
	--.. centered on screen
	local d = resolveReward(winner, cucumberAmounts, coinAmounts)
	frame.Visible = false
	clearGenerated()
	revealLabel.Text = (d and d.amount or "REWARD") .. "!"
	revealLabel.Visible = true
	--.. gated the way PlayFX gates its own library sounds
	if SettingsController.ValidateSetting("SFX", false) then
		rewardSound:Play()
	end
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
	ContentProvider:PreloadAsync({ arrow, upper:FindFirstChild("Ray") })
end)
print("[SelectingRewardClient] Place1 reward spinner wired to minigame completion.")

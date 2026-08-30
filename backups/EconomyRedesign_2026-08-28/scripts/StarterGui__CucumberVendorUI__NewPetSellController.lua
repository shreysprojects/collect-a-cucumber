local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent
local frame = gui:WaitForChild("PetSellLayerNew")
local openEvent = gui:WaitForChild("OpenNewPetSell")
local scroll = frame:WaitForChild("ScrollingFrame")
local totalLabel = frame:WaitForChild("SelectedCoinText")
local sellButton = frame:WaitForChild("SellButton")
local closeButton = frame:WaitForChild("CloseButton")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")
local PetSellValues = require(ReplicatedStorage.Modules.PetSellValues)
local PanelMetrics = require(ReplicatedStorage.Modules.PanelMetrics)
local SellPets = ReplicatedStorage:WaitForChild("VendorRemotes"):WaitForChild("SellPets")
local Module3D = require(ReplicatedStorage.Shared.Module3D)

--.. Rarity tint for the card label. The game states each rarity as a two-stop GRADIENT
--.. (RarityController.Classes), and a TextColor3 needs one solid colour, so take the
--.. midpoint of that gradient: it stays recognisably "the rarity colour" while avoiding
--.. the near-white first stops (Common/Epic/Special) that would be unreadable on the
--.. panel. Read from RarityController rather than copied so re-tuning a rarity there
--.. moves these labels too.
local RarityController = require(ReplicatedStorage.Modules.FrameworkLoader.Client.EggController.RarityController)
--.. Pet rigs carry invisible collision/rig parts -- an oversized Root, and on some pets a
--.. Head box -- that dwarf the art: Lil Pickle's visible mesh is 1.9 studs inside a 4-stud
--.. bounding box. Module3D frames the BOUNDING BOX, so those parts alone shrank the pet to
--.. about half its card while pets whose Root is small (the bee) filled theirs. They are
--.. Transparency 1, so deleting them from the CLONE cannot change what is drawn.
local function stripInvisibleParts(model)
	local visible = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then visible += 1 end
	end
	if visible == 0 then return end --.. fully invisible pet: leave it alone rather than empty it
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency >= 1 then
			if model.PrimaryPart == d then model.PrimaryPart = nil end
			d:Destroy()
		end
	end
end

local rarityColorCache = {}
local function rarityColor(rarity)
	if rarityColorCache[rarity] then return rarityColorCache[rarity] end
	local colour = Color3.new(1, 1, 1)
	local class = rarity and RarityController.Classes and RarityController.Classes[rarity]
	local gradient = class and class.Gradient
	if gradient then
		local keys = gradient.Keypoints
		colour = keys[1].Value:Lerp(keys[#keys].Value, 0.5)
	end
	rarityColorCache[rarity] = colour
	return colour
end

--=====================================================================
-- Responsive contract (see ReplicatedStorage.Modules.PanelMetrics).
-- This window had NO responsive handling at all: it was a pure-Scale figma
-- export whose strokes never drew and whose grid could not be resized. It now
-- runs the same fixed-pixel-canvas + root UIScale contract as every panel
-- under Display.Frame.Frames, so it scales in lockstep with them even though
-- it lives in its own ScreenGui.
--
-- 770x640 is the design's 1920x1080 footprint (close button lands at 72x72,
-- same shared asset as Vault / Door / Rebirth).
--=====================================================================
local DESIGN_W, DESIGN_H = 770, 640
--.. Heading overhangs 48px above the panel, close button 36px past its right.
local CONTENT_TOP, CONTENT_RIGHT = -48, 806
--.. Authored scrollbar width in design px. UIScale scales TextSize, strokes
--.. and corner radii -- but NOT ScrollBarThickness, so that one is driven by
--.. hand from the same scale.
local SCROLLBAR_DESIGN_PX = 12

local selected = {}
local cards = {}
local previews = {}
local selling = false
local petDict

local template
for _, child in ipairs(scroll:GetChildren()) do
	if child:IsA("Frame") and child.Name == "Template" then
		template = template or child:Clone()
	end
end
for _, child in ipairs(scroll:GetChildren()) do
	if child:IsA("Frame") and child.Name == "Template" then child:Destroy() end
end
assert(template, "SellPets design has no Template")

frame.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
PanelMetrics.bind(frame, {
	DesignW = DESIGN_W,
	DesignH = DESIGN_H,
	ContentTop = CONTENT_TOP,
	ContentRight = CONTENT_RIGHT,
	--.. No Host: this panel is not under Display.Frame.Frames, so PanelMetrics
	--.. reproduces that box's width from the viewport instead. Same number.
	OnScale = function(scale)
		scroll.ScrollBarThickness = math.max(4, math.floor(SCROLLBAR_DESIGN_PX * scale + 0.5))
	end,
})

local function money(value)
	local s = tostring(math.floor(value or 0))
	while true do
		local n, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = n
		if count == 0 then break end
	end
	return s
end

local function clear()
	for _, preview in ipairs(previews) do pcall(function() preview:Destroy() end) end
	table.clear(previews)
	for _, card in ipairs(cards) do card:Destroy() end
	table.clear(cards)
	table.clear(selected)
end

local function totals()
	local count, coins = 0, 0
	for _, value in pairs(selected) do count += 1; coins += value end
	totalLabel.Text = string.format('SELECTED: <font color="#FFE033">%d - %s Coins</font>', count, money(coins))
	sellButton.Active = count > 0 and not selling
	sellButton.AutoButtonColor = count > 0 and not selling
end

local function rebuild()
	clear()
	totalLabel.Text = "LOADING..."
	local ok, userData = pcall(function() return Network:InvokeServer("GetUserData") end)
	if not petDict then
		local dictOk, dict = pcall(function()
			return Network:InvokeServer("GetData", "Dictionary", {Name = "Pets"})
		end)
		if dictOk and type(dict) == "table" then petDict = dict end
	end
	if not ok or type(userData) ~= "table" or type(userData.PetData) ~= "table" then
		totalLabel.Text = "COULDN'T LOAD PETS"
		return
	end

	local list = {}
	for id, pet in pairs(userData.PetData) do
		if id ~= "Unlocked" and type(pet) == "table" and pet.Name then
			local coins, rarity = PetSellValues.GetValue(pet, petDict and petDict[pet.Name])
			table.insert(list, {Id=id, Name=pet.Name, Coins=coins, Rarity=rarity, Craft=pet.Craft, Equipped=pet.Equipped == true})
		end
	end
	table.sort(list, function(a,b)
		if a.Coins ~= b.Coins then return a.Coins > b.Coins end
		return a.Name < b.Name
	end)

	for i, info in ipairs(list) do
		local card = template:Clone()
		card.Name = "Pet_" .. tostring(info.Id)
		card.LayoutOrder = i
		card.Visible = true
		card.NameBar.NameLabel.Text = info.Name .. (info.Craft == "Golden" and " (Golden)" or "")
		card.RarityLabel.Text = info.Rarity or "UNKNOWN"
		card.RarityLabel.TextColor3 = rarityColor(info.Rarity)
		card.Description.Text = money(info.Coins) .. " Coins"
		local button = card.SelectButton
		local buttonText = button.SelectLabel
		if info.Equipped then
			buttonText.Text = "EQUIPPED"
			button.Active = false
			button.AutoButtonColor = false
		else
			buttonText.Text = "SELECT"
			button.Activated:Connect(function()
				if selected[info.Id] then
					selected[info.Id] = nil
					buttonText.Text = "SELECT"
				else
					local count = 0
					for _ in pairs(selected) do count += 1 end
					if count >= 50 then
						totalLabel.Text = "YOU CAN SELL 50 PETS AT A TIME"
						return
					end
					selected[info.Id] = info.Coins
					buttonText.Text = "SELECTED"
				end
				totals()
			end)
		end
		card.Parent = scroll
		table.insert(cards, card)

		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local pets = assets and assets:FindFirstChild("Pets")
		local model = pets and pets:FindFirstChild(info.Name)
		if model then
			local vpOk, vp = pcall(function()
				local clone = model:Clone()
				stripInvisibleParts(clone)
				return Module3D:Attach3D(card.PetIcon, clone)
			end)
			if vpOk and vp then
				--.. now that the box matches the art, a near-exact fit is the right framing
				vp:SetDepthMultiplier(1)
				if vp.CurrentCamera then vp.CurrentCamera.FieldOfView = 5 end
				vp:SetCFrame(CFrame.Angles(0, math.rad(265), 0))
				--.. Attach3D parks the viewport hidden (Module3D line 221) and never
				--.. unhides it, so every pet preview here rendered into an invisible
				--.. frame and the cards showed an empty icon slot.
				vp.Visible = true
				table.insert(previews, vp)
			end
		end
	end
	if #list == 0 then totalLabel.Text = "YOU HAVE NO PETS TO SELL" else totals() end
end

local function setOpen(open)
	frame.Visible = open
	if open then rebuild() else clear(); totals() end
end

openEvent.Event:Connect(setOpen)
closeButton.Activated:Connect(function() setOpen(false) end)
sellButton.Activated:Connect(function()
	if selling then return end
	local ids = {}
	for id in pairs(selected) do table.insert(ids, id) end
	if #ids == 0 then return end
	selling = true
	totals()
	local ok, result = pcall(function() return SellPets:InvokeServer(ids) end)
	selling = false
	if ok and type(result) == "table" and result.Ok then
		totalLabel.Text = string.format("SOLD %d PETS FOR %s COINS!", result.Sold or 0, money(result.Coins or 0))
		task.wait(0.8)
		setOpen(false)
	else
		totalLabel.Text = "SALE FAILED - TRY AGAIN"
		task.wait(0.8)
		rebuild()
	end
end)

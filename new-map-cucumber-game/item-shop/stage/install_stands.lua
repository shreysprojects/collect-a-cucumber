--[[
	item-shop/stage/install_stands.lua -- ONE execute_luau (edit mode) with pets-remake/serve.ps1 -Port 879x
	-Root item-shop/stage running. Turns the lobby's "Sell Shop" cart into the ITEM SHOP (potions / boosts)
	and dresses the headband "Buy Shop" cart with its wares - all PHYSICAL parts, no decals / image guis:
	  Item Shop (was Sell Shop): renamed; cucumbers, slice trays + counter pets parked; SELL -> BUY letters
	    (clones of the Buy Shop's B / U / Y meshes in the cart's green); "SELL HERE !" -> "BUY HERE !";
	    the "CUCUMBERS & PETS" letters + emoji guis -> the ItemSign stroke letters "POTIONS / BOOSTS" + mini
	    icons; the A-frame image icons -> a MiniFlask; the Circle Light's decal cylinder parked; the ItemStand
	    shelf on the counter with the nine RS.Assets.Items models on its pedestals (x1.5)
	  Buy Shop: the Circle Light's decal cylinder parked; the Bolt image icon -> a MiniBolt; the HeadbandRack
	    on the counter with the 12 RS.Assets.Headbands models on its mannequin heads (tiers 1-6 front,
	    7-12 back, left to right for the customer)
	Fixtures come from <Key>.parts.json (Blender primitives -> Parts, itemlib conventions: Roblox local
	frame = fromMatrix(C(t), C(x), C(z), -C(y)), C(v) = (v.x, v.z, -v.y), size (sx, sz, sy)); the model's
	front is its -Z, so PivotTo(CFrame.lookAt(at, at + customerDir)) faces it at the customer.
	Parked originals: ServerStorage.__ShopGoods_2026_09_23 (and backups/NewMap_LobbyShops_before-buy-stands_2026-09-23.rbxm).
	Idempotent: fixtures / clones of the same name are replaced; already-parked pieces are skipped.
	  local f = loadstring(HttpService:GetAsync(BASE .. "install_stands.lua"))()
	  return f(BASE)
]]
return function(BASE)
	local HttpService = game:GetService("HttpService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerStorage = game:GetService("ServerStorage")
	local report = {}
	local function say(fmt, ...) table.insert(report, fmt:format(...)) end
	local function fetch(name)
		local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
		assert(ok, "fetch " .. name .. ": " .. tostring(body))
		return body
	end
	local function C(v) return Vector3.new(v[1], v[3], -v[2]) end
	local SHAPES = {Ball = Enum.PartType.Ball, Block = Enum.PartType.Block, Cylinder = Enum.PartType.Cylinder}

	local lobby = workspace.Map.Lobby
	local shops = lobby.Shops
	local floorPart = lobby.Floor:FindFirstChildWhichIsA("BasePart")
	local floorY = floorPart.Position.Y + floorPart.Size.Y * 0.5

	local parkRoot = ServerStorage:FindFirstChild("__ShopGoods_2026_09_23")
	if not parkRoot then
		parkRoot = Instance.new("Folder")
		parkRoot.Name = "__ShopGoods_2026_09_23"
		parkRoot.Parent = ServerStorage
	end
	local function parkFolder(name)
		local f = parkRoot:FindFirstChild(name)
		if not f then
			f = Instance.new("Folder")
			f.Name = name
			f.Parent = parkRoot
		end
		return f
	end
	local function park(inst, folder)
		inst.Parent = folder
	end

	--..Fixture builder..--
	local function BuildFixture(key)
		local info = HttpService:JSONDecode(fetch(key .. ".parts.json"))
		local model = Instance.new("Model")
		model.Name = key
		for _, p in ipairs(info.parts) do
			local m = p.matrix
			local t = {m[1][4], m[2][4], m[3][4]}
			local x = {m[1][1], m[2][1], m[3][1]}
			local y = {m[1][2], m[2][2], m[3][2]}
			local z = {m[1][3], m[2][3], m[3][3]}
			local part = Instance.new("Part")
			part.Name = p.name
			part.Shape = SHAPES[p.shape] or Enum.PartType.Block
			part.Size = Vector3.new(p.size[1], p.size[3], p.size[2])
			part.CFrame = CFrame.fromMatrix(C(t), C(x), C(z), -C(y))
			part.Color = Color3.fromHex(p.hex)
			part.Material = Enum.Material[p.material] or Enum.Material.SmoothPlastic
			part.Transparency = tonumber(p.transparency) or 0
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = model
		end
		model.WorldPivot = CFrame.new()
		model:SetAttribute("Source", "Blender item-shop/blender/build_stands.py (primitive parts)")
		model:SetAttribute("Tris", info.tris or 0)
		return model, info
	end
	local function Replace(parent, model)
		local old = parent:FindFirstChild(model.Name)
		if old then old:Destroy() end
		model.Parent = parent
	end
	local function Freeze(inst)
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			end
		end
	end

	--..Cart helpers..--
	local function Shell(cart)
		local shell
		for _, d in ipairs(cart:GetDescendants()) do
			if d:IsA("UnionOperation") and d.Size.X > 15 and (not shell or d.Size.Magnitude > shell.Size.Magnitude) then shell = d end
		end
		return shell
	end
	--.. world frame on the counter top at union-local (lx, lz), the front (-Z) toward the customer (+ZVector)
	local function CounterFrame(cart, lx, lz)
		local shell = Shell(cart)
		local cf = shell.CFrame
		local p = cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {shell}
		local hit = workspace:Raycast(Vector3.new(p.X, floorY + 5.5, p.Z), Vector3.new(0, -6, 0), params)
		local topY = hit and hit.Position.Y or (floorY + 3)
		local dir = Vector3.new(cf.ZVector.X, 0, cf.ZVector.Z).Unit
		local at = Vector3.new(p.X, topY, p.Z)
		return CFrame.lookAt(at, at + dir), topY - floorY, dir
	end
	local function StripCircleLight(cart, folder)
		local cl = cart:FindFirstChild("Circle Light")
		if not cl then return end
		for _, d in ipairs(cl:GetChildren()) do
			if d:IsA("MeshPart") and d:FindFirstChildWhichIsA("Decal") then
				park(d, folder)
				say("%s: decal cylinder parked", cart.Name)
			end
		end
	end
	local function ImageParts(cart) -- transparent host Parts carrying a SurfaceGui image / emoji label
		local list = {}
		for _, d in ipairs(cart:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency >= 0.99 then
				local sg = d:FindFirstChildWhichIsA("SurfaceGui")
				if sg and (sg:FindFirstChildWhichIsA("ImageLabel", true) or (sg:FindFirstChildWhichIsA("TextLabel", true) and not d:FindFirstAncestor("ThreeDTextObject"))) then
					local tl = sg:FindFirstChildWhichIsA("TextLabel", true)
					if not tl or #tl.Text <= 4 then table.insert(list, d) end -- the emoji labels, not a sign
				end
			end
		end
		return list
	end
	--.. an upright icon fixture in front of a tilted board part: pos = where the old image part was
	local function PlaceIcon(fixture, at, board, lift, customerDir)
		local n = -board.CFrame.LookVector
		if customerDir and n:Dot(customerDir) < 0 then n = -n end -- the A-frames face the customer side
		local nh = Vector3.new(n.X, 0, n.Z)
		nh = nh.Magnitude > 0.05 and nh.Unit or Vector3.xAxis
		local pos = at + nh * 0.18 + Vector3.new(0, -(lift or 0.4), 0)
		fixture:PivotTo(CFrame.lookAt(pos, pos + nh))
	end
	local function BoardFor(cart, near) -- the A-frame's dark board part closest to `near`
		local best, bestD
		for _, d in ipairs(cart:GetDescendants()) do
			if d:IsA("Part") and d.Transparency < 0.5 and math.abs(d.Size.X - 2.41) < 0.1 and math.abs(d.Size.Y - 3.56) < 0.1 then
				local dist = (d.Position - near).Magnitude
				if not bestD or dist < bestD then best, bestD = d, dist end
			end
		end
		return best
	end

	----------------------------------------------------------------------------------------------- ITEM SHOP
	local itemShop = shops:FindFirstChild("Item Shop") or shops:FindFirstChild("Sell Shop")
	assert(itemShop, "no Sell Shop / Item Shop cart")
	local buyShop = shops:FindFirstChild("Buy Shop")
	assert(buyShop, "no Buy Shop cart")
	local itemPark = parkFolder("ItemShop")
	local buyPark = parkFolder("BuyShop")
	if itemShop.Name ~= "Item Shop" then
		itemShop.Name = "Item Shop"
		say("Sell Shop renamed to Item Shop")
	end

	--.. goods off the counter
	local moved = 0
	for _, ch in ipairs(itemShop:GetChildren()) do
		local isGoods = false
		if ch:IsA("Model") and (ch.Name:find("Cucumber") or ch:FindFirstChild("Moon Bunny") or ch:FindFirstChild("Cosmo Cat")) then isGoods = true end
		if ch:IsA("UnionOperation") and ch.Size.X < 6 then isGoods = true end -- the two slice trays
		if isGoods then
			park(ch, itemPark)
			moved += 1
		end
	end
	if moved > 0 then say("Item Shop: %d goods models / trays parked", moved) end

	--.. the cart's own sub-model (frame, boards, texts)
	local frameModel
	for _, ch in ipairs(itemShop:GetChildren()) do
		if ch:IsA("Model") and ch:FindFirstChild("ThreeDTextObject") then frameModel = ch end
	end
	assert(frameModel, "Item Shop: no frame model with the ThreeDTextObject")
	local buyFrame
	for _, ch in ipairs(buyShop:GetChildren()) do
		if ch:IsA("Model") and ch:FindFirstChild("ThreeDTextObject") then buyFrame = ch end
	end
	assert(buyFrame, "Buy Shop: no frame model with the ThreeDTextObject")

	--.. big letters: SELL -> BUY
	local function BigText(frame)
		local best
		for _, t in ipairs(frame:GetChildren()) do
			if t:IsA("Model") and t.Name == "Text" then
				local _, size = t:GetBoundingBox()
				if size.X > 4 or size.Z > 4 then best = t end
			end
		end
		return best
	end
	local function Board(frame, width)
		for _, p in ipairs(frame:GetChildren()) do
			if p:IsA("Part") and math.abs(p.Size.X - width) < 0.2 then return p end
		end
	end
	local oldBig = BigText(frameModel)
	local buyBig = BigText(buyFrame)
	local itemBoard = Board(frameModel, 11.15)
	local buyBoard = Board(buyFrame, 11.15)
	assert(oldBig and buyBig and itemBoard and buyBoard, "sign boards / letters not found")
	if not oldBig:GetAttribute("ItemShopLetters") then
		park(oldBig, itemPark)
		local text = Instance.new("Model")
		text.Name = "Text"
		text:SetAttribute("ItemShopLetters", true)
		for _, letter in ipairs(buyBig:GetChildren()) do
			if letter:IsA("MeshPart") then
				local clone = letter:Clone()
				clone.CFrame = itemBoard.CFrame * buyBoard.CFrame:ToObjectSpace(letter.CFrame)
				clone.Color = Color3.fromRGB(58, 125, 21)
				clone.Material = Enum.Material.Plastic
				clone.Anchored = true
				clone.CanCollide = false
				clone.Parent = text
			end
		end
		text.Parent = frameModel
		say("Item Shop: SELL letters parked, BUY letters cloned in green (%d)", #text:GetChildren())
	end

	--.. A-frame text
	local tdo = frameModel:FindFirstChild("ThreeDTextObject")
	local label = tdo and tdo:FindFirstChildWhichIsA("TextLabel", true)
	if label and label.Text:find("SELL") then
		label.Text = label.Text:gsub("SELL", "BUY")
		local params = tdo:FindFirstChild("ThreeDTextParams")
		if params then params.Value = params.Value:gsub("SELL", "BUY") end
		say("Item Shop: A-frame text -> %q", label.Text:gsub("\n", "/"))
	end

	--.. small side sign: letters + emoji guis out, ItemSign in
	local smallText
	for _, t in ipairs(frameModel:GetChildren()) do
		if t:IsA("Model") and t.Name == "Text" and not t:GetAttribute("ItemShopLetters") then
			local _, size = t:GetBoundingBox()
			if size.X < 4 and size.Z < 4 then smallText = t end
		end
	end
	if smallText then
		park(smallText, itemPark)
		say("Item Shop: CUCUMBERS/PETS letters parked")
	end
	local sideBoard = Board(frameModel, 3.87)
	assert(sideBoard, "Item Shop: side board not found")
	local imageParts = ImageParts(itemShop)
	local aFrameSpots = {}
	for _, p in ipairs(imageParts) do
		if (p.Position - sideBoard.Position).Magnitude < 4 then
			park(p, itemPark) -- the emoji labels beside the side sign
		else
			table.insert(aFrameSpots, p.Position)
			park(p, itemPark)
		end
	end
	if #imageParts > 0 then say("Item Shop: %d image / emoji gui parts parked", #imageParts) end
	do
		local sign = BuildFixture("ItemSign")
		local n = -sideBoard.CFrame.LookVector -- the letters were on the cart's +X side (the customer side)
		if n:Dot(Vector3.xAxis) < 0 then n = -n end
		local face = sideBoard.Position + n * (sideBoard.Size.Z * 0.5) + Vector3.new(0, 0.15, 0)
		sign:PivotTo(CFrame.lookAt(face, face + n))
		Replace(frameModel, sign)
		say("Item Shop: ItemSign placed on the side board (%d parts)", #sign:GetChildren())
	end
	if #aFrameSpots > 0 then
		local at = Vector3.zero
		for _, p in ipairs(aFrameSpots) do at += p end
		at /= #aFrameSpots
		local board = BoardFor(itemShop, at)
		local flask = BuildFixture("MiniFlask")
		local _, _, customerDir = CounterFrame(itemShop, 0, 0)
		if board then PlaceIcon(flask, at, board, 0.42, customerDir) else flask:PivotTo(CFrame.new(at)) end
		Replace(frameModel, flask)
		say("Item Shop: MiniFlask on the A-frame")
	else
		local old = frameModel:FindFirstChild("MiniFlask")
		if not old then say("Item Shop: no A-frame image parts found (MiniFlask skipped)") end
	end
	StripCircleLight(itemShop, itemPark)

	--.. the shelf + the nine items
	do
		local stand, info = BuildFixture("ItemStand")
		local cf, height, dir = CounterFrame(itemShop, -0.5, -1.3)
		stand:PivotTo(cf)
		Replace(itemShop, stand)
		say("Item Shop: ItemStand on the counter (%.2f above the floor, front %s)", height, tostring(dir))
		local items = ReplicatedStorage.Assets:FindFirstChild("Items")
		local catalog = require(ReplicatedStorage.Modules.ItemShopCatalog:Clone())
		local holder = itemShop:FindFirstChild("ItemDisplay")
		if holder then holder:Destroy() end
		holder = Instance.new("Model")
		holder.Name = "ItemDisplay"
		local slots = info.slots
		table.sort(slots, function(a, b)
			if a.row ~= b.row then return a.row == "back" end
			return a.x > b.x -- viewer's left (+X) first
		end)
		local placed = 0
		for i, def in ipairs(catalog.ITEMS) do
			local slot = slots[i]
			local template = items and items:FindFirstChild(def.Key)
			if slot and template then
				local clone = template:Clone()
				clone.Name = def.Key
				Freeze(clone)
				clone:ScaleTo(1.5)
				clone:PivotTo(cf * CFrame.new(C({slot.x, slot.y, slot.z})))
				clone.Parent = holder
				placed += 1
			end
		end
		holder.Parent = itemShop
		say("Item Shop: %d / %d items on the pedestals", placed, #catalog.ITEMS)
	end

	----------------------------------------------------------------------------------------------- BUY SHOP
	StripCircleLight(buyShop, buyPark)
	do
		local spots = {}
		for _, p in ipairs(ImageParts(buyShop)) do
			table.insert(spots, p.Position)
			park(p, buyPark)
		end
		if #spots > 0 then
			local at = Vector3.zero
			for _, p in ipairs(spots) do at += p end
			at /= #spots
			local board = BoardFor(buyShop, at)
			local bolt = BuildFixture("MiniBolt")
			local _, _, customerDir = CounterFrame(buyShop, 0, 0)
			if board then PlaceIcon(bolt, at, board, 0.4, customerDir) else bolt:PivotTo(CFrame.new(at)) end
			Replace(buyFrame, bolt)
			say("Buy Shop: %d image parts parked, MiniBolt on the A-frame", #spots)
		end
	end
	do
		local rack, info = BuildFixture("HeadbandRack")
		local cf, height, dir = CounterFrame(buyShop, 2.5, -1.25)
		rack:PivotTo(cf)
		Replace(buyShop, rack)
		say("Buy Shop: HeadbandRack on the counter (%.2f above the floor, front %s)", height, tostring(dir))
		local bands = ReplicatedStorage.Assets:FindFirstChild("Headbands")
		local catalog = require(ReplicatedStorage.Modules.HeadbandsCatalog:Clone())
		local holder = buyShop:FindFirstChild("HeadbandDisplay")
		if holder then holder:Destroy() end
		holder = Instance.new("Model")
		holder.Name = "HeadbandDisplay"
		local heads = info.heads
		table.sort(heads, function(a, b)
			if a.row ~= b.row then return a.row == "front" end
			return a.x > b.x -- viewer's left (+X) first
		end)
		local placed = 0
		for i, entry in ipairs(catalog.List()) do
			local head = heads[i]
			local template = bands and bands:FindFirstChild(entry.Name)
			if head and template then
				local clone = template:Clone()
				clone.Name = entry.Name
				Freeze(clone)
				local at = C({head.x, head.y, head.z}) + Vector3.new(0, info.band_above_head or 0.22, 0)
				clone:PivotTo(cf * CFrame.new(at))
				clone.Parent = holder
				placed += 1
			end
		end
		holder.Parent = buyShop
		say("Buy Shop: %d / 12 headbands on the mannequins", placed)
	end

	print("[install_stands] " .. table.concat(report, " | "))
	return table.concat(report, "\n")
end

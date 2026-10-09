--[[
	CucumberMutations  (ModuleScript, ReplicatedStorage.Modules)
	Mutations + materials for field cucumbers, ported from the Zombie Cucumber Game
	(BreakablesService MUTATIONS / DiamondMod / GOLDEN_* + MutationColors), 2026-09-06.

	  * MATERIAL: at most one per cucumber -- Golden (4%, x12) or Diamond (0.6%, x50).
	    Golden is what the old Golden attribute was; the Material attribute now names it.
	  * MUTATIONS: CucumberSpawner picks 0..4 cucumbers PER DAY across all biomes to be
	    mutated (2026-09-06; it used to be a roll on every cucumber). A mutated one carries
	    1..4 distinct mutations (COUNT_CHANCES conditioned on at least one), weighted by
	    the zombie game's rarity mix (NEON / SHADOW common ... VOID / PRISMATIC chase). They
	    stack with each other and with the material; the combined multiplier is capped at
	    STACK_CAP so a stacked jackpot stays sane.
	  * every spawn rolls both (CucumberSpawner); drops / plot placement keep them
	    (CucumberCarry passes them through); CucumberValues multiplies the plot rate.

	Attributes on a cucumber (field holder, carried copy, placed copy):
	  Material  "Golden" | "Diamond" | nil
	  Mutations "NEON,FROZEN" (comma-joined, in roll order) | ""
	  Golden    bool (kept for older readers: Material == "Golden")
	  SizeTier  "HUGE" | "MASSIVE" | "COLOSSAL" | nil  (2026-09-08: a giant cucumber)
	  SizeScale 2 | 3 | 4 | 1                          (SizeTier's Scale, stamped for readers)

	API
	  RollMaterial(rng?) -> name|nil      RollMutations(rng?, count?) -> {names}
	  RollCount(rng?) -> 0..4             RollCountAtLeastOne(rng?) -> 1..4
	  MaterialMultOf(name)  MultOf(mutationName)  TotalMult(material, mutations, size?)
	  ScaleOf(size) -> 1|2|3|4   SizeMultOf(size)   CapOf(size)   DemoteSize(size)
	  RollGiant(rng?) -> bool    RollSize(rng?) -> name    ShouldAnnounce(size) -> bool
	  Parse(str) -> list  Join(list) -> str   DisplayName(typeName, material, mutations, size?)
	  ColorOf(word) -> Color3   TextColor(c)   Hex(c)   ColorizeName(name) -> RichText
	  AnnouncementRichText(typeName, material, mutations, zone, zoneColor, size?) -> RichText
]]
local M = {}

M.MUTATIONS = {
	{Name = "NEON", Color = Color3.fromRGB(57, 255, 20), Mult = 15, Weight = 100},
	{Name = "SHADOW", Color = Color3.fromRGB(45, 42, 66), Mult = 15, Weight = 100},
	{Name = "FROZEN", Color = Color3.fromRGB(170, 230, 255), Mult = 20, Weight = 40},
	{Name = "RADIOACTIVE", Color = Color3.fromRGB(196, 255, 40), Mult = 25, Weight = 25},
	{Name = "MOLTEN", Color = Color3.fromRGB(255, 90, 30), Mult = 25, Weight = 25},
	{Name = "ROYAL", Color = Color3.fromRGB(150, 60, 220), Mult = 40, Weight = 15},
	{Name = "VOID", Color = Color3.fromRGB(90, 30, 140), Mult = 150, Weight = 8},
	{Name = "PRISMATIC", Color = Color3.fromRGB(255, 105, 180), Mult = 750, Weight = 0.5},
}
M.MATERIALS = {
	Golden = {Name = "Golden", Color = Color3.fromRGB(255, 200, 30), Mult = 12, Chance = 0.04, Material = Enum.Material.Foil},
	Diamond = {Name = "Diamond", Color = Color3.fromRGB(200, 245, 255), Mult = 50, Chance = 0.006, Material = Enum.Material.Glass},
}
M.MATERIAL_ORDER = {"Diamond", "Golden"} -- rarest first; one material at most
--.. how many mutations a fresh cucumber gets ("0-4"); indices are the counts
M.COUNT_CHANCES = {[0] = 0.92, [1] = 0.05, [2] = 0.02, [3] = 0.008, [4] = 0.002}
--..Size (2026-09-08, user: "a chance cucumbers spawn in really huge sizes")..--
--.. A THIRD axis beside Material and Mutations: a few of the day's cucumbers grow to 2x / 3x / 4x
--.. their normal size -- in the field, on the shoulder and on the plot they end up on.
--.. Every cucumber rolls GIANT_CHANCE (5 %) at dawn, so a 60-cucumber reset grows ~3 giants
--.. somewhere across the ten biomes. WHICH giant it is comes from the SIZES weights: nearly all
--.. are HUGE, a MASSIVE is a treat and a COLOSSAL is the chase. Cap keeps the user's rule --
--.. "we do not want every day reset to have a quadruple cucumber, or even three of them" -- true
--.. no matter how the dice fall: at most Cap of that tier per reset, and an over-cap roll steps
--.. DOWN a tier instead of being thrown away. Announce = it gets a chat line of its own (a HUGE is
--.. common enough that announcing every one would just be noise).
--.. Dial the whole feature with GIANT_CHANCE (0 = off, 0.05 = ~3 per reset, 0.15 = ~9 per reset).
--..   Scale = how many times its normal size    Mult = how much more it is worth
M.SIZES = { -- smallest first: an over-cap roll demotes to the entry before it
	{Name = "HUGE", Scale = 2, Mult = 3, Weight = 80, Cap = math.huge, Announce = false, Color = Color3.fromRGB(126, 217, 87)},
	{Name = "MASSIVE", Scale = 3, Mult = 6, Weight = 17, Cap = 2, Announce = true, Color = Color3.fromRGB(255, 156, 26)},
	{Name = "COLOSSAL", Scale = 4, Mult = 12, Weight = 3, Cap = 1, Announce = true, Color = Color3.fromRGB(255, 74, 74)},
}
M.GIANT_CHANCE = 0.05 -- per cucumber, per day reset (0 = never a giant)
M.STACK_CAP = 5000 -- combined material x mutations x size multiplier ceiling
M.TAG_COLOR = Color3.fromRGB(255, 255, 255) -- the " + " between mutation words in chat

local byName = {}
for _, m in ipairs(M.MUTATIONS) do byName[m.Name] = m end
local bySize, sizeIndex = {}, {}
for i, s in ipairs(M.SIZES) do bySize[s.Name] = s sizeIndex[s.Name] = i end

function M.Get(name)
	return byName[name]
end

function M.MultOf(name)
	local m = byName[name]
	return m and m.Mult or 1
end

function M.MaterialMultOf(material)
	local mat = material and M.MATERIALS[material]
	return mat and mat.Mult or 1
end

function M.Parse(str)
	local list = {}
	if type(str) == "table" then
		for _, v in ipairs(str) do if byName[v] then list[#list + 1] = v end end
		return list
	end
	for word in tostring(str or ""):gmatch("[^,%s]+") do
		if byName[word] then list[#list + 1] = word end
	end
	return list
end

function M.Join(list)
	return table.concat(M.Parse(list), ",")
end

--..Size accessors (size = a SIZES name: "HUGE" | "MASSIVE" | "COLOSSAL"; nil = normal)..--
function M.GetSize(size)
	return size and bySize[size] or nil
end

--.. how many times its normal size a cucumber of this tier is (1 = normal)
function M.ScaleOf(size)
	local s = size and bySize[size]
	return s and s.Scale or 1
end

function M.SizeMultOf(size)
	local s = size and bySize[size]
	return s and s.Mult or 1
end

--.. how many of this tier one day reset may grow (math.huge = as many as the dice give)
function M.CapOf(size)
	local s = size and bySize[size]
	return s and s.Cap or math.huge
end

--.. the next tier DOWN, or nil below the smallest: an over-cap roll steps down instead of vanishing
function M.DemoteSize(size)
	local i = size and sizeIndex[size]
	local below = i and M.SIZES[i - 1]
	return below and below.Name or nil
end

--.. does this tier deserve its own chat line (MutationChatClient)
function M.ShouldAnnounce(size)
	local s = size and bySize[size]
	return s ~= nil and s.Announce == true
end

--.. material x every mutation, capped at STACK_CAP -- then x size OUTSIDE the cap, so a giant
--.. always pays for being a giant even on a jackpot that is already sitting on the ceiling
function M.TotalMult(material, mutations, size)
	local mult = M.MaterialMultOf(material)
	for _, name in ipairs(M.Parse(mutations)) do
		mult *= M.MultOf(name)
	end
	return math.min(mult, M.STACK_CAP) * M.SizeMultOf(size)
end

--..Rolls (server)..--
function M.RollMaterial(rng)
	rng = rng or math.random
	for _, key in ipairs(M.MATERIAL_ORDER) do
		if rng() < M.MATERIALS[key].Chance then return key end
	end
	return nil
end

function M.RollCount(rng)
	rng = rng or math.random
	local r = rng()
	for count = 4, 1, -1 do
		local p = M.COUNT_CHANCES[count] or 0
		if r < p then return count end
		r -= p
	end
	return 0
end

--.. 1..4: COUNT_CHANCES conditioned on the cucumber being mutated at all
function M.RollCountAtLeastOne(rng)
	rng = rng or math.random
	local total = 0
	for count = 1, 4 do total += M.COUNT_CHANCES[count] or 0 end
	local r = rng() * total
	for count = 4, 1, -1 do
		local p = M.COUNT_CHANCES[count] or 0
		if r < p then return count end
		r -= p
	end
	return 1
end

--.. `count` distinct mutations, each pick weighted among the ones still available
function M.RollMutations(rng, count)
	rng = rng or math.random
	count = count or M.RollCount(rng)
	local pool = table.clone(M.MUTATIONS)
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		local total = 0
		for _, m in ipairs(pool) do total += m.Weight end
		local r = rng() * total
		local index = #pool
		for i, m in ipairs(pool) do
			r -= m.Weight
			if r <= 0 then index = i break end
		end
		picked[#picked + 1] = pool[index].Name
		table.remove(pool, index)
	end
	return picked
end

--..Giant rolls (server; CucumberSpawner.BeginDay rolls them with the day's shared dice)..--
--.. does THIS cucumber grow (one roll per cucumber, per day reset)
function M.RollGiant(rng)
	rng = rng or math.random
	return rng() < M.GIANT_CHANCE
end

--.. how big one giant is: a SIZES name, weighted (HUGE common ... COLOSSAL the chase)
function M.RollSize(rng)
	rng = rng or math.random
	local total = 0
	for _, s in ipairs(M.SIZES) do total += s.Weight end
	local r = rng() * total
	for _, s in ipairs(M.SIZES) do
		r -= s.Weight
		if r <= 0 then return s.Name end
	end
	return M.SIZES[1].Name
end

--..Names / colours..--
function M.DisplayName(typeName, material, mutations, size)
	local parts = {}
	if size and bySize[size] then parts[#parts + 1] = bySize[size].Name end
	if material and M.MATERIALS[material] then parts[#parts + 1] = M.MATERIALS[material].Name end
	for _, name in ipairs(M.Parse(mutations)) do parts[#parts + 1] = name end
	parts[#parts + 1] = typeName
	return table.concat(parts, " ")
end

function M.ColorOf(word)
	local upper = string.upper(tostring(word or ""))
	local m = byName[upper]
	if m then return m.Color end
	local sized = bySize[upper]
	if sized then return sized.Color end
	for key, mat in pairs(M.MATERIALS) do
		if string.upper(key) == upper then return mat.Color end
	end
	return nil
end

--.. dark body colours (SHADOW, VOID) lifted toward white so text stays readable
function M.TextColor(c)
	if math.max(c.R, c.G, c.B) < 0.55 then
		return c:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	return c
end

function M.Hex(c)
	return string.format("#%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.Font(text, color, bold)
	local inner = escape(text)
	if bold then inner = "<b>" .. inner .. "</b>" end
	return string.format('<font color="%s">%s</font>', M.Hex(M.TextColor(color)), inner)
end

--.. "GOLDEN NEON CUCUMBER" -> the material / mutation words in their colours (RichText)
function M.ColorizeName(name)
	local out = {}
	for word in tostring(name or ""):gmatch("%S+") do
		local c = M.ColorOf(word)
		out[#out + 1] = c and M.Font(word, c) or escape(word)
	end
	return table.concat(out, " ")
end

--.. "NEON + FROZEN Golden Vined Cucumber spawned in Desert!" with every word colour-coded
--.. (no brackets around the mutation words since 2026-09-06)
function M.AnnouncementRichText(typeName, material, mutations, zone, zoneColor, size)
	local list = M.Parse(mutations)
	local tags = {}
	for _, name in ipairs(list) do tags[#tags + 1] = M.Font(name, byName[name].Color, true) end
	local head = table.concat(tags, M.Font(" + ", M.TAG_COLOR, true))
	local what = escape(typeName)
	if material and M.MATERIALS[material] then
		what = M.Font(M.MATERIALS[material].Name, M.MATERIALS[material].Color, true) .. " " .. what
	end
	local sized = size and bySize[size]
	--.. the size word leads the noun: "COLOSSAL Golden Vined Cucumber"
	if sized then what = M.Font(sized.Name, sized.Color, true) .. " " .. what end
	local where = M.Font(zone, zoneColor or Color3.fromRGB(200, 200, 200), true)
	--.. a giant with no mutations has no mutation head: do not start the line with a space
	if head == "" then return ("%s spawned in %s!"):format(what, where) end
	return ("%s %s spawned in %s!"):format(head, what, where)
end

--..Look (2026-09-07, shared with the egg shop / placement)..--
--.. The same look CucumberSpawner gives field cucumbers: a Golden (Foil) or Diamond (Glass +
--.. sparkle + light) body, the first mutation tinting a body with no material, one colour-coded
--.. particle emitter per mutation, a point light for the first mutation, PRISMATIC cycling the
--.. rainbow while the model lives. Safe on the client (previews) and re-applicable (no duplicates).
--.. opts.ParticleScale scales the emitters (held eggs use 0.6). Shadow / Hitbox / Handle parts are skipped.
local LOOK_SKIP = {Shadow = true, Hitbox = true, Handle = true}
local function LookParts(model)
	local parts = {}
	if model:IsA("BasePart") then parts[#parts + 1] = model end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not LOOK_SKIP[d.Name] then parts[#parts + 1] = d end
	end
	return parts
end

function M.ApplyLook(model, material, mutations, opts)
	opts = opts or {}
	local list = M.Parse(mutations)
	local parts = LookParts(model)
	local root = model:IsA("BasePart") and model or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root or #parts == 0 then return end
	local particleScale = opts.ParticleScale or 1
	local mat = material and M.MATERIALS[material]
	if mat then
		for _, p in ipairs(parts) do
			p.Color = mat.Color
			p.Material = mat.Material
		end
	end
	local first = list[1] and byName[list[1]]
	if first and not mat then
		for _, p in ipairs(parts) do p.Color = first.Color end
	end
	if material == "Diamond" and not root:FindFirstChild("DiamondSparkle") then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "DiamondSparkle"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
		sparkle.LightEmission = 1
		sparkle.Rate = 6
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45 * particleScale), NumberSequenceKeypoint.new(1, 0)})
		sparkle.Parent = root
		local glow = Instance.new("PointLight")
		glow.Name = "DiamondLight"
		glow.Color = mat.Color
		glow.Range = 12
		glow.Brightness = 0.9
		glow.Parent = root
	end
	for _, name in ipairs(list) do
		local m = byName[name]
		if m and not root:FindFirstChild("Mutation_" .. name) then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Mutation_" .. name
			e.Color = ColorSequence.new(m.Color)
			e.LightEmission = 0.8
			e.Rate = 5
			e.Lifetime = NumberRange.new(0.9, 1.6)
			e.Speed = NumberRange.new(0.6, 1.8)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45 * particleScale), NumberSequenceKeypoint.new(1, 0)})
			e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
			e.Parent = root
		end
	end
	if first and not root:FindFirstChildOfClass("PointLight") then
		local light = Instance.new("PointLight")
		light.Name = "MutationLight"
		light.Color = first.Color
		light.Range = 12
		light.Brightness = 0.9
		light.Parent = root
	end
	if table.find(list, "PRISMATIC") and not model:GetAttribute("PrismaticLoop") then
		model:SetAttribute("PrismaticLoop", true)
		task.spawn(function()
			local t = 0
			while model.Parent do
				t += 0.15
				local c = Color3.fromHSV((t * 0.12) % 1, 0.65, 1)
				for _, p in ipairs(parts) do if p.Parent then p.Color = c end end
				task.wait(0.15)
			end
		end)
	end
end

return M

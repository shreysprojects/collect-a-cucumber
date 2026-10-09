--[[
	CucumberMutations  (ModuleScript, ReplicatedStorage.Modules)
	Mutations + materials for field cucumbers, ported from the Zombie Cucumber Game
	(BreakablesService MUTATIONS / DiamondMod / GOLDEN_* + MutationColors), 2026-09-06.

	  * MATERIAL: at most one per cucumber -- Golden (4%, x12) or Diamond (0.6%, x50).
	    Golden is what the old Golden attribute was; the Material attribute now names it.
	  * MUTATIONS: 0..4 per cucumber (COUNT_CHANCES), distinct, weighted by the zombie
	    game's rarity mix (NEON / SHADOW common ... VOID / PRISMATIC chase). They stack
	    with each other and with the material; the combined multiplier is capped at
	    STACK_CAP so a stacked jackpot stays sane.
	  * every spawn rolls both (CucumberSpawner); drops / plot placement keep them
	    (CucumberCarry passes them through); CucumberValues multiplies the plot rate.

	Attributes on a cucumber (field holder, carried copy, placed copy):
	  Material  "Golden" | "Diamond" | nil
	  Mutations "NEON,FROZEN" (comma-joined, in roll order) | ""
	  Golden    bool (kept for older readers: Material == "Golden")

	API
	  RollMaterial() -> name|nil          RollMutations() -> {names}
	  MaterialMultOf(name)  MultOf(mutationName)  TotalMult(material, mutations)
	  Parse(str) -> list  Join(list) -> str   DisplayName(typeName, material, mutations)
	  ColorOf(word) -> Color3   TextColor(c)   Hex(c)   ColorizeName(name) -> RichText
	  AnnouncementRichText(typeName, material, mutations, zone, zoneColor) -> RichText
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
M.STACK_CAP = 5000 -- combined material x mutations multiplier ceiling
M.TAG_COLOR = Color3.fromRGB(255, 255, 255) -- the "[MUTATION]" prefix / plain words in chat

local byName = {}
for _, m in ipairs(M.MUTATIONS) do byName[m.Name] = m end

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

--.. material x every mutation, capped
function M.TotalMult(material, mutations)
	local mult = M.MaterialMultOf(material)
	for _, name in ipairs(M.Parse(mutations)) do
		mult *= M.MultOf(name)
	end
	return math.min(mult, M.STACK_CAP)
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

--..Names / colours..--
function M.DisplayName(typeName, material, mutations)
	local parts = {}
	if material and M.MATERIALS[material] then parts[#parts + 1] = M.MATERIALS[material].Name end
	for _, name in ipairs(M.Parse(mutations)) do parts[#parts + 1] = name end
	parts[#parts + 1] = typeName
	return table.concat(parts, " ")
end

function M.ColorOf(word)
	local upper = string.upper(tostring(word or ""))
	local m = byName[upper]
	if m then return m.Color end
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

--.. "[NEON + FROZEN] Golden Vined Cucumber spawned in Desert!" with every word colour-coded
function M.AnnouncementRichText(typeName, material, mutations, zone, zoneColor)
	local list = M.Parse(mutations)
	local tags = {}
	for _, name in ipairs(list) do tags[#tags + 1] = M.Font(name, byName[name].Color, true) end
	local head = M.Font("[", M.TAG_COLOR, true) .. table.concat(tags, M.Font(" + ", M.TAG_COLOR, true)) .. M.Font("]", M.TAG_COLOR, true)
	local what = escape(typeName)
	if material and M.MATERIALS[material] then
		what = M.Font(M.MATERIALS[material].Name, M.MATERIALS[material].Color, true) .. " " .. what
	end
	local where = M.Font(zone, zoneColor or Color3.fromRGB(200, 200, 200), true)
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

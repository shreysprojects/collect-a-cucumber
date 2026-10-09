const fs = require('fs');
let src = fs.readFileSync('pets-system/src/StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua', 'utf8').replace(/\r\n/g, '\n');
let n = 0;
function rep(a, b) { if (!src.includes(a)) { throw new Error('anchor missing: ' + a.slice(0, 60)); } src = src.replace(a, b); n++; }
rep(`local WHITE = Color3.fromRGB(255, 255, 255)\n`,
`local WHITE = Color3.fromRGB(255, 255, 255)
--.. 2026-09-23 (user: "the bullets from pets that hit cucumbers" in the Zombie Cucumber Game should hit the
--.. zombies here): the pet BOLT look ported from that game's BreakablesClient.petBolts - a 0.4-stud neon ball
--.. that ACCELERATES into its target (Quad In) while shrinking to 0.2, trailing a soft ribbon (Trail, 0.18 s,
--.. light emission). Colours blend the zombie game's pale-green ball / green ribbon with the pet's rarity glow.
local BOLT_BALL = Color3.fromRGB(225, 255, 200)
local BOLT_TRAIL = Color3.fromRGB(120, 220, 90)
local BOLT_BLEND = 0.5 -- 0 = the zombie game's colours, 1 = pure rarity glow
local BOLT_END_SIZE = 0.2 -- studs at impact
local TRAIL_LIFETIME = 0.18
`);
rep(`local function ReleasePart(part)
	Budget:Give()
	part.Transparency = 1
	part.CFrame = PARK`,
`--.. the ribbon behind a bolt: built once per pooled part, switched on only while a shot flies
local function TrailOf(part)
	local trail = part:FindFirstChild("BoltTrail")
	if not trail then
		local a0 = Instance.new("Attachment")
		a0.Name = "BoltA0"
		a0.Position = Vector3.new(0, 0.15, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "BoltA1"
		a1.Position = Vector3.new(0, -0.15, 0)
		a1.Parent = part
		trail = Instance.new("Trail")
		trail.Name = "BoltTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
		trail.Lifetime = TRAIL_LIFETIME
		trail.LightEmission = 0.6
		trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2)})
		trail.Enabled = false
		trail.Parent = part
	end
	return trail
end

local function ReleasePart(part)
	Budget:Give()
	local trail = part:FindFirstChild("BoltTrail")
	if trail then trail.Enabled = false end
	part.Transparency = 1
	part.CFrame = PARK`);
rep(`	local glow = PetsCatalog.RARITY_GLOW
	local color = type(glow) == "table" and typeof(glow[ev.Rarity]) == "Color3" and glow[ev.Rarity] or WHITE
	local part = AcquirePart(Enum.PartType.Ball, Vector3.one * SHOT_SIZE, color)
	if not part then return end
	local travel = Core.TravelTime((to - from).Magnitude, TRAVEL_MIN, TRAVEL_MAX, SHOT_SPEED)
	local t0 = os.clock()
	part.CFrame = CFrame.new(from)
	table.insert(animations, function(now)
		local t = now - t0
		if t < travel then
			part.CFrame = CFrame.new(from:Lerp(to, t / travel))
			part.Size = Vector3.one * (t < MUZZLE_FLASH_TIME and SHOT_SIZE * MUZZLE_FLASH_SCALE or SHOT_SIZE)
			return true
		end
		local k = (t - travel) / SPARK_TIME`,
`	local glow = PetsCatalog.RARITY_GLOW
	local rarity = type(glow) == "table" and typeof(glow[ev.Rarity]) == "Color3" and glow[ev.Rarity] or WHITE
	local color = BOLT_BALL:Lerp(rarity, BOLT_BLEND)
	local part = AcquirePart(Enum.PartType.Ball, Vector3.one * SHOT_SIZE, color)
	if not part then return end
	local travel = Core.TravelTime((to - from).Magnitude, TRAVEL_MIN, TRAVEL_MAX, SHOT_SPEED)
	local t0 = os.clock()
	part.CFrame = CFrame.new(from)
	local trail = TrailOf(part)
	trail.Color = ColorSequence.new(BOLT_TRAIL:Lerp(rarity, BOLT_BLEND))
	trail.Enabled = true
	table.insert(animations, function(now)
		local t = now - t0
		if t < travel then
			local k = t / travel
			k = k * k -- Quad In: the bolt accelerates into the zombie (the zombie game's pet bolt flight)
			part.CFrame = CFrame.new(from:Lerp(to, k))
			part.Size = Vector3.one * (t < MUZZLE_FLASH_TIME and SHOT_SIZE * MUZZLE_FLASH_SCALE or (SHOT_SIZE + (BOLT_END_SIZE - SHOT_SIZE) * k))
			return true
		end
		trail.Enabled = false
		local k = (t - travel) / SPARK_TIME`);
rep(`	  * Shot -- a pooled neon orb in the pet's rarity glow colour (PetsCatalog.RARITY_GLOW) flies from`,
`	  * Shot -- a pooled neon BOLT (2026-09-23: the Zombie Cucumber Game's pet-bolt look - a ribbon Trail
	    behind a ball that accelerates into the target and shrinks, coloured by the rarity glow) flies from`);
fs.writeFileSync('stage-2026-09-23b/StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua', src.replace(/\n/g, '\r\n'));
fs.writeFileSync('spinner/src/StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua', src.replace(/\n/g, '\r\n'));
console.log('replacements', n, 'new length', src.length);

--[[
	BuildHealthService  (Script, ServerScriptService)  2026-09-12
	Durability for every placed build (tag "PlacedBuild": walls, defences, decoration - floors and
	stairs are never damaged). User: "zombies deal damage to builds like walls, defenses, decoration
	etc. each defense has a healthbar when damaged but they always heal throughout the daytime and
	never take longer than the daytime to heal back fully. by next night all defenses are at 100%
	again. and make it so defenses are never fully destroyed / irreparable".

	  Health   attributes Health / MaxHealth (ZombieCatalog.BuildHealth(BuildKey)) on the model.
	           ServerStorage.BuildAPI (BindableFunctions): Damage(model, amount, source) -> health,
	           broken | IsBroken(model) -> bool | Heal(model or nil = everything) -> true.
	           ZombieRaidService.Bash is the only damage source: a zombie stuck against a build that
	           is in its path (they never go out of their way for one).
	  Bar      a stud-sized BillboardGui ("BuildHealthTag") over the Hitbox with the build's name and
	           a health bar, shown only while Health < MaxHealth.
	  Broken   at 0 the build is NEVER destroyed: attribute Broken = true, every part but the Hitbox
	           fades to BROKEN_TRANSPARENCY and stops colliding (zombies and players walk through;
	           the originals are remembered per part), the defences stop working (DefenceService
	           skips Broken models), dust + "Rock Crumble". Damage to a broken build is refused.
	  Healing  every HEAL_TICK while workspace.CyclePhase == "Day" every damaged build gains
	           MaxHealth * dt / HealSeconds, HealSeconds = HEAL_FRACTION x DayDurationSeconds (the
	           DayNightCycle attribute; 0.8 x 180 = 144 s, so even a build broken in the last swing of
	           the night is full well inside the next day). A broken build stands again (originals
	           restored, sparkle + "Magic Shimmer") once it is back to REPAIR_FRACTION of its health.
	           When night falls everything is set to 100 % and mended regardless - the guarantee "by
	           next night all defenses are at 100 %" - and nothing heals during the night itself.
	Studio hook: workspace:SetAttribute("BuildHealthDev", "damage:<amount>" | "break" | "heal") -
	  applied to every placed build; edge-triggered, cleared after it runs.
]]

--..Services..--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

--..Modules..--
local ZombieCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieCatalog"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))

--..Config..--
local BUILD_TAG = "PlacedBuild"
local API_NAME = "BuildAPI"
local HEAL_TICK = 1            -- seconds between heal steps
local HEAL_FRACTION = 0.8      -- of the day length: 0 -> full in 80 % of a day
local DAY_DEFAULT = 180        -- seconds, if DayNightCycle carries no DayDurationSeconds
local REPAIR_FRACTION = 0.35   -- a broken build stands again at this much of its health
local BROKEN_TRANSPARENCY = 0.65
local BAR_WIDTH = 5            -- studs (BillboardGui scale units are studs)
local BAR_HEIGHT = 1.5
local BAR_ABOVE = 0.6          -- studs above the hitbox top
local BAR_DISTANCE = 120
local COLOR_FULL = Color3.fromRGB(92, 225, 92)
local COLOR_MID = Color3.fromRGB(255, 190, 60)
local COLOR_LOW = Color3.fromRGB(240, 58, 58)

--..State..--
local Builds = {} -- [model] = {Model, Hitbox, Max, Broken, Originals, Gui, Fill, Label}
local cycleScript = ServerScriptService:FindFirstChild("DayNightCycle")

--..API..--
local API = ServerStorage:FindFirstChild(API_NAME)
if API then API:Destroy() end
API = Instance.new("Folder")
API.Name = API_NAME
local function Bindable(name)
	local b = Instance.new("BindableFunction")
	b.Name = name
	b.Parent = API
	return b
end
local DamageAPI, IsBrokenAPI, HealAPI = Bindable("Damage"), Bindable("IsBroken"), Bindable("Heal")

--..Helpers..--
local function HealSeconds()
	local day = cycleScript and tonumber(cycleScript:GetAttribute("DayDurationSeconds"))
		or tonumber(workspace:GetAttribute("DayDurationSeconds")) or DAY_DEFAULT
	return math.max(10, HEAL_FRACTION * day)
end

local function NameOf(model)
	return tostring(model:GetAttribute("DisplayName") or model:GetAttribute("BuildKey") or model.Name)
end

local function Dust(position, color, count)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count or 20)
	Debris:AddItem(att, 2.5)
end

local function Sparkle(position)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(170, 255, 190), Color3.fromRGB(255, 250, 200))
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0)})
	pe.Transparency = NumberSequence.new(0)
	pe.LightEmission = 1
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Speed = NumberRange.new(5, 10)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(26)
	Debris:AddItem(att, 2.5)
end

--..Health bar (sized in studs, like every overhead UI in this place)..--
local function MakeBar(rec)
	local hitbox = rec.Hitbox
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuildHealthTag"
	gui.Adornee = hitbox
	gui.Size = UDim2.fromScale(BAR_WIDTH, BAR_HEIGHT)
	gui.StudsOffsetWorldSpace = Vector3.new(0, hitbox.Size.Y * 0.5 + BAR_ABOVE + BAR_HEIGHT * 0.5, 0)
	gui.MaxDistance = BAR_DISTANCE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 0.55)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = NameOf(rec.Model)
	label.TextColor3 = Color3.fromRGB(245, 245, 250)
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = label
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(0.8, 0.24)
	bar.Position = UDim2.fromScale(0.1, 0.66)
	bar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_FULL
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	gui.Parent = hitbox
	rec.Gui, rec.Fill, rec.Label = gui, fill, label
end

local function Refresh(rec)
	local model = rec.Model
	local health = tonumber(model:GetAttribute("Health")) or rec.Max
	local f = math.clamp(health / math.max(1, rec.Max), 0, 1)
	if rec.Fill and rec.Fill.Parent then
		rec.Fill.Size = UDim2.fromScale(f, 1)
		rec.Fill.BackgroundColor3 = f > 0.5 and COLOR_FULL or (f > 0.25 and COLOR_MID or COLOR_LOW)
	end
	if rec.Label and rec.Label.Parent then
		rec.Label.Text = rec.Broken and (NameOf(model) .. " (broken)") or NameOf(model)
	end
	if rec.Gui then rec.Gui.Enabled = health < rec.Max end
end

local function SetHealth(rec, health)
	health = math.clamp(health, 0, rec.Max)
	rec.Model:SetAttribute("Health", health)
	Refresh(rec)
	return health
end

--..Broken / mended..--
local function Break(rec, at)
	if rec.Broken then return end
	rec.Broken = true
	rec.Originals = {}
	for _, d in ipairs(rec.Model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= rec.Hitbox then
			rec.Originals[d] = {Transparency = d.Transparency, CanCollide = d.CanCollide}
			if d.Transparency < 1 then d.Transparency = math.max(d.Transparency, BROKEN_TRANSPARENCY) end
			d.CanCollide = false
		end
	end
	rec.Model:SetAttribute("Broken", true)
	local position = at or rec.Hitbox.Position
	Dust(position, Color3.fromRGB(150, 140, 120), 24)
	SoundController.PlayFXAt("Rock Crumble", position, {Volume = 1, RollOff = 70})
	Refresh(rec)
end

local function Mend(rec)
	if not rec.Broken then return end
	rec.Broken = false
	for part, o in pairs(rec.Originals or {}) do
		if part.Parent then
			part.Transparency = o.Transparency
			part.CanCollide = o.CanCollide
		end
	end
	rec.Originals = nil
	rec.Model:SetAttribute("Broken", nil)
	Sparkle(rec.Hitbox.Position)
	SoundController.PlayFXAt("Magic Shimmer", rec.Hitbox.Position, {Volume = 0.6, RollOff = 60})
	Refresh(rec)
end

--..Registration..--
local function Register(model)
	if Builds[model] then return end
	if not CollectionService:HasTag(model, BUILD_TAG) then return end
	if model:GetAttribute("IsFloor") == true or model:GetAttribute("IsStairs") == true then return end
	local hitbox = model.PrimaryPart or model:FindFirstChild("Hitbox")
	if not hitbox then return end
	local key = model:GetAttribute("BuildKey") or model:GetAttribute("Key")
	local max = tonumber(model:GetAttribute("MaxHealth")) or ZombieCatalog.BuildHealth(key)
	local rec = {Model = model, Hitbox = hitbox, Max = max, Broken = false}
	model:SetAttribute("MaxHealth", max)
	local health = tonumber(model:GetAttribute("Health"))
	if health == nil then health = max end
	Builds[model] = rec
	MakeBar(rec)
	SetHealth(rec, health)
	if health <= 0 or model:GetAttribute("Broken") == true then Break(rec) end
end

local function Forget(model)
	local rec = Builds[model]
	if not rec then return end
	Builds[model] = nil
	if rec.Gui and rec.Gui.Parent and model.Parent then rec.Gui:Destroy() end
end

--..API..--
local function Damage(model, amount, source)
	local rec = Builds[model]
	amount = tonumber(amount) or 0
	if not rec or not model.Parent then return nil, false end
	if rec.Broken or amount <= 0 then return tonumber(model:GetAttribute("Health")) or 0, rec.Broken end
	local health = SetHealth(rec, (tonumber(model:GetAttribute("Health")) or rec.Max) - amount)
	if health <= 0 then
		Break(rec)
		print(("[BuildHealth] %s broke (%s)"):format(NameOf(model), tostring(source)))
	end
	return health, rec.Broken
end

local function HealAll(model)
	local function full(rec)
		SetHealth(rec, rec.Max)
		if rec.Broken then Mend(rec) end
	end
	if model then
		local rec = Builds[model]
		if rec then full(rec) end
	else
		for _, rec in pairs(Builds) do full(rec) end
	end
	return true
end

DamageAPI.OnInvoke = Damage
IsBrokenAPI.OnInvoke = function(model)
	local rec = Builds[model]
	return rec ~= nil and rec.Broken
end
HealAPI.OnInvoke = HealAll
API.Parent = ServerStorage

--..Daytime healing..--
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(HEAL_TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		if workspace:GetAttribute("CyclePhase") ~= "Day" then continue end
		local seconds = HealSeconds()
		for model, rec in pairs(Builds) do
			if not model.Parent then
				Forget(model)
			else
				local health = tonumber(model:GetAttribute("Health")) or rec.Max
				if health < rec.Max then
					health = SetHealth(rec, health + rec.Max * dt / seconds)
					if rec.Broken and health >= REPAIR_FRACTION * rec.Max then Mend(rec) end
				end
			end
		end
	end
end)

--..Night: everything at 100 %, the guarantee..--
workspace:GetAttributeChangedSignal("CyclePhase"):Connect(function()
	if workspace:GetAttribute("CyclePhase") == "Night" then
		local mended = 0
		for _, rec in pairs(Builds) do
			if rec.Broken or (tonumber(rec.Model:GetAttribute("Health")) or rec.Max) < rec.Max then mended += 1 end
		end
		HealAll()
		if mended > 0 then print(("[BuildHealth] night: %d build(s) restored to full health"):format(mended)) end
	end
end)

--..Setup..--
for _, model in ipairs(CollectionService:GetTagged(BUILD_TAG)) do Register(model) end
CollectionService:GetInstanceAddedSignal(BUILD_TAG):Connect(function(model) task.defer(Register, model) end)
CollectionService:GetInstanceRemovedSignal(BUILD_TAG):Connect(Forget)

--..Studio hook..--
workspace:GetAttributeChangedSignal("BuildHealthDev"):Connect(function()
	local cmd = workspace:GetAttribute("BuildHealthDev")
	if type(cmd) ~= "string" or cmd == "" then return end
	workspace:SetAttribute("BuildHealthDev", nil)
	local kind, arg = cmd:match("^(%w+):?(.*)$")
	if kind == "damage" then
		for model in pairs(Builds) do Damage(model, tonumber(arg) or 25, "Dev") end
	elseif kind == "break" then
		for model, rec in pairs(Builds) do
			SetHealth(rec, 0)
			Break(rec)
		end
	elseif kind == "heal" then
		HealAll()
	end
end)

print(("[BuildHealth] %d build(s) tracked; heal 0 -> full in %.0f s of daytime, mend at %d %%, never destroyed"):format(
	(function() local n = 0 for _ in pairs(Builds) do n += 1 end return n end)(), HealSeconds(), REPAIR_FRACTION * 100))

--[[---------------------------------------DESCRIPTION------------------------------------------
	The snowball you SEE coming out of the launcher (client only, never replicated).

	ChargeController owns one per posed character (the local player and every observed one):
	  * while the clip says so (Ball.Show "Charge" / "Always" / "Fire" after the clip's
	    BallAppearAt), a copy of that player's equipped snowball sits in the launcher's Seat
	    (shovel blade, scoop, pouch, crossbow rail ...), growing from Ball.Grow to full size as it
	    packs; slingshots get two elastic Beams from the fork tips to the ball;
	  * at the clip's fire moment Launch() lets go of it: it flies from the Seat (or out of the
	    Muzzle for barrels, with a burst at the muzzle) along the muzzle direction;
	  * when that player's real ride ball (workspace.ActiveSnowballs.<Name>_Snowball, spawned by
	    the server at the same point) shows up, the flying copy eases onto it and hands over:
	    the real ball is kept hidden (LocalTransparencyModifier) for that blend, then shown.
	So the ball visibly leaves the launcher at the right frame on every screen, and the network
	delay before the real ball arrives is covered by the copy.

	Slingshots hold the ball in the LEFT hand instead (Ball.Hand = "Left", Ball.Offset in the
	hand part's frame). Fx.Style picks the shot burst (snow / smoke / spark / fire / steam /
	toxic, Fx.Color tints it); Fx.Charge adds a small looping effect at the muzzle while the
	player holds (its rate follows the charge). Meta.Muzzle2 gets a second burst (twin barrels),
	Meta.Back a backblast (rocket).

	Snowball looks come from ReplicatedStorage.Assets.SnowballVisuals (copied from
	ServerStorage.Assets.Storage.Snowballs by SERV_Launcher at boot); a white sphere otherwise.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local snowballCatalog = require(ReplicatedStorage.Assets.Modules.Shared.Snowballs)

local LauncherBall = {}
LauncherBall.__index = LauncherBall

local BALL_SUFFIX = "_Snowball"
local HANDOFF_TIME = 0.12 -- shortest time the flying copy takes to ease onto the real ball
local HANDOFF_MAX = 0.5 -- longest (a big lead from a slow connection melts away over this)
local GHOST_LIFETIME = 1.2 -- give up waiting for the real ball (launch refused) after this
local GHOST_MAX_SPEED = 70 -- studs/s; only has to cover the network delay
local GRAVITY_SCALE = 0.35 -- the copy arcs a little, the real ball is lifted while flying anyway
local GROW_TIME = 0.5

local FX_STYLES = {
	snow = { Color = Color3.fromRGB(245, 250, 255), Count = 14, Speed = 14, Size = 0.55, Life = 0.45, Texture = "rbxasset://textures/particles/smoke_main.dds" },
	smoke = { Color = Color3.fromRGB(235, 238, 245), Count = 12, Speed = 10, Size = 0.9, Life = 0.55, Texture = "rbxasset://textures/particles/smoke_main.dds", Flash = true },
	spark = { Color = Color3.fromRGB(140, 220, 255), Count = 20, Speed = 18, Size = 0.35, Life = 0.35, Texture = "rbxasset://textures/particles/sparkles_main.dds", Flash = true },
	fire = { Color = Color3.fromRGB(255, 150, 60), Count = 16, Speed = 12, Size = 0.8, Life = 0.4, Texture = "rbxasset://textures/particles/fire_main.dds", Flash = true },
	steam = { Color = Color3.fromRGB(215, 240, 255), Count = 16, Speed = 8, Size = 1.1, Life = 0.7, Texture = "rbxasset://textures/particles/smoke_main.dds" },
	toxic = { Color = Color3.fromRGB(120, 235, 70), Count = 16, Speed = 10, Size = 0.8, Life = 0.55, Texture = "rbxasset://textures/particles/smoke_main.dds", Flash = true },
}

local localFolder

local function getLocalFolder()
	if localFolder and localFolder.Parent then
		return localFolder
	end
	localFolder = Instance.new("Folder")
	localFolder.Name = "LauncherBallsLocal"
	localFolder.Parent = workspace
	return localFolder
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function setParts(model, fn)
	if model:IsA("BasePart") then
		fn(model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

function LauncherBall.new(character, data)
	local self = setmetatable({}, LauncherBall)
	self.Character = character
	self.Player = Players:GetPlayerFromCharacter(character)
	self.Data = data
	self.Ball = data.Ball or {}
	self.Kind = data.Meta and data.Meta.Kind or "barrel"
	self.Grow = 1
	self.Visible = false
	return self
end

function LauncherBall:_snowballName()
	local name = self.Player and self.Player:GetAttribute("EquippedSnowball")
	return if type(name) == "string" then name else "Classic"
end

function LauncherBall:_model()
	local name = self:_snowballName()
	if self.Model and self.ModelName == name then
		return self.Model
	end
	if self.Model then
		self.Model:Destroy()
	end
	local info = snowballCatalog:GetByName(name)
	local asset = info and info.Asset or name
	local visuals = ReplicatedStorage.Assets:FindFirstChild("SnowballVisuals")
	local template = visuals and visuals:FindFirstChild(asset)
	local model
	if template then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2, 2, 2)
		part.Material = Enum.Material.Snow
		part.Color = Color3.fromRGB(245, 248, 255)
		part.Parent = model
		model.PrimaryPart = part
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	setParts(model, function(part)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end)
	model.Name = "LauncherBall"
	local scale = (mountainConfig.LAUNCH.BallScale or 1) * (self.Ball.Scale or 1)
	if model:IsA("Model") and scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	self.BaseScale = model:GetScale()
	self.CurrentScale = self.BaseScale
	self.Model = model
	self.ModelName = name
	return model
end

function LauncherBall:_setScale(k)
	local model = self.Model
	local want = self.BaseScale * k
	if model and math.abs(want - (self.CurrentScale or 0)) > 0.005 then
		model:ScaleTo(want)
		self.CurrentScale = want
	end
end

function LauncherBall:_launcherFrames()
	local launcher = self.Character:FindFirstChild(mountainConfig.LAUNCHER.InstanceName)
	if not (launcher and launcher:IsA("Model") and launcher.PrimaryPart) then
		return nil
	end
	return launcher, launcher:GetPivot(), launcher:GetScale()
end

-- Where the ball sits before the shot: in the left hand (slingshots) or on the launcher.
function LauncherBall:SeatCFrame()
	if self.Ball.Hand == "Left" then
		local hand = self.Character:FindFirstChild("LeftHand")
		if not hand then
			return nil
		end
		local offset = self.Ball.Offset or Vector3.new(0, -0.45, 0)
		return hand.CFrame * CFrame.new(offset)
	end
	return self:PointCFrame(if self.Data.Meta.Seat then "Seat" else "Muzzle")
end

-- World CFrame of a Meta point on the held launcher (nil when there is no launcher).
function LauncherBall:PointCFrame(name)
	local entry = self.Data.Meta and self.Data.Meta[name]
	if not entry then
		return nil
	end
	local launcher, pivot, scale = self:_launcherFrames()
	if not launcher then
		return nil
	end
	local pos = entry.Pos * scale
	local look = entry.Look or Vector3.new(0, -1, 0)
	local up = entry.Up or Vector3.new(0, 0, -1)
	return pivot * CFrame.lookAt(pos, pos + look, up)
end

function LauncherBall:_bands(visible, ballPosition)
	local bands = self.Data.Meta and self.Data.Meta.Bands
	if not bands then
		return
	end
	local launcher, pivot, scale = self:_launcherFrames()
	if not visible or not launcher then
		if self.BandBeams then
			for _, beam in self.BandBeams do
				beam.Enabled = false
			end
		end
		return
	end
	if not self.BandBeams or not self.BandPart or not self.BandPart.Parent then
		self:_clearBands()
		local part = Instance.new("Part")
		part.Name = "LauncherBands"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Parent = getLocalFolder()
		self.BandPart = part
		self.BandAttachments = {}
		self.BandBeams = {}
		local tail = Instance.new("Attachment")
		tail.Parent = part
		self.BandTail = tail
		for i in bands do
			local a = Instance.new("Attachment")
			a.Parent = part
			self.BandAttachments[i] = a
			local beam = Instance.new("Beam")
			beam.Attachment0 = a
			beam.Attachment1 = tail
			beam.Width0 = 0.14
			beam.Width1 = 0.2
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Color = ColorSequence.new(Color3.fromRGB(120, 72, 40))
			beam.LightInfluence = 1
			beam.Parent = part
			self.BandBeams[i] = beam
		end
	end
	self.BandPart.CFrame = CFrame.new()
	for i, p in bands do
		self.BandAttachments[i].WorldPosition = pivot * (p * scale)
		self.BandBeams[i].Enabled = true
	end
	self.BandTail.WorldPosition = ballPosition
end

function LauncherBall:_clearBands()
	if self.BandPart then
		self.BandPart:Destroy()
	end
	self.BandPart, self.BandBeams, self.BandAttachments, self.BandTail = nil, nil, nil, nil
end

-- Called every frame before the shot. visible: the clip wants the ball in the seat now.
-- holding: seconds since the player started holding (drives the grow), nil when not holding.
function LauncherBall:Seat(visible, holdingFor)
	if self.Flying then
		return
	end
	local cf = visible and self:SeatCFrame()
	if not cf then
		if self.Model then
			self.Model.Parent = nil
		end
		self.Visible = false
		self:_bands(false)
		return
	end
	local model = self:_model()
	local grow = 1
	if holdingFor ~= nil and (self.Ball.Grow or 1) < 1 then
		grow = (self.Ball.Grow or 1) + (1 - (self.Ball.Grow or 1)) * smooth(holdingFor / GROW_TIME)
	end
	self:_setScale(grow)
	model:PivotTo(cf)
	model.Parent = getLocalFolder()
	self.Visible = true
	self:_bands(true, cf.Position)
end

local function emitBurst(position, direction, style, color)
	local spec = FX_STYLES[style] or FX_STYLES.snow
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.lookAt(position, position + direction)
	part.Parent = getLocalFolder()
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.Texture
	emitter.Color = ColorSequence.new(color or spec.Color)
	emitter.LightEmission = if style == "spark" or style == "fire" then 0.7 else 0.1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.Size), NumberSequenceKeypoint.new(1, spec.Size * 2.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(spec.Life * 0.6, spec.Life)
	emitter.Speed = NumberRange.new(spec.Speed * 0.4, spec.Speed)
	emitter.SpreadAngle = Vector2.new(28, 28)
	emitter.Drag = 4
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(spec.Count)
	if spec.Flash then
		local light = Instance.new("PointLight")
		light.Color = color or spec.Color
		light.Brightness = 3
		light.Range = 9
		light.Parent = attachment
		task.delay(0.08, function()
			light:Destroy()
		end)
	end
	task.delay(spec.Life + 0.2, function()
		part:Destroy()
	end)
end

function LauncherBall:_realBall()
	local folder = workspace:FindFirstChild("ActiveSnowballs")
	local name = (self.Player and self.Player.Name or self.Character.Name) .. BALL_SUFFIX
	return folder and folder:FindFirstChild(name)
end

local function hideReal(ball, hidden)
	setParts(ball, function(part)
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end)
end

-- Release: a ride ball that exists now is the PREVIOUS ride, never the one this shot spawns.
-- expected = a ball already known to belong to this shot (observers that only learnt about the
-- shot from the ball itself), never treated as old.
function LauncherBall:Arm(expected)
	local current = self:_realBall()
	self.PreviousReal = if current ~= nil and current ~= expected then current else nil
	self.EarlyReal = nil
end

-- Between the release and the fire moment: on other players' screens the real ball can arrive
-- before their copy of the clip reaches its fire frame. Keep it hidden until the copy takes over.
function LauncherBall:WatchEarly()
	if self.Flying then
		return
	end
	local found = self:_realBall()
	if found and found ~= self.PreviousReal and found ~= self.EarlyReal and found.Parent then
		self.EarlyReal = found
		hideReal(found, true)
	end
end

-- The shot: the copy leaves the launcher. Returns the world start point (for the server) and
-- the direction. speed = predicted launch speed (studs/s), only used for the short flight.
function LauncherBall:Launch(speed)
	local fromSeat = self.Ball.Start == "Seat" and (self.Data.Meta.Seat ~= nil or self.Ball.Hand ~= nil)
	local startCF = if fromSeat then self:SeatCFrame() else self:PointCFrame("Muzzle")
	local muzzle = self:PointCFrame("Muzzle")
	if not startCF or not muzzle then
		return nil
	end
	local direction = muzzle.LookVector
	local model = self:_model()
	if not self.Visible then
		-- barrels: the ball is born in the muzzle
		self:_setScale(0.6)
	end
	model:PivotTo(CFrame.new(startCF.Position))
	model.Parent = getLocalFolder()
	self:_bands(false)
	local fx = self.Data.Fx or {}
	local style = fx.Style or (if self.Kind == "barrel" then "smoke" else "snow")
	emitBurst(muzzle.Position, direction, style, fx.Color)
	if self.Data.Meta.Muzzle2 then
		local second = self:PointCFrame("Muzzle2")
		if second then
			emitBurst(second.Position, second.LookVector, style, fx.Color)
		end
	end
	if self.Data.Meta.Back then
		local back = self:PointCFrame("Back")
		if back then
			emitBurst(back.Position, back.LookVector, "smoke", Color3.fromRGB(230, 230, 235))
		end
	end
	self.Flying = {
		Start = startCF.Position,
		Position = startCF.Position,
		Velocity = direction * math.clamp(speed or 40, 20, GHOST_MAX_SPEED),
		Age = 0,
		Old = self.PreviousReal,
	}
	self.PreviousReal = nil
	if self.EarlyReal and self.EarlyReal.Parent then
		self:_beginHandoff(self.EarlyReal)
	end
	self.EarlyReal = nil
	self.Visible = true
	return startCF.Position, direction
end

-- Looping effect at the muzzle while the player holds (Fx.Charge), rate by the charge 0..1.
function LauncherBall:ChargeFx(active, level)
	local fx = self.Data.Fx
	local style = fx and fx.Charge
	if not style then
		return
	end
	local muzzle = active and self:PointCFrame("Muzzle")
	if not muzzle then
		if self.ChargeEmitter then
			self.ChargeEmitter.Enabled = false
		end
		return
	end
	if not self.ChargePart or not self.ChargePart.Parent then
		local spec = FX_STYLES[style] or FX_STYLES.snow
		local part = Instance.new("Part")
		part.Name = "LauncherChargeFx"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = getLocalFolder()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = spec.Texture
		emitter.Color = ColorSequence.new(fx.ChargeColor or fx.Color or spec.Color)
		emitter.LightEmission = if style == "spark" or style == "fire" then 0.8 else 0.1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.Size * 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.2, 0.4)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LockedToPart = true
		emitter.Rate = 0
		emitter.Parent = part
		self.ChargePart, self.ChargeEmitter = part, emitter
	end
	self.ChargePart.CFrame = muzzle
	self.ChargeEmitter.Rate = 6 + 40 * math.clamp(level or 0, 0, 1)
	self.ChargeEmitter.Enabled = true
end

-- Per frame while flying.
function LauncherBall:Step(dt)
	local flight = self.Flying
	if not flight then
		return
	end
	flight.Age += dt
	local model = self.Model
	if not model then
		self.Flying = nil
		return
	end
	-- grow back to full size if it was born small in a barrel
	if (self.CurrentScale or self.BaseScale) < self.BaseScale then
		self:_setScale(math.min(1, (self.CurrentScale / self.BaseScale) + dt / 0.1))
	end

	local real = flight.Real
	if not real then
		local found = self:_realBall()
		if found and found ~= flight.Old and found.Parent then
			self:_beginHandoff(found)
			real = found
		end
	end

	if real then
		flight.HandoffAge += dt
		local k = smooth(flight.HandoffAge / flight.HandoffTime)
		if real.Parent then
			-- the copy's lead over the real ball melts away; the visible ball never runs backwards
			flight.Position = real:GetPivot().Position + flight.Offset * (1 - k)
		end
		model:PivotTo(CFrame.new(flight.Position))
		if k >= 1 or not real.Parent then
			if real.Parent then
				hideReal(real, false)
			end
			self:_endFlight()
		end
		return
	end

	flight.Velocity += Vector3.new(0, -workspace.Gravity * GRAVITY_SCALE * dt, 0)
	flight.Position += flight.Velocity * dt
	model:PivotTo(CFrame.new(flight.Position))
	if flight.Age > GHOST_LIFETIME then
		self:_endFlight()
	end
end

-- The real ride ball is here: hide it and let the copy's lead over it shrink to nothing, slower
-- than the real ball moves (smoothstep peaks at 1.5 / T), so the ball keeps going forward.
function LauncherBall:_beginHandoff(found)
	local flight = self.Flying
	flight.Real = found
	flight.HandoffAge = 0
	flight.Offset = flight.Position - found:GetPivot().Position
	local root = if found:IsA("BasePart") then found else (found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true))
	local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
	flight.HandoffTime = math.clamp(1.5 * flight.Offset.Magnitude / math.max(speed, 1), HANDOFF_TIME, HANDOFF_MAX)
	hideReal(found, true)
end

function LauncherBall:_endFlight()
	self.Flying = nil
	self.Visible = false
	if self.Model then
		self.Model.Parent = nil
	end
end

function LauncherBall:IsFlying()
	return self.Flying ~= nil
end

function LauncherBall:Hide()
	if self.Flying then
		return
	end
	if self.EarlyReal and self.EarlyReal.Parent then
		hideReal(self.EarlyReal, false)
	end
	self.EarlyReal = nil
	if self.Model then
		self.Model.Parent = nil
	end
	self.Visible = false
	self:_bands(false)
end

function LauncherBall:Destroy()
	local flight = self.Flying
	if flight and flight.Real and flight.Real.Parent then
		hideReal(flight.Real, false)
	end
	if self.EarlyReal and self.EarlyReal.Parent then
		hideReal(self.EarlyReal, false)
	end
	self.Flying, self.EarlyReal = nil, nil
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
	if self.ChargePart then
		self.ChargePart:Destroy()
		self.ChargePart, self.ChargeEmitter = nil, nil
	end
	self:_clearBands()
end

return LauncherBall

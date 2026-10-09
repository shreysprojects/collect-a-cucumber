--[[---------------------------------------DESCRIPTION------------------------------------------
	Mountain types, difficulty order, and the shared attachment pieces they use.
	Terrain pieces live in ServerStorage.Assets.Storage.Maps.Attachments.
	Themed props live in ServerStorage.Assets.Storage.Props/<MountainId>.

--------------------------------------------------------------------------------------------]]--

local config = {}

config.WORKSPACE_NAME = "GeneratedMountain"
config.STORAGE_FOLDER = "Maps"
config.ATTACHMENTS_MODEL = "Attachments"

config.SOCKETS = {
	Root = "Root",
	Entrance = "Entrance",
	Exit = "Exit",
	LaunchPoint = "LaunchPoint",
	LandmarkPoint = "LandmarkPoint",
}

config.LAUNCH_PAD = {
	Model = "LaunchPlatform",
	Collision = "Collision",
}

-- Piece types. Every mountain can use these; generation uses whichever models exist.
config.Attachments = {
	"StartPlatform",
	"Downhill_Gentle",
	"Downhill_Steep",
	"Valley_Small",
	"Valley_Large",
	"Uphill_Small",
	"Uphill_Large",
	"Drop",
	"JumpRamp",
	"Flat_Transition",
	"DestructionZone",
	"FinishPlatform",
}

config.Attachment = {}
for _, name in config.Attachments do
	config.Attachment[name] = name
end

-- Easiest to hardest. Every mountain reuses Maps.Attachments; only Props differ.
config.MountainOrder = {
	"Frostpeak",
	"Christmas",
	"Candy",
	"PirateGlacier",
	"Haunted",
	"Volcano",
	"Tech",
	"Cosmic",
}

config.Mountains = {
	Frostpeak = {
		DisplayName = "Frostpeak",
		Description = "A traditional snowy mountain filled with pine trees, cabins, ski lifts and frozen lakes. Its wide slopes and gentle hills introduce players to the game.",
		Props = {
			Trees = { "Pine_Small", "Pine_Tall", "Pine_SnowCovered" },
			Rocks = { "Boulder_Small", "Boulder_Large", "Boulder_Icy" },
			Start = { "Sign_Welcome", "Equipment_Rack", "Cabin_SkiRental", "Sled_Red" },
			Valley = { "Pine_SnowCovered", "Cabin_Small", "Snowman_Scarf", "WoodPile" },
			Targets = {
				"Snowman_Basic",
				"Fence_Straight",
				"Snowmobile_Red",
				"WoodPile",
				"Cabin_Small",
				"Snowman_BucketHat",
				"Snowmobile_Blue",
				"Fence_Broken",
				"Chalet_Large",
			},
			Finish = { "Resort_Flag", "Chalet_Large", "Cabin_SkiRental", "Cabin_Small", "Sled_Red", "Sign_Welcome", "Pine_SnowCovered" },
			JumpOrDrop = "Warning_Pole",
			FlatFirst = "Sign_Distance",
			FlatOther = "Pine_SnowCovered",
			Landmark = "Lodge_Giant",
			PlaceFinalLodge = true,
		},
	},
	Christmas = {
		DisplayName = "Christmas",
		Description = "A festive nighttime mountain covered in colorful lights, presents, candy canes and holiday decorations, ending at Santa’s Workshop.",
	},
	Candy = {
		DisplayName = "Candy",
		Description = "A bright fantasy mountain made from frosting, chocolate and candy. Players roll past giant lollipops, cookies, gumdrops and gingerbread buildings.",
	},
	PirateGlacier = {
		DisplayName = "Pirate Glacier",
		Description = "A frozen coastal mountain containing shipwrecks, treasure chests, cannons and icy pirate villages, ending at a massive frozen pirate ship.",
	},
	Haunted = {
		DisplayName = "Haunted",
		Description = "A mysterious moonlit mountain filled with blue snow, dead forests, pumpkins, gravestones and ghosts, with a haunted castle waiting at the end.",
	},
	Volcano = {
		DisplayName = "Volcano",
		Description = "A dangerous mountain covered in ash, volcanic rocks, lava rivers and ancient ruins. The snowball becomes increasingly meteor-like as it travels.",
	},
	Tech = {
		DisplayName = "Tech",
		Description = "A futuristic metal mountain featuring neon tracks, robots, drones, laser gates and powerful energy reactors.",
	},
	Cosmic = {
		DisplayName = "Cosmic",
		Description = "The final mountain, stretching through space across asteroids, planets and floating space stations, ending at an enormous alien mothership.",
	},
}

for index, mountainId in config.MountainOrder do
	local mountain = config.Mountains[mountainId]
	if mountain then
		mountain.Id = mountainId
		mountain.Difficulty = index
	end
end

config.SNOW = {
	Enabled = true,
	Thickness = 1.2,
	PatchesPerGroup = 6,
	TrackPrefix = "Track_",
	CollisionFolder = "Collision",
	VisualFolder = "Visual",
	PatchesFolder = "SnowPatches",
	FoundationColor = Color3.fromRGB(104, 113, 124),
	FoundationMaterial = Enum.Material.Slate,
	SnowColor = Color3.fromRGB(244, 250, 255),
	SnowMaterial = Enum.Material.Plastic,
	AmountDivisor = 200,
	CoverStartPlatform = false,
	CollectStartPlatform = false,
}

-- Props are scattered procedurally per piece (see ServerStorage.Modules.PlaceMountainProps).
-- They live in workspace[WorkspaceFolder]/<PieceName> so streaming only sends nearby ones.
config.PROPS = {
	Enabled = false,
	StorageFolder = "Props",
	DecorFolder = "Decorations",
	WorkspaceFolder = "MountainDecor",
	Tag = "MountainProp",
	TreeChance = 0.7,
	PlaceFinalLodge = true,

	Density = 1, -- global multiplier for how much gets scattered
	EdgeMargin = 3, -- keep footprints this far inside the 100-stud track edge
	LaneHalfWidth = 30, -- smashable props are scattered within this |x|
	LaneSpread = 16, -- gaussian spread of lane props around the centre line
	TreeStep = { 26, 44 }, -- along-track spacing of the edge tree line
	SkiLiftStretch = { 2, 3 }, -- pieces per ski-lift line
	SkiLiftGap = { 4, 8 }, -- pieces between ski-lift lines
	SkiLiftChairChance = 0.5, -- chance of a chair hanging on each cable span
	SkiLiftSpan = 40, -- cable segment length (SkiLift_CableSegment is 40 long)
	DistanceSignEvery = 1000,
	MaxSlope = { -- degrees; anything steeper rejects the prop
		Building = 18,
		Pond = 5,
		Fence = 32,
		Tree = 42,
		Rock = 42,
		Snowman = 28,
		Equipment = 28,
		Vehicle = 24,
		Sign = 34,
		SkiLift = 38,
		WoodPile = 30,
		Landmark = 20,
		Scenery = 30,
		Default = 30,
	},
	-- Props with a footprint at least this wide count as "big" (edge/hamlet items)
	BigFootprint = 12,
	-- How many lane props per 100 studs of track, per piece kind (times Density)
	LaneDensity = {
		DestructionZone = 4.2,
		Flat_Transition = 1.6,
		Downhill_Gentle = 1.1,
		Downhill_Steep = 0.7,
		Valley_Small = 1.3,
		Valley_Large = 1.2,
		Uphill_Small = 1.0,
		Uphill_Large = 0.9,
		JumpRamp = 0.5,
		Drop = 0,
		FinishPlatform = 0.8,
	},
	HamletChance = {
		DestructionZone = 1,
		Flat_Transition = 0.9,
		Valley_Small = 0.9,
		Valley_Large = 1,
		Downhill_Gentle = 0.5,
		Uphill_Small = 0.55,
		Uphill_Large = 0.6,
		FinishPlatform = 1,
	},
	PondChance = 0.45,
	FadeTime = 0, -- smashed structures vanish instantly (server removes them 0.5 s later)
	FadeRise = 0,
}

-- Snowball air physics + landing feel. Forces run on the network-owning client.
config.FLIGHT = {
	LiftFraction = 0.26, -- fraction of gravity cancelled while falling (glide)
	LiftRisingFactor = 0.3, -- lift while still climbing, as a fraction of LiftFraction
	GlideFraction = 0.04, -- forward push while airborne, as a fraction of weight
	MinAirTime = 0.12, -- seconds off the ground before it counts as flight
	TrickChance = 0.9,
	TrickDelay = 0.1, -- seconds after takeoff before the trick spin kicks in
	Tricks = { -- name = weight
		Glide = 3,
		Backspin = 3,
		BarrelRoll = 3,
		Corkscrew = 2,
		Tumble = 2,
	},
	BarrelRollSpin = 12,
	CorkscrewSpin = 10,
	TumbleSpin = 14,
	BackspinFactor = -0.6, -- multiple of the natural rolling spin
	PreLandTime = 0.07, -- seconds of look-ahead used to restore a rolling spin before touchdown
	-- Momentum keeper (impacts only): speed that collapses below ImpactRatio of its
	-- recent peak gets ImpactKeep of that peak back along the slope, pointing downhill.
	PeakDecay = 400, -- studs/s^2 the remembered peak may fall without counting as an impact
	ImpactMinSpeed = 60,
	ImpactRatio = 0.7,
	ImpactKeep = 0.82,
	LandingBurstMinAir = 0.25, -- flights shorter than this land quietly
	LandingKick = 0.9, -- camera kick strength per 100 studs/s of impact speed
	GroundProbe = 1.6, -- extra raycast reach below the ball radius
	-- Glide over holes in the track (jump gaps) instead of dropping into them.
	GapGuard = {
		NearTime = 0.25, -- seconds ahead to check for ground under the ball
		FarTime = 0.7, -- seconds ahead to look for the landing
		FarMin = 80, -- studs, minimum look-ahead
		ClimbSpeed = 45, -- upward speed used when the landing is higher than the ball
		Blend = 5, -- per-second blend of vertical speed toward the target
	},
	-- Left/right wandering across the 100-stud track (smooth noise + a pull toward
	-- structures ahead) so the ball carves instead of rolling a straight line.
	Wander = {
		Amplitude = 38, -- studs either side of the centre line the wander target reaches
		Speed = 0.5, -- how fast the wander target changes (noise time scale)
		Gain = 2.4, -- lateral speed per stud of offset from the target
		MaxHeading = 0.45, -- lateral speed cap as a fraction of forward speed
		GroundBlend = 3.5, -- per-second blend toward the wanted lateral speed on the ground
		AirBlend = 0.9, -- ...and in the air
		EdgeLimit = 40, -- beyond this |x| the ball is pushed back hard
		Seek = 0.55, -- 0..1 pull of the wander target toward the nearest structure ahead
		SeekRange = 110, -- studs ahead to look for structures
		SeekWidth = 34, -- half-width of that search box
		SeekInterval = 0.12, -- seconds between structure searches
	},
}

config.SMASH = {
	-- Tiny: dozens of hits per run must not bleed the ball dry (47 hits at 1.5-6% cost ~70% speed)
	SpeedLoss = { Building = 0.012, Landmark = 0.012, SkiLift = 0.006, Default = 0.002 },
	Kick = { Building = 1.2, Landmark = 1.4, SkiLift = 0.6, Default = 0.35 },
	ServerReach = 140, -- extra studs of tolerance when the server validates a hit
	SmashSound = false, -- smashes are silent (the white burst is the feedback)
	Explosion = { -- soft white burst on every destroyed structure
		Scale = 1,
		Density = 1,
		SphereTime = 0.3,
	},

	-- Combo: every smash stacks while hits keep coming within ComboWindow seconds.
	ComboWindow = 2.5,
	ComboPopScale = 2.6, -- how big the label pops on a hit before shrinking to the top
	ComboPopTime = 0.5,
	ComboStartY = 0.4, -- screen fraction where the pop starts (centre-ish)
	ComboTopY = 0, -- screen fraction where it settles (top)...
	ComboTopOffset = 108, -- ...plus pixels, so it sits under the compact race bar (y 14-48) and its labels
	ComboFadeTime = 0.45,
	ComboColor = Color3.fromRGB(255, 138, 0),
	ComboFlashColor = Color3.fromRGB(255, 236, 190),
	ComboStrokeColor = Color3.fromRGB(105, 42, 0),
	ComboKickPerStack = 0.06, -- extra camera kick / burst per stack (capped by ComboMaxBonus)
	ComboMaxBonus = 1,
	ComboPitchPerStack = 0.025, -- crash sound pitch rises with the combo
}

config.SOUNDS = {
	Whoosh = "rbxassetid://9126229255",
	Thud = "rbxassetid://9118616114",
	BigThud = "rbxassetid://9113480915",
	CrashBig = "rbxassetid://9120957636",
	CrashSmall = "rbxassetid://9126267420",
	Volume = { Whoosh = 1.2, Thud = 2, BigThud = 2.2, CrashBig = 1.8, CrashSmall = 1.6 },
}

-- LaunchPoint is on the rolling surface; ExtraHeight sits the character above snow.
config.SPAWN = {
	ExtraHeight = 3,
}

config.LAUNCH = {
	StorageFolder = "Snowballs",
	CollisionTemplate = "BallCollision",
	ThrustSpeed = 90,
	UpSpeed = 0,
	ThrustDuration = 0.35,
	Elasticity = 0.35, -- ball bounce on landing (snow is soft)
	ElasticityWeight = 3,
	BallScale = 1 / 1.5, -- the launched ball is 1.5x smaller than the template
	-- Hold-to-launch: hold click/touch on the pad, the bar fills to 100%, release fires.
	Charge = {
		Time = 1.5, -- seconds of holding to reach 100%
		MinSpeed = 30, -- launch speed at 0%
		MaxSpeed = 150, -- launch speed at 100%
		MinCharge = 0.03, -- taps shorter than this do nothing
		HintText = "HOLD TO LAUNCH",
	},
	ForwardOffset = 8,
	ExitOffset = 8,
	CameraDistance = 18,
	CameraHeight = 16,
	CameraClearance = 4,
	PadCameraDistance = 24,
	PadCameraHeight = 8,
	PadLookAhead = 10,
	StopSpeed = 0.45,
	StopSpin = 0.6,
	StopHold = 1,
	StopGrace = 1,
	-- Each eaten patch adds this volume; radius grows with the cube root.
	GrowVolumePerSnow = 1.6,
	GrowMaxScale = 8,
	GrowLerp = 10,
	GrowCollectPadding = 0.35,
}

local T = config.Attachment

config.DEFAULT_GRAMMAR = {
	MinPieces = 32,
	MaxPieces = 56,
	OriginCFrame = CFrame.new(0, 120, 0),
	Weights = {
		[T.Downhill_Gentle] = 4,
		[T.Downhill_Steep] = 3,
		[T.Valley_Small] = 2,
		[T.Valley_Large] = 1,
		[T.Uphill_Small] = 2,
		[T.Uphill_Large] = 1,
		[T.Drop] = 1,
		[T.JumpRamp] = 2,
		[T.Flat_Transition] = 3,
		[T.DestructionZone] = 1,
		[T.FinishPlatform] = 1,
	},
	MaxCount = {
		[T.DestructionZone] = 4,
		[T.Drop] = 8,
		[T.JumpRamp] = 8,
		[T.Valley_Large] = 8,
		[T.Uphill_Large] = 8,
	},
	Next = {
		[T.StartPlatform] = { T.Downhill_Steep },
		[T.Downhill_Gentle] = {
			T.Downhill_Gentle,
			T.Downhill_Steep,
			T.Valley_Small,
			T.Valley_Large,
			T.Flat_Transition,
			T.JumpRamp,
			T.Drop,
			T.Uphill_Small,
			T.DestructionZone,
			T.FinishPlatform,
		},
		[T.Downhill_Steep] = {
			T.Downhill_Gentle,
			T.Flat_Transition,
			T.Valley_Small,
			T.JumpRamp,
			T.Drop,
			T.DestructionZone,
			T.FinishPlatform,
		},
		[T.Valley_Small] = { T.Downhill_Gentle, T.Downhill_Steep, T.Flat_Transition, T.Uphill_Small, T.FinishPlatform },
		[T.Valley_Large] = { T.Downhill_Gentle, T.Uphill_Small, T.Uphill_Large, T.Flat_Transition },
		[T.Uphill_Small] = { T.Downhill_Gentle, T.Downhill_Steep, T.Flat_Transition, T.JumpRamp },
		[T.Uphill_Large] = { T.Downhill_Steep, T.Drop, T.JumpRamp, T.Flat_Transition },
		[T.Drop] = { T.Flat_Transition, T.Valley_Small, T.Downhill_Gentle },
		[T.JumpRamp] = { T.Flat_Transition, T.Valley_Small, T.Downhill_Gentle },
		[T.Flat_Transition] = {
			T.Downhill_Gentle,
			T.Downhill_Steep,
			T.Valley_Small,
			T.Valley_Large,
			T.Uphill_Small,
			T.JumpRamp,
			T.Drop,
			T.DestructionZone,
			T.FinishPlatform,
		},
		[T.DestructionZone] = { T.Downhill_Gentle, T.Flat_Transition, T.Valley_Small, T.FinishPlatform },
	},
}

local function copyGrammar(src)
	local copy = {
		MinPieces = src.MinPieces,
		MaxPieces = src.MaxPieces,
		OriginCFrame = src.OriginCFrame,
		Weights = table.clone(src.Weights),
		MaxCount = table.clone(src.MaxCount),
		Next = {},
	}
	for from, tos in src.Next do
		copy.Next[from] = table.clone(tos)
	end
	return copy
end

local function mergeNext(baseList, extra)
	local merged = table.clone(baseList or {})
	local seen = {}
	for _, name in merged do
		seen[name] = true
	end
	for _, name in extra do
		if not seen[name] then
			table.insert(merged, name)
			seen[name] = true
		end
	end
	return merged
end

function config:GetMountain(mountainId)
	return self.Mountains[mountainId]
end

function config.IsOnLaunchPad(position, collision)
	if typeof(position) ~= "Vector3" or not collision or not collision:IsA("BasePart") then
		return false
	end

	local localPoint = collision.CFrame:PointToObjectSpace(position)
	local half = collision.Size * 0.5
	return math.abs(localPoint.X) <= half.X + 1
		and math.abs(localPoint.Z) <= half.Z + 1
		and localPoint.Y >= -half.Y - 1
		and localPoint.Y <= half.Y + 12
end

function config:GetDisplayName(mountainId)
	local mountain = self.Mountains[mountainId]
	return if mountain then mountain.DisplayName or mountainId else mountainId
end

function config:GetDifficulty(mountainId)
	local mountain = self.Mountains[mountainId]
	return if mountain then mountain.Difficulty else nil
end

function config:GetNextMountain(mountainId)
	local difficulty = self:GetDifficulty(mountainId)
	if not difficulty then
		return nil
	end
	return self.MountainOrder[difficulty + 1]
end

function config:GetPreviousMountain(mountainId)
	local difficulty = self:GetDifficulty(mountainId)
	if not difficulty or difficulty <= 1 then
		return nil
	end
	return self.MountainOrder[difficulty - 1]
end

function config:GetSnowSettings(mountainId)
	local snow = table.clone(self.SNOW)
	local mountain = self.Mountains[mountainId]
	if not mountain then
		return snow
	end

	if mountain.BuildSnow ~= nil then
		snow.Enabled = mountain.BuildSnow
	end
	if mountain.Snow then
		for key, value in mountain.Snow do
			snow[key] = value
		end
	end

	return snow
end

function config:GetPropSettings(mountainId)
	local settings = table.clone(self.PROPS)
	local mountain = self.Mountains[mountainId]
	if not mountain or not mountain.Props then
		settings.Enabled = false
		return settings
	end

	settings.Enabled = true
	settings.LibraryName = mountain.Props.LibraryName or mountainId
	for key, value in mountain.Props do
		settings[key] = value
	end

	return settings
end

function config:GetGrammar(mountainId)
	local grammar = copyGrammar(self.DEFAULT_GRAMMAR)
	local mountain = self.Mountains[mountainId]
	if not mountain then
		return grammar
	end

	if mountain.MinPieces then
		grammar.MinPieces = mountain.MinPieces
	end
	if mountain.MaxPieces then
		grammar.MaxPieces = mountain.MaxPieces
	end
	if mountain.OriginCFrame then
		grammar.OriginCFrame = mountain.OriginCFrame
	end
	if mountain.Weights then
		for name, weight in mountain.Weights do
			grammar.Weights[name] = weight
		end
	end
	if mountain.MaxCount then
		for name, count in mountain.MaxCount do
			grammar.MaxCount[name] = count
		end
	end
	if mountain.Next then
		for from, extra in mountain.Next do
			grammar.Next[from] = mergeNext(grammar.Next[from], extra)
		end
	end

	if grammar.MinPieces > grammar.MaxPieces then
		grammar.MinPieces = grammar.MaxPieces
	end

	return grammar
end

return function()
	return config
end


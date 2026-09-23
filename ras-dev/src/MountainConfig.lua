--[[---------------------------------------DESCRIPTION------------------------------------------
	Mountain types, difficulty order, and the shared attachment pieces they use.
	Terrain pieces live in ServerStorage.Assets.Storage.Maps.Attachments.
	Themed props live in ServerStorage.Assets.Storage.Props/<MountainId>.

	Difficulty 1–8 is the mountain order. Later mountains are steeper, and their
	coast resistance matches the snowball × launcher power you can own from the
	previous mountain. Each mountain also has its own Length in meters (studs).
	Snowballs and launchers share one 30-step ladder split across those 8
	difficulties (see OrderDifficulty).

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

-- CollisionBox parts on StartPlatform block players, not the snowball.
config.PHYSICS = {
	SnowballGroup = "Snowball",
	PlayerBarrierGroup = "PlayerBarrier",
	PlayerBarrierName = "CollisionBox",
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
		Length = 10000,
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
		Length = 12847,
		Description = "A festive nighttime mountain covered in colorful lights, presents, candy canes and holiday decorations, ending at Santa’s Workshop.",
	},
	Candy = {
		DisplayName = "Candy",
		Length = 14763,
		Description = "A bright fantasy mountain made from frosting, chocolate and candy. Players roll past giant lollipops, cookies, gumdrops and gingerbread buildings.",
	},
	PirateGlacier = {
		DisplayName = "Pirate Glacier",
		Length = 15000,
		Description = "A frozen coastal mountain containing shipwrecks, treasure chests, cannons and icy pirate villages, ending at a massive frozen pirate ship.",
	},
	Haunted = {
		DisplayName = "Haunted",
		Length = 18620,
		Description = "A mysterious moonlit mountain filled with blue snow, dead forests, pumpkins, gravestones and ghosts, with a haunted castle waiting at the end.",
	},
	Volcano = {
		DisplayName = "Volcano",
		Length = 20000,
		Description = "A dangerous mountain covered in ash, volcanic rocks, lava rivers and ancient ruins. The snowball becomes increasingly meteor-like as it travels.",
	},
	Tech = {
		DisplayName = "Tech",
		Length = 24173,
		Description = "A futuristic metal mountain featuring neon tracks, robots, drones, laser gates and powerful energy reactors.",
	},
	Cosmic = {
		DisplayName = "Cosmic",
		Length = 28940,
		Description = "The final mountain, stretching through space across asteroids, planets and floating space stations, ending at an enormous alien mothership.",
	},
}

-- Same ladder for snowballs and launchers: 30 orders split across 8 mountains.
config.PROGRESSION_ORDERS = 30
config.DifficultyNames = {
	"Easy",
	"Medium",
	"Tricky",
	"Hard",
	"Intense",
	"Extreme",
	"Brutal",
	"Cosmic",
}

config.OrderDifficulty = {}
local mountainCount = #config.MountainOrder
for index, mountainId in config.MountainOrder do
	local firstOrder = math.floor((index - 1) * config.PROGRESSION_ORDERS / mountainCount) + 1
	local lastOrder = math.floor(index * config.PROGRESSION_ORDERS / mountainCount)
	for order = firstOrder, lastOrder do
		config.OrderDifficulty[order] = index
	end

	local mountain = config.Mountains[mountainId]
	if mountain then
		mountain.Id = mountainId
		mountain.Difficulty = index
		mountain.DifficultyName = config.DifficultyNames[index] or tostring(index)
		mountain.FirstOrder = firstOrder
		mountain.LastOrder = lastOrder
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
	-- Grid of carvable tiles laid by BuildMountainSnow.
	TileSize = 2,
	Layers = 1,
	TileOverlap = 0,
	Budget = {
		MaxTiles = 80000,
		TilesPerStep = 1500,
	},
	Grid = {
		CellSize = 8, -- SnowField hash-grid cell size
	},
	-- Rolling carves this trail (SERV_Snowball, SnowField, the riding client).
	Carve = {
		Interval = 0.05, -- seconds between carve steps
		Depth = 1, -- snow layers removed per column per step
		Width = 0, -- 0 = ball diameter * WidthScale + WidthPadding*2
		WidthScale = 1,
		WidthPadding = 0,
		MinWidth = 2,
		MaxWidth = 48,
		SampleLift = 4, -- studs above a reported contact to start the ground ray
		GroundProbe = 2.5, -- extra ray reach below the ball / contact
		ClientReach = 60, -- max distance a client CarveSnow point may be from the ball
		SurfaceTolerance = 2.5, -- how far a column may sit off the contact plane
		NormalDot = 0.5, -- min alignment with the contact normal
		MaxColumnsPerStep = 400,
		MaxSweep = 240, -- skip filling the trail if the last contact is farther than this
		MaxSamples = 16, -- samples along the sweep between last and current contact
		MaxDrop = 6, -- extra downward reach when sampling the sweep
	},
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

-- Visual rock borders along both playable edges. Independent of PROPS.Enabled.
-- Templates live in ServerStorage.Assets.Storage.BorderClusters. Generated clones
-- go to workspace.MountainBorders and are never smashable or carvable snow.
config.BORDERS = {
	Enabled = true,
	LibraryFolder = "Storage",
	LibraryName = "BorderClusters",
	WorkspaceFolder = "MountainBorders",

	ScaleMin = 1.5,
	ScaleMax = 2.0,
	Spacing = 18, -- floor on pivot travel so a bad footprint cannot stack clusters
	OverlapFraction = 0.3, -- share of the smaller rock footprint that overlaps the next
	EdgeClearance = 1.5,
	MaxYaw = 6, -- degrees
	TallOutset = 4, -- extra studs so tall peaks sit further outside the lane
	BaseSink = 0.15,

	-- Continuous base under the clusters. When MaxParts is tight these sections
	-- get longer; they are not spread apart into gaps.
	FoundationLength = 24,
	FoundationOverlap = 8,
	FoundationMinLength = 7,
	FoundationWidth = 16,
	FoundationHeight = 11, -- body below the edge; grown where the chord leaves the polyline
	FoundationLip = 1, -- studs of the edge buried into the top of a section
	FoundationBite = 0.25, -- inner face may kiss the lip, not the playable lane
	FoundationWedgeDrop = 6, -- wedge once the edge rises at least this much along a section
	FoundationChord = 3.5, -- max studs a section may leave the edge polyline
	FoundationLengthMax = 80,
	FoundationChordMax = 14,
	FoundationCap = 1.35,

	CapChance = 0.9,
	RockColor = Color3.fromRGB(104, 113, 124),
	CapColor = Color3.fromRGB(244, 250, 255),

	MaxClusters = 500,
	MaxParts = 6000,
	ClustersPerYield = 12,

	SampleStep = 4,
	Dedup = 2.5,
	GapBreak = 14, -- split an edge run when the surface jumps this far
	SeamJoin = 12, -- join section edges that meet within this distance
	ProbeXZ = 2,
	ProbeY = 4,
	MinSurfaceY = 0.3, -- skip near-vertical faces; 0.3 is about a 72° slope

	LipClearance = 8,
	FlightClearance = 22,
	LaunchClearance = 26,
	FinishClearance = 22,
	TransitionMargin = 18,
	SteepAngle = 12,
	TallChance = 0.18,
	SteepTallChance = 0.85,

	LowTemplates = { "LowRidge", "WideRidge" },
	TallTemplates = { "SteppedCliff", "TallPeak", "TwinPeak" },
}

config.BorderThemes = {
	Frostpeak = {
		RockColor = Color3.fromRGB(104, 113, 124),
		CapColor = Color3.fromRGB(244, 250, 255),
		CapChance = 0.90,
	},
	Christmas = {
		RockColor = Color3.fromRGB(68, 100, 89),
		CapColor = Color3.fromRGB(250, 252, 255),
		CapChance = 0.95,
	},
	Candy = {
		RockColor = Color3.fromRGB(173, 109, 154),
		CapColor = Color3.fromRGB(255, 237, 247),
		CapChance = 0.90,
	},
	PirateGlacier = {
		RockColor = Color3.fromRGB(81, 148, 174),
		CapColor = Color3.fromRGB(222, 248, 255),
		CapChance = 0.80,
	},
	Haunted = {
		RockColor = Color3.fromRGB(80, 67, 102),
		CapColor = Color3.fromRGB(196, 205, 234),
		CapChance = 0.45,
	},
	Volcano = {
		RockColor = Color3.fromRGB(66, 60, 59),
		CapColor = Color3.fromRGB(167, 159, 151),
		CapChance = 0.15,
	},
	Tech = {
		RockColor = Color3.fromRGB(87, 109, 129),
		CapColor = Color3.fromRGB(217, 243, 250),
		CapChance = 0.35,
	},
	Cosmic = {
		RockColor = Color3.fromRGB(104, 77, 148),
		CapColor = Color3.fromRGB(225, 217, 255),
		CapChance = 0.35,
	},
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
	-- Momentum keeper: only a fast ball plows through kinks. Slower impacts keep
	-- the speed they lost (and a little more) so the ride can actually stop.
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
	-- Track edges + optional player steer while rolling. No auto left/right weave;
	-- flight is vertical only (AirBlend bleeds leftover sideways speed).
	Wander = {
		Gain = 2.4, -- lateral speed per stud of offset from a player steer target
		MaxHeading = 0.45, -- leftover lateral speed cap as a fraction of forward speed
		GroundBlend = 3.5, -- per-second blend toward 0 (or player steer) on the ground
		AirBlend = 2.2, -- bleed sideways speed in the air so flight stays up/down
		EdgeLimit = 40, -- beyond this |x| the ball is pushed back hard
		PlayerHeading = 0.28, -- extra lateral speed as a fraction of forward speed at full input
		PlayerMaxHeading = 0.7, -- heading cap while the player is steering
		PlayerBlend = 7, -- ground blend while steering
	},
}

-- Rolling resistance + energy. Launch charge (0..1) lerps each {weak, strong} pair.
-- Energy drains over the ride; when it runs out the ball brakes to a stop even on slopes.
config.COAST = {
	MaxSpeed = { 48, 86 }, -- hard horizontal cap at charge 0 / charge 1
	CapFloor = 0.32, -- cap stays at least this fraction of MaxSpeed as energy fades
	GroundDrag = { 16, 5 }, -- studs/s^2 rolling resistance
	AirDrag = { 10, 3.5 },
	GroundDamp = { 0.55, 0.14 }, -- exponential speed decay /s
	AirDamp = { 0.35, 0.1 },
	EmptyDragBonus = 2.2, -- drag multiplier added as energy 1 → 0
	EnergyDrain = { 0.085, 0.024 }, -- energy/s (weak ~12s, strong ~42s before brakes)
	BrakeBelow = 0.2, -- extra braking starts under this remaining energy
	BrakeAccel = 36, -- extra linear studs/s^2 once spent
	BrakeDamp = 5, -- extra exponential decay /s once spent
	SpinDamp = 4, -- angular-velocity fade /s while braking
	FastSpeed = 78, -- at/above this, hits barely slow the ball (it plows through)
	FastSmashScale = 0.18, -- remaining smash / hit penalty when fast
	HitSlow = 0.08, -- extra fraction lost on a slow object/terrain impact
}

config.SMASH = {
	-- Hits bleed speed unless the ball is already going COAST.FastSpeed (it plows through).
	SpeedLoss = { Building = 0.1, Landmark = 0.12, SkiLift = 0.055, Default = 0.05 },
	EnergyLoss = { Building = 0.055, Landmark = 0.065, SkiLift = 0.03, Default = 0.022 },
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
	ComboTopOffset = 108, -- ...plus pixels: the highest it settles (it also drops below the HUD readouts below)
	ComboAvoid = { "DistanceRolled", "CoinsMade" }, -- PlayerGui.HUD labels the settled combo must stay under
	ComboClearGap = 6, -- px between those labels and the settled combo text
	ComboAvoidPop = 1.45, -- biggest EarnPop scale the HUD gives CoinsMade (HUD popCoinsMade clamp)
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
-- The rest keeps characters from falling off the map on join (SERV_PlayerEvents +
-- CLIENT_SpawnGuard): the server anchors each new character, places it on the pad
-- once the mountain exists, and lets go when the client reports the pad's floor
-- under it (the mountain is one Persistent model, so a joining client can get it
-- seconds after its character is placed).
config.SPAWN = {
	ExtraHeight = 3,
	SpawnLocationName = "MountainSpawn", -- invisible Neutral SpawnLocation on the launch pad (workspace)
	SpawnLocationSize = Vector3.new(4, 1, 4),
	HoldAttribute = "SpawnHold", -- character attribute: hold token while the server anchors it on the pad
	ParentTimeout = 5, -- seconds the server waits for a new character to be parented before holding it
	SpawnKeepRadius = 4, -- flat studs from the pad spawn inside which an engine spawn is kept (no server re-pivot)
	HoldTimeout = 30, -- seconds a placed character stays anchored waiting for the client's floor report
	StreamTimeout = 10, -- RequestStreamAroundAsync timeout for the pad
	FloorProbe = 40, -- studs below the root part searched for mountain floor (client)
	AckResend = 0.5, -- seconds between the client's SpawnReady reports while still held
	AckTolerance = 12, -- studs between the reported and the placed root position
	FallDepth = 60, -- studs below the StartPlatform (near it) or the whole mountain before the failsafe acts
	StartMargin = 40, -- studs around the StartPlatform footprint that still count as "at the start"
	FailsafeInterval = 0.5, -- seconds between server failsafe sweeps
	-- ReplicatedStorage.Assets.GameInfo attributes the server stamps once the mountain is built.
	InfoSpawnCFrame = "SpawnCFrame",
	InfoStartBoxCFrame = "StartBoxCFrame",
	InfoStartBoxSize = "StartBoxSize",
}

-- Reaching FinishPlatform parks the ball in front of it (chase camera stays on
-- the ball), then unlocks the next mountain.
config.FINISH = {
	StandBack = 16, -- studs uphill of the finish entrance, facing the platform
	ArriveHold = 2, -- seconds to stand there before unlock + teleport
	ReportInterval = 0.6, -- how often the rider re-reports the finish while the server catches up
	ReportWindow = 6, -- give up and end the ride normally if the server never accepts
}

config.LAUNCHER = {
	StorageFolder = "SnowballLaunchers",
	InstanceName = "EquippedLauncher",
	Grip = "Grip",
	HandGrip = "RightGripAttachment",
	-- The launcher model is scaled about its grip pivot when it is handed out, so it
	-- reads from the pad camera (the templates are 2-4 studs long at 1x).
	Scale = 1.5,
	-- Launch pad stance: standing still, charging or releasing on the pad turns the
	-- character side-on so the pad camera (behind, looking down the track) sees the
	-- launcher and its charge animation. Walking hands turning back to the Humanoid.
	-- The launch itself always goes down the track.
	PadStance = {
		Enabled = true, -- false = face down the track (the old stance)
		Yaw = -90, -- degrees from facing down the track: -90 = right side (launcher hand) to the camera, 90 = left side
		TurnRate = 10, -- ease speed (1/s): about 95% of the turn in 0.3 s
		WalkThreshold = 0.1, -- Humanoid.MoveDirection magnitude that counts as walking
	},
}

config.LAUNCH = {
	StorageFolder = "Snowballs",
	CollisionTemplate = "BallCollision",
	ThrustSpeed = 90,
	UpSpeed = 0,
	ThrustDuration = 0.22,
	ThrustBoost = 0.22, -- extra speed added over ThrustDuration, as a fraction of launch speed
	Elasticity = 0.35, -- ball bounce on landing (snow is soft)
	ElasticityWeight = 3,
	Friction = 0.55,
	FrictionWeight = 2,
	BallScale = 1 / 1.5, -- the launched ball is 1.5x smaller than the template
	-- Hold-to-launch: bar fills to 100% quickly, then ping-pongs 100% ↔ 0% until release.
	Charge = {
		FillTime = 0.42, -- seconds to first reach 100%
		Time = 1.2, -- seconds for 100% → 0% (and 0% → 100%) while holding
		MinSpeed = 22, -- launch speed at 0%
		MaxSpeed = 78, -- launch speed at 100%
		MinCharge = 0.03, -- taps shorter than this do nothing
		HintText = "HOLD TO LAUNCH",
	},
	-- EquipmentMultiplier (snowball order × launcher order) scales launch speed.
	-- Above 1x the throw levels out and lofts, so the ball flies before it falls.
	MaxPoweredSpeed = 12000,
	LoftPerMultiplier = 26, -- extra upward studs/s for each point of multiplier above 1
	MaxLoft = 120,
	ForwardOffset = 8,
	ExitOffset = 8,
	CameraDistance = 18,
	CameraHeight = 16,
	CameraClearance = 4,
	-- Pad camera: behind the pad centre (which sits ~3 studs above the floor), looking
	-- a little past the character. Close enough that the launcher and the throw read.
	PadCameraDistance = 13,
	PadCameraHeight = 3,
	PadLookAhead = 3,
	-- The chase camera follows the ball from the frame it leaves the launcher: no hold on
	-- the throw and no delayed blend. With ChaseFromPadCamera the camera position starts
	-- where the pad camera was and settles behind the ball through the chase follow (about
	-- 0.3 s), one continuous shot; false = cut straight to the chase framing instead.
	ChaseFromPadCamera = true,
	-- The ride ball starts where the launcher lets it go (the clip's Seat / Muzzle point at its
	-- fire moment, reported by the client) instead of on the ground ahead of the pad, as long as
	-- that point is within MaxDistance studs of the character with nothing solid in between.
	MuzzleSpawn = { Enabled = true, MaxDistance = 14, FloorClearance = 0.05, CollisionGroup = "Snowball" },
	-- Auto-stop (same as the Stop button) once the ball is idle or crawling.
	StopSpeed = 8, -- studs/s horizontal; at or below this counts as barely moving
	StopHold = 0.75, -- seconds it must stay that slow before the ride ends
	StopGrace = 1.25, -- ignore auto-stop this long after launch (stream/physics hitch)
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

function config.FindFinishPlatform(mountain)
	if typeof(mountain) ~= "Instance" then
		return nil
	end

	local name = config.Attachment.FinishPlatform
	for _, child in mountain:GetChildren() do
		if child:GetAttribute("AttachmentType") == name or string.sub(child.Name, 1, #name) == name then
			return child
		end
	end
	return nil
end

function config.IsOnFinishPiece(piece, position, padding)
	if typeof(piece) ~= "Instance" or typeof(position) ~= "Vector3" then
		return false
	end

	local ok, cf, size = pcall(piece.GetBoundingBox, piece)
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return false
	end

	padding = tonumber(padding) or 8
	local localPos = cf:PointToObjectSpace(position)
	local half = size * 0.5
	return math.abs(localPos.X) <= half.X + padding
		and math.abs(localPos.Z) <= half.Z + padding
		and localPos.Y <= half.Y + padding + 40
		and localPos.Y >= -half.Y - padding
end

-- A fast ball can cross the whole finish piece in one frame. Returns a point on it.
function config.FinishContact(piece, fromPos, toPos, padding)
	if typeof(toPos) ~= "Vector3" then
		return nil
	end
	if config.IsOnFinishPiece(piece, toPos, padding) then
		return toPos
	end
	if typeof(fromPos) ~= "Vector3" then
		return nil
	end
	if config.IsOnFinishPiece(piece, fromPos, padding) then
		return fromPos
	end

	local steps = math.clamp(math.ceil((toPos - fromPos).Magnitude / 25), 1, 16)
	for step = 1, steps - 1 do
		local point = fromPos:Lerp(toPos, step / steps)
		if config.IsOnFinishPiece(piece, point, padding) then
			return point
		end
	end
	return nil
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

function config:GetLength(mountainId)
	local mountain = self.Mountains[mountainId]
	local length = mountain and mountain.Length
	if type(length) ~= "number" or length <= 0 then
		return nil
	end
	return math.floor(length)
end

function config:GetDifficultyName(mountainId)
	local mountain = self.Mountains[mountainId]
	return if mountain then mountain.DifficultyName else nil
end

function config.DifficultyForOrder(order)
	local difficulty = config.OrderDifficulty[order]
	if difficulty then
		return difficulty
	end
	if type(order) ~= "number" or order < 1 then
		return 1
	end
	return #config.MountainOrder
end

function config:MountainIdForOrder(order)
	return self.MountainOrder[config.DifficultyForOrder(order)]
end

-- Power the previous mountain's shop can reach (snowball order × launcher order).
-- Mountain 1 expects the free starters. Later mountains expect that gear, clamped
-- to the launch-speed cap so a maxed throw can still finish the course.
function config:CoastResistance(mountainId)
	local mountain = self.Mountains[mountainId]
	local difficulty = mountain and mountain.Difficulty or 1
	local order = 1
	if difficulty > 1 then
		local previous = self.Mountains[self.MountainOrder[difficulty - 1]]
		order = previous and previous.LastOrder or 1
	end
	local maxSpeed = self.LAUNCH.Charge and self.LAUNCH.Charge.MaxSpeed or 78
	local cap = (self.LAUNCH.MaxPoweredSpeed or 12000) / math.max(maxSpeed, 1)
	return math.clamp(order * order, 1, cap)
end

function config:EffectivePower(multiplier)
	local maxSpeed = self.LAUNCH.Charge and self.LAUNCH.Charge.MaxSpeed or 78
	local cap = (self.LAUNCH.MaxPoweredSpeed or 12000) / math.max(maxSpeed, 1)
	local power = tonumber(multiplier) or 1
	if power < 1 then
		power = 1
	end
	return math.min(power, cap)
end

local function mix(easy, hard, t)
	return easy + (hard - easy) * t
end

function config:ApplyDifficulty(grammar, difficulty)
	local count = #self.MountainOrder
	difficulty = math.clamp(math.floor(tonumber(difficulty) or 1), 1, count)
	local steps = difficulty - 1
	local t = steps / math.max(count - 1, 1)
	grammar.MinPieces += steps * 6
	grammar.MaxPieces += steps * 8

	local weights = grammar.Weights
	local piece = self.Attachment
	weights[piece.Downhill_Gentle] = mix(weights[piece.Downhill_Gentle] or 4, 1, t)
	weights[piece.Downhill_Steep] = mix(weights[piece.Downhill_Steep] or 3, 6, t)
	weights[piece.Valley_Large] = mix(weights[piece.Valley_Large] or 1, 3, t)
	weights[piece.Uphill_Small] = mix(weights[piece.Uphill_Small] or 2, 3, t)
	weights[piece.Uphill_Large] = mix(weights[piece.Uphill_Large] or 1, 5, t)
	weights[piece.Drop] = mix(weights[piece.Drop] or 1, 4, t)
	weights[piece.JumpRamp] = mix(weights[piece.JumpRamp] or 2, 3, t)
	weights[piece.Flat_Transition] = mix(weights[piece.Flat_Transition] or 3, 2, t)
	weights[piece.DestructionZone] = mix(weights[piece.DestructionZone] or 1, 4, t)

	local function bump(name, perStep)
		grammar.MaxCount[name] = (grammar.MaxCount[name] or 0) + steps * perStep
	end
	bump(piece.DestructionZone, 1)
	bump(piece.Drop, 2)
	bump(piece.JumpRamp, 2)
	bump(piece.Valley_Large, 2)
	bump(piece.Uphill_Large, 2)
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
	if not mountain then
		settings.Enabled = false
		return settings
	end

	-- Every mountain place loads Storage.Props/<MountainId>. Named Frostpeak
	-- recipes are optional; category scatter still runs from whatever is in the library.
	settings.Enabled = true
	settings.LibraryName = mountainId
	if mountain.Props then
		settings.LibraryName = mountain.Props.LibraryName or mountainId
		for key, value in mountain.Props do
			settings[key] = value
		end
	end

	return settings
end

function config:GetBorderSettings(mountainId)
	local settings = table.clone(self.BORDERS)
	settings.LowTemplates = table.clone(self.BORDERS.LowTemplates)
	settings.TallTemplates = table.clone(self.BORDERS.TallTemplates)

	local theme = self.BorderThemes[mountainId]
	if theme then
		for key, value in theme do
			settings[key] = value
		end
	end

	local mountain = self.Mountains[mountainId]
	if not mountain then
		settings.Enabled = false
		return settings
	end

	if mountain.BuildBorders ~= nil then
		settings.Enabled = mountain.BuildBorders
	end
	if mountain.Borders then
		for key, value in mountain.Borders do
			settings[key] = value
		end
		if mountain.Borders.LowTemplates then
			settings.LowTemplates = table.clone(mountain.Borders.LowTemplates)
		end
		if mountain.Borders.TallTemplates then
			settings.TallTemplates = table.clone(mountain.Borders.TallTemplates)
		end
	end

	return settings
end

function config:GetGrammar(mountainId)
	local grammar = copyGrammar(self.DEFAULT_GRAMMAR)
	local mountain = self.Mountains[mountainId]
	self:ApplyDifficulty(grammar, mountain and mountain.Difficulty or 1)
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


--[[---------------------------------------DESCRIPTION------------------------------------------
	Explicit motion profiles for all 30 supplied launchers. The list index is
	the launcher id, matching SnowballLaunchers.Order (1 - 30).

	period      seconds for one charge loop cycle
	duration    seconds of the release / recovery animation
	fireAt      seconds into the release where the visual shot happens (OnFire)
	kick        recoil amplitude
	sway        charge loop amplitude
	base        pose in degrees per joint, in AnimationMath.Joints order:
	            UpperTorso, Head, RightUpperArm, RightLowerArm, RightHand,
	            LeftUpperArm, LeftLowerArm, LeftHand

--------------------------------------------------------------------------------------------]]--

local PROFILES = {
	{ id = 1, name = "01_Wooden_Shovel", family = "scoop", period = 1.5, duration = 0.62, fireAt = 0.1178, kick = 13, sway = 2.5,
		base = { { -5, -9, 0 }, { 4, 5, 0 }, { 46, 12, -14 }, { 26, 0, 0 }, { 5, 0, -8 }, { 37.75, -18, 20 }, { 45, 0, 0 }, { 0, 0, 10 } },
		description = "Small cupped wind-up and light wrist flick" },

	{ id = 2, name = "02_Snow_Scoop", family = "scoop", period = 1.6, duration = 0.66, fireAt = 0.1254, kick = 16, sway = 2.8,
		base = { { -5, -9, 0 }, { 4, 5, 0 }, { 48, 12, -14 }, { 26, 0, 0 }, { 5, 0, -8 }, { 39.25, -18, 20 }, { 45, 0, 0 }, { 0, 0, 10 } },
		description = "Deep scoop, soft breathing, rising toss" },

	{ id = 3, name = "03_Snowball_Flipper", family = "flipper", period = 1.25, duration = 0.48, fireAt = 0.0912, kick = 20, sway = 3.0,
		base = { { -4, -10, 0 }, { 3, 6, 0 }, { 60, 10, -12 }, { 24, 0, 0 }, { 3, 0, -8 }, { 36.75, -16, 20 }, { 42, 0, 0 }, { 0, 0, 8 } },
		description = "Quick paddle preparation and crisp flip" },

	{ id = 4, name = "04_Leather_Sling", family = "sling", period = 1.3, duration = 0.62, fireAt = 0.1178, kick = 24, sway = 3.3,
		base = { { -3, -15, -3 }, { 2, 10, 0 }, { 64, 20, -28 }, { 48, 0, 0 }, { 0, 12, -12 }, { 32.25, -20, 24 }, { 40, 0, 0 }, { 0, 0, 8 } },
		description = "Circular wrist gathering and sidearm release" },

	{ id = 5, name = "05_Wooden_Slingshot", family = "bow", period = 1.7, duration = 0.56, fireAt = 0.1064, kick = 15, sway = 1.8,
		base = { { -3, 16, 0 }, { 2, -10, 0 }, { 82, 23, -6 }, { 12, 0, 0 }, { 0, 0, -4 }, { 71.75, -48, 22 }, { 98, 0, 0 }, { 0, 0, 14 } },
		description = "Steady drawn hold and elastic hand follow-through" },

	{ id = 6, name = "06_Steel_Slingshot", family = "bow", period = 1.5, duration = 0.48, fireAt = 0.0912, kick = 12, sway = 1.3,
		base = { { -3, 16, 0 }, { 2, -10, 0 }, { 84, 23, -6 }, { 12, 0, 0 }, { 0, 0, -4 }, { 73.25, -48, 22 }, { 98, 0, 0 }, { 0, 0, 14 } },
		description = "Firm steel draw and fast controlled snap" },

	{ id = 7, name = "07_Spring_Scoop", family = "flipper", period = 1.05, duration = 0.5, fireAt = 0.095, kick = 24, sway = 3.2,
		base = { { -4, -10, 0 }, { 3, 6, 0 }, { 56, 10, -12 }, { 24, 0, 0 }, { 3, 0, -8 }, { 36.75, -16, 20 }, { 42, 0, 0 }, { 0, 0, 8 } },
		description = "Springy rocking hold and upward pop" },

	{ id = 8, name = "08_Snow_Crossbow", family = "crossbow", period = 1.75, duration = 0.54, fireAt = 0.1026, kick = 10, sway = 1.0,
		base = { { -5, -8, 0 }, { 3, 4, 0 }, { 68, 16, -10 }, { 38, 0, 0 }, { 0, 0, -5 }, { 71.25, -26, 17 }, { 28, 0, 0 }, { 0, 0, 10 } },
		description = "Two-hand brace and restrained kick" },

	{ id = 9, name = "09_Hand_Catapult", family = "catapult", period = 1.5, duration = 0.76, fireAt = 0.1444, kick = 28, sway = 2.2,
		base = { { -6, -10, 0 }, { 4, 7, 0 }, { 55, 18, -18 }, { 45, 0, 0 }, { 0, 0, -9 }, { 51.75, -26, 22 }, { 47, 0, 0 }, { 0, 0, 12 } },
		description = "Cocked cradled hold and forward arm throw" },

	{ id = 10, name = "10_Pump_Blaster", family = "blaster", period = 1.55, duration = 0.62, fireAt = 0.1178, kick = 13, sway = 1.4,
		base = { { -5, -10, 0 }, { 3, 6, 0 }, { 61, 15, -13 }, { 44, 0, 0 }, { 0, 0, -6 }, { 63.25, -24, 20 }, { 37, 0, 0 }, { 0, 0, 10 } },
		description = "Compact shoulder brace and pump-like recovery" },

	{ id = 11, name = "11_Twin_Snow_Blaster", family = "blaster", period = 1.4, duration = 0.64, fireAt = 0.1216, kick = 16, sway = 1.6,
		base = { { -5, -10, 0 }, { 3, 6, 0 }, { 63, 15, -13 }, { 44, 0, 0 }, { 0, 0, -6 }, { 64.75, -24, 20 }, { 37, 0, 0 }, { 0, 0, 10 } },
		description = "Wide two-hand hold and rolling double-weight recoil" },

	{ id = 12, name = "12_Snow_Revolver", family = "pistol", period = 1.45, duration = 0.51, fireAt = 0.0969, kick = 20, sway = 1.8,
		base = { { -3, -12, 0 }, { 2, 7, 0 }, { 86, 12, -6 }, { 10, 0, 0 }, { 0, 0, -4 }, { 34.25, -12, 14 }, { 48, 0, 0 }, { 0, 0, 5 } },
		description = "One-hand aim, wrist kick and small settle" },

	{ id = 13, name = "13_Pressure_Cannon", family = "heavy", period = 1.85, duration = 0.8, fireAt = 0.152, kick = 21, sway = 1.4,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 55, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 59.75, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Low heavy brace, pressure pulse and deep recoil" },

	{ id = 14, name = "14_Snowball_Gatling", family = "heavy", period = 1.05, duration = 0.7, fireAt = 0.133, kick = 12, sway = 1.2,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 57, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 61.25, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Tight oscillating brace with rotary-inspired shoulder motion" },

	{ id = 15, name = "15_Avalanche_Mortar", family = "mortar", period = 1.9, duration = 0.92, fireAt = 0.1748, kick = 29, sway = 1.7,
		base = { { -8, -8, 0 }, { 7, 4, 0 }, { 69, 17, -20 }, { 59, 0, 0 }, { 0, 0, -10 }, { 72.75, -28, 25 }, { 49, 0, 0 }, { 0, 0, 12 } },
		description = "Raised muzzle, deep stance and weighty upward release" },

	{ id = 16, name = "16_Frostbite_Cannon", family = "heavy", period = 1.8, duration = 0.7, fireAt = 0.133, kick = 16, sway = 1.0,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 55, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 64.25, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Cold precise hold with sharp frozen recoil" },

	{ id = 17, name = "17_Toxic_Lobber", family = "mortar", period = 1.7, duration = 0.8, fireAt = 0.152, kick = 22, sway = 2.0,
		base = { { -8, -8, 0 }, { 7, 4, 0 }, { 67, 17, -20 }, { 59, 0, 0 }, { 0, 0, -10 }, { 69.75, -28, 25 }, { 49, 0, 0 }, { 0, 0, 12 } },
		description = "Slow liquid sway and rounded lob" },

	{ id = 18, name = "18_Thunder_Coil", family = "energy", period = 1.1, duration = 0.52, fireAt = 0.0988, kick = 12, sway = 1.6,
		base = { { -4, -7, 0 }, { 3, 4, 0 }, { 70, 15, -12 }, { 38, 0, 0 }, { 0, 0, -5 }, { 66.25, -24, 18 }, { 33, 0, 0 }, { 0, 0, 10 } },
		description = "Tight periodic charge vibration and crisp discharge" },

	{ id = 19, name = "19_Lava_Lobber", family = "heavy", period = 1.65, duration = 0.82, fireAt = 0.1558, kick = 24, sway = 1.7,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 55, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 62.75, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Dense heavy charge and molten-weight recoil" },

	{ id = 20, name = "20_Blizzard_Launcher", family = "heavy", period = 1.25, duration = 0.7, fireAt = 0.133, kick = 17, sway = 2.3,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 57, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 64.25, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Swirling circular hold and sweeping release" },

	{ id = 21, name = "21_Golden_Ballista", family = "crossbow", period = 1.85, duration = 0.72, fireAt = 0.1368, kick = 20, sway = 1.2,
		base = { { -5, -8, 0 }, { 3, 4, 0 }, { 70, 16, -10 }, { 38, 0, 0 }, { 0, 0, -5 }, { 66.75, -26, 17 }, { 28, 0, 0 }, { 0, 0, 10 } },
		description = "Broad drawn brace and stately follow-through" },

	{ id = 22, name = "22_Royal_Cannon", family = "heavy", period = 1.9, duration = 0.82, fireAt = 0.1558, kick = 23, sway = 1.1,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 55, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 61.25, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Tall composed stance and authoritative kick" },

	{ id = 23, name = "23_Diamond_Railgun", family = "energy", period = 1.7, duration = 0.46, fireAt = 0.0874, kick = 9, sway = 0.65,
		base = { { -4, -7, 0 }, { 3, 4, 0 }, { 68, 15, -12 }, { 38, 0, 0 }, { 0, 0, -5 }, { 67.75, -24, 18 }, { 33, 0, 0 }, { 0, 0, 10 } },
		description = "Very stable precision charge and needle-fast recoil" },

	{ id = 24, name = "24_Dragon_Launcher", family = "heavy", period = 1.6, duration = 0.84, fireAt = 0.1596, kick = 26, sway = 2.1,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 59, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 64.25, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Breathing charge, head-like lift and powerful recoil" },

	{ id = 25, name = "25_Aurora_Prism", family = "energy", period = 1.9, duration = 0.65, fireAt = 0.1235, kick = 13, sway = 1.8,
		base = { { -4, -7, 0 }, { 3, 4, 0 }, { 66, 15, -12 }, { 38, 0, 0 }, { 0, 0, -5 }, { 64.75, -24, 18 }, { 33, 0, 0 }, { 0, 0, 10 } },
		description = "Flowing figure-eight hand drift and smooth discharge" },

	{ id = 26, name = "26_Meteor_Launcher", family = "mortar", period = 1.75, duration = 0.9, fireAt = 0.171, kick = 30, sway = 1.8,
		base = { { -8, -8, 0 }, { 7, 4, 0 }, { 67, 17, -20 }, { 59, 0, 0 }, { 0, 0, -10 }, { 71.25, -28, 25 }, { 49, 0, 0 }, { 0, 0, 12 } },
		description = "Gathered heavy hold and rising meteor lob" },

	{ id = 27, name = "27_Orbital_Cannon", family = "heavy", period = 2.0, duration = 0.9, fireAt = 0.171, kick = 27, sway = 1.2,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 59, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 62.75, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Slow orbital sway and large controlled release" },

	{ id = 28, name = "28_Nebula_Accelerator", family = "energy", period = 1.8, duration = 0.72, fireAt = 0.1368, kick = 18, sway = 1.6,
		base = { { -4, -7, 0 }, { 3, 4, 0 }, { 66, 15, -12 }, { 38, 0, 0 }, { 0, 0, -5 }, { 69.25, -24, 18 }, { 33, 0, 0 }, { 0, 0, 10 } },
		description = "Suspended spiral drift and accelerating follow-through" },

	{ id = 29, name = "29_Singularity_Cannon", family = "heavy", period = 2.1, duration = 1.02, fireAt = 0.1938, kick = 32, sway = 0.85,
		base = { { -7, -10, 0 }, { 4, 6, 0 }, { 57, 17, -20 }, { 53, 0, 0 }, { 0, 0, -9 }, { 59.75, -29, 25 }, { 44, 0, 0 }, { 0, 0, 12 } },
		description = "Inward bracing tension and powerful release" },

	{ id = 30, name = "30_Galactic_Rocket_Launcher", family = "rocket", period = 1.85, duration = 0.94, fireAt = 0.1786, kick = 28, sway = 1.4,
		base = { { -6, -14, 0 }, { 3, 8, 0 }, { 77, 18, -24 }, { 67, 0, 0 }, { 0, 0, -9 }, { 81.25, -25, 24 }, { 43, 0, 0 }, { 0, 0, 12 } },
		description = "Shouldered heavy hold and backward rocket recoil" },
}

-- The release plays on the pad camera until the ball leaves at fireAt, then the
-- chase camera takes over. The authored durations were a 0.5-1 s flick; stretch
-- them so the swing and the recoil can be seen. fireAt keeps its fraction.
local RELEASE_TIME_SCALE = 2.0

for _, profile in ipairs(PROFILES) do
	profile.duration *= RELEASE_TIME_SCALE
	profile.fireAt *= RELEASE_TIME_SCALE
end

return PROFILES

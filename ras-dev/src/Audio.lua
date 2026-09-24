--[[---------------------------------------DESCRIPTION------------------------------------------
	Every sound the client plays goes through here, so the game sounds like one thing:
	  * the catalog is MountainConfig.SOUNDS.Library: one entry per sound (asset id, base
	    volume, mix group, pitch spread, rate limit, roll-off). MountainConfig.MUSIC lists
	    the music loops, MountainConfig.AUDIO the group levels.
	  * four SoundGroups under SoundService carry the mix: Music, SFX, UI, Ambience. The
	    player attributes MusicEnabled / SFXEnabled = false silence a side (settings later).
	  * music is a state: "Lobby" on the pad, "Ride" while a ball rolls; changes crossfade
	    (MUSIC.Crossfade) and big moments duck it (Duck). Ambience is a wind bed that never
	    stops.
	Called from ClientMain (Start), the HUD / Notify / PurchaseFX UI modules, CLIENT_Snowball,
	CLIENT_SnowballFX (ride loops on each ball's FX rig), ChargeController (charge loop and
	throw, so other players hear them in 3D at the thrower) and LaunchPropAnimations.

	Audio.Start(vars)
	Audio.Play(name, opts)                      2D one-shot (UI, stingers). opts = { Volume, Pitch }
	Audio.PlayAt(name, partOrPosition, opts)    3D one-shot on a part (or a temporary point)
	Audio.Attach(part, name, opts) -> Sound     a Sound on a part you drive yourself (loops);
	                                            attribute BaseVolume = the catalog volume
	Audio.Release(sound, seconds)               fade a Sound out and destroy it
	Audio.Loop(key, name, opts) / Audio.SetLoop(key, volume, pitch) / Audio.StopLoop(key, seconds)
	Audio.SetMusic(state)                       "Lobby" | "Ride" | nil
	Audio.Duck(seconds, level)                  music dips to level, eases back
	Audio.ThrowSoundFor(launcherId) -> name     the launcher family's throw sound

--------------------------------------------------------------------------------------------]]--

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()
local Profiles = require(ReplicatedStorage.Assets.SnowballAnimations.Profiles)

local Audio = {}

local GROUP_NAMES = { "Music", "SFX", "UI", "Ambience" }
local THROW_BY_FAMILY = {
	scoop = "ThrowSwing",
	flipper = "ThrowSwing",
	catapult = "ThrowSwing",
	sling = "ThrowSwing",
	bow = "ThrowSlingshot",
	crossbow = "ThrowCrossbow",
	blaster = "ThrowBlaster",
	pistol = "ThrowBlaster",
	heavy = "ThrowCannon",
	mortar = "ThrowMortar",
	energy = "ThrowEnergy",
	rocket = "ThrowRocket",
}

local groups = {}
local templates = {}
local lastPlayed = {}
local loops = {}
local music = { State = nil, Sound = nil, Fading = {} }
local duck = { Until = 0, Level = 1 }
local started = false
local familyById = nil
local hostFolder = nil

local function library()
	local sounds = mountainConfig.SOUNDS
	return sounds and sounds.Library or {}
end

local function settings()
	return mountainConfig.AUDIO or {}
end

local function sfxEnabled()
	local player = Players.LocalPlayer
	return not (player and player:GetAttribute("SFXEnabled") == false)
end

local function musicEnabled()
	local player = Players.LocalPlayer
	return not (player and player:GetAttribute("MusicEnabled") == false)
end

local function assetId(id)
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end
	return tostring(id or "")
end

local function ensureGroups()
	local levels = settings().Groups or {}
	for _, name in GROUP_NAMES do
		local group = groups[name] or SoundService:FindFirstChild(name)
		if not (group and group:IsA("SoundGroup")) then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Parent = SoundService
		end
		group.Volume = levels[name] or 1
		groups[name] = group
	end
end

local function groupFor(entry)
	if not groups.SFX then
		ensureGroups()
	end
	return groups[entry.Group or "SFX"] or groups.SFX
end

local function entryFor(name)
	local entry = library()[name]
	if entry then
		return entry
	end
	-- the flat legacy keys (Whoosh, Thud, ...) still work
	local sounds = mountainConfig.SOUNDS
	local id = sounds and sounds[name]
	if type(id) == "string" then
		local volume = sounds.Volume and sounds.Volume[name] or 1
		return { Id = id, Volume = volume, Group = "SFX" }
	end
	return nil
end

local function template(name)
	local sound = templates[name]
	if sound then
		return sound
	end
	local entry = entryFor(name)
	if not entry then
		warn("[CLIENT]: Audio: no sound named", name)
		return nil
	end
	sound = Instance.new("Sound")
	sound.Name = "Audio_" .. name
	sound.SoundId = assetId(entry.Id)
	templates[name] = sound
	return sound
end

local function hostPoint(position)
	if not hostFolder or not hostFolder.Parent then
		hostFolder = Instance.new("Folder")
		hostFolder.Name = "AudioPoints"
		hostFolder.Parent = workspace
	end
	local host = Instance.new("Part")
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(position)
	host.Parent = hostFolder
	return host
end

local function configure(sound, entry, opts, spatial)
	opts = opts or {}
	sound.Volume = (entry.Volume or 0.5) * (opts.Volume or 1)
	local pitch = (entry.Pitch or 1) * (opts.Pitch or 1)
	local spread = if opts.PitchSpread ~= nil then opts.PitchSpread else (entry.PitchSpread or 0)
	if spread > 0 then
		pitch *= 1 + (math.random() * 2 - 1) * spread
	end
	sound.PlaybackSpeed = pitch
	sound.Looped = opts.Looped == true or entry.Looped == true
	sound.SoundGroup = groupFor(entry)
	if spatial then
		local roll = entry.RollOff or { 25, 260 }
		sound.RollOffMinDistance = roll[1] or 25
		sound.RollOffMaxDistance = roll[2] or 260
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
	end
	-- the catalog base, so a loop attached at Volume 0 still knows how loud it may get
	sound:SetAttribute("BaseVolume", entry.Volume or 0.5)
	return sound
end

local function rateLimited(name, entry)
	local now = os.clock()
	local gap = entry.MinInterval or 0.03
	if lastPlayed[name] and now - lastPlayed[name] < gap then
		return true
	end
	lastPlayed[name] = now
	return false
end

local function autoClean(sound, seconds)
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	task.delay(seconds or 15, function()
		if sound.Parent and not sound.Looped then
			sound:Destroy()
		end
	end)
end

----------------------------------------------------------------------------------------------
-- One-shots
----------------------------------------------------------------------------------------------

function Audio.Play(name, opts)
	if not sfxEnabled() then
		return nil
	end
	local entry = entryFor(name)
	local base = entry and template(name)
	if not base or rateLimited(name, entry) then
		return nil
	end
	local sound = configure(base:Clone(), entry, opts, false)
	sound.Parent = SoundService
	autoClean(sound)
	sound:Play()
	return sound
end

function Audio.PlayAt(name, target, opts)
	if not sfxEnabled() then
		return nil
	end
	local entry = entryFor(name)
	local base = entry and template(name)
	if not base or rateLimited(name, entry) then
		return nil
	end
	local host, temporary
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		host = target
	elseif typeof(target) == "Vector3" then
		host = hostPoint(target)
		temporary = host
	elseif typeof(target) == "Instance" and target:IsA("Model") then
		host = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host then
		return Audio.Play(name, opts)
	end
	local sound = configure(base:Clone(), entry, opts, true)
	sound.Parent = host
	autoClean(sound)
	if temporary then
		task.delay(math.max((sound.TimeLength > 0 and sound.TimeLength or 4) / math.max(sound.PlaybackSpeed, 0.1) + 0.5, 4), function()
			if temporary.Parent then
				temporary:Destroy()
			end
		end)
	end
	sound:Play()
	return sound
end

-- A Sound on a part that the caller drives (volume / pitch) and owns. Loops start playing.
function Audio.Attach(part, name, opts)
	local entry = entryFor(name)
	local base = entry and template(name)
	if not base or not part then
		return nil
	end
	local sound = configure(base:Clone(), entry, opts, true)
	sound.Parent = part
	if sound.Looped then
		if not sfxEnabled() then
			sound.Volume = 0
		end
		sound:Play()
	end
	return sound
end

function Audio.Release(sound, seconds)
	if not (sound and sound.Parent) then
		return
	end
	seconds = seconds or 0.2
	if seconds <= 0 or sound.Volume <= 0 then
		sound:Destroy()
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = 0 })
	tween.Completed:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	tween:Play()
end

----------------------------------------------------------------------------------------------
-- Named loops (2D beds: ambience)
----------------------------------------------------------------------------------------------

function Audio.Loop(key, name, opts)
	Audio.StopLoop(key, 0)
	local entry = entryFor(name)
	local base = entry and template(name)
	if not base then
		return nil
	end
	local sound = configure(base:Clone(), entry, opts, false)
	sound.Looped = true
	sound.Parent = SoundService
	local target = sound.Volume
	sound.Volume = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(if opts and opts.FadeIn then opts.FadeIn else 1.5), { Volume = target }):Play()
	loops[key] = sound
	return sound
end

function Audio.SetLoop(key, volume, pitch)
	local sound = loops[key]
	if not (sound and sound.Parent) then
		return
	end
	if volume then
		sound.Volume = (sound:GetAttribute("BaseVolume") or 1) * volume
	end
	if pitch then
		sound.PlaybackSpeed = pitch
	end
end

function Audio.StopLoop(key, seconds)
	local sound = loops[key]
	loops[key] = nil
	if sound then
		Audio.Release(sound, seconds or 1)
	end
end

----------------------------------------------------------------------------------------------
-- Music
----------------------------------------------------------------------------------------------

local function musicConfig()
	return mountainConfig.MUSIC or {}
end

local function musicLevel()
	local levels = settings().Groups or {}
	local level = (levels.Music or 1) * (if musicEnabled() then 1 else 0)
	return level * duck.Level
end

function Audio.SetMusic(state)
	local cfg = musicConfig()
	local entry = state and cfg[state] or nil
	if music.State == state then
		return
	end
	music.State = state
	local crossfade = math.max(cfg.Crossfade or 1.2, 0.05)

	local old = music.Sound
	music.Sound = nil
	if old then
		Audio.Release(old, crossfade)
	end
	if not entry then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. tostring(state)
	sound.SoundId = assetId(entry.Id)
	sound.Looped = entry.Looped ~= false
	sound.Volume = 0
	sound.SoundGroup = groups.Music
	sound:SetAttribute("BaseVolume", entry.Volume or 0.5)
	sound.Parent = SoundService
	music.Sound = sound
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(crossfade), { Volume = entry.Volume or 0.5 }):Play()
end

-- Music dips to `level` for `seconds`, then eases back (big stings, the finish).
function Audio.Duck(seconds, level)
	duck.Until = os.clock() + (seconds or 2)
	duck.Target = math.clamp(level or 0.35, 0, 1)
end

local function stepMix(dt)
	local target = if os.clock() < duck.Until then (duck.Target or 0.35) else 1
	duck.Level += (target - duck.Level) * (1 - math.exp(-(if target < duck.Level then 12 else 1.5) * dt))
	if groups.Music then
		groups.Music.Volume = musicLevel()
	end
	if groups.SFX then
		local levels = settings().Groups or {}
		local on = if sfxEnabled() then 1 else 0
		groups.SFX.Volume = (levels.SFX or 1) * on
		groups.UI.Volume = (levels.UI or 1) * on
		groups.Ambience.Volume = (levels.Ambience or 1) * on
	end
end

----------------------------------------------------------------------------------------------
-- Launchers
----------------------------------------------------------------------------------------------

function Audio.ThrowSoundFor(launcherId)
	if not familyById then
		familyById = {}
		for _, profile in ipairs(Profiles) do
			familyById[profile.id] = profile.family
		end
	end
	local family = familyById[tonumber(launcherId) or 0]
	return THROW_BY_FAMILY[family] or "ThrowSwing"
end

----------------------------------------------------------------------------------------------
-- Start
----------------------------------------------------------------------------------------------

function Audio.Start(_vars)
	if started or not RunService:IsClient() then
		return
	end
	started = true
	ensureGroups()

	if settings().Preload ~= false then
		task.spawn(function()
			local list = {}
			for name in pairs(library()) do
				local sound = template(name)
				if sound then
					table.insert(list, sound)
				end
			end
			for _, entry in pairs(musicConfig()) do
				if type(entry) == "table" and entry.Id then
					local sound = Instance.new("Sound")
					sound.SoundId = assetId(entry.Id)
					table.insert(list, sound)
				end
			end
			pcall(ContentProvider.PreloadAsync, ContentProvider, list)
		end)
	end

	local ambience = settings().Ambience
	if ambience and ambience.Sound then
		Audio.Loop("Ambience", ambience.Sound, { Volume = ambience.Volume or 1, FadeIn = 3 })
	end
	Audio.SetMusic(settings().StartMusic or "Lobby")

	RunService.Heartbeat:Connect(stepMix)
end

return Audio

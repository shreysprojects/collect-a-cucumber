--[[
	SoundController  (ModuleScript, ReplicatedStorage.Modules)
	Ported from the Zombie Cucumber Game (ControllerLoader.Custom.SoundController),
	made standalone: no ControllerLoader / SettingsController. The SFX gate is
	module.SetSFXEnabled(bool) or the LocalPlayer attribute SFXEnabled == false.

	Server:  SoundController.PlaySound(name, parent?, {Volume, Speed, Pitch, RollOff, RollOffMin, MaxLife})
	Client:  SoundController.PlayFX(name, opts)      -- opts: Volume, Speed, Pitch, Parent (3D),
	                                                 --   Key, MinInterval, MaxConcurrent, Variants, RollOff, RollOffMin, Looped, MaxLife
	         SoundController.PlayFXAt(name, position, opts)
	         SoundController.PlayerSoundClient(name)  -- legacy alias of PlayFX
	Templates live in ReplicatedStorage.Assets.Sounds (Sound objects; optional AuthoredVolume attribute).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

--..Variables..--
local Sounds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")
local rng = Random.new()

local module = {}

--.. per-name live counts + last-play stamps for throttling (client)
local ActiveCount = {}
local LastPlayed = {}
local DEFAULT_MAX_CONCURRENT = 3
local SFXEnabled = true

local function authoredVolume(template)
	local v = template:GetAttribute("AuthoredVolume")
	if v == nil then v = template.Volume end
	return v
end

local function sfxAllowed()
	if not SFXEnabled then return false end
	local player = Players.LocalPlayer
	if player and player:GetAttribute("SFXEnabled") == false then return false end
	return true
end

function module.SetSFXEnabled(enabled)
	SFXEnabled = enabled ~= false
end

--.. Plays The Sound # Server Use Only
--.. Non-blocking; world one-shots always get a rolloff cap
--.. (an uncapped Sound defaults to 10,000 studs = server-wide).
--.. Options: Volume, Speed, Pitch (± jitter fraction), RollOff, RollOffMin, MaxLife
function module.PlaySound(SoundName, Parent, Options)
	Options = Options or {}
	local template = Sounds:FindFirstChild(SoundName)
	if not template then return end
	local Sound = template:Clone()
	Sound.Volume = Options.Volume or authoredVolume(template)
	Sound.PlaybackSpeed = Options.Speed or 1
	if Options.Pitch then
		Sound.PlaybackSpeed = Sound.PlaybackSpeed * (1 + rng:NextNumber(-Options.Pitch, Options.Pitch))
	end
	Sound.RollOffMinDistance = Options.RollOffMin or 8
	Sound.RollOffMaxDistance = Options.RollOff or 60
	Sound.Parent = Parent or SoundService
	Sound:Play()
	Sound.Ended:Once(function() Sound:Destroy() end)
	Debris:AddItem(Sound, Options.MaxLife or 10)
	return Sound
end

--.. The client one-shot # Client Use Only. SFX-gated, pooled-count capped.
--.. opts: Volume, Speed, Pitch (± jitter fraction), Parent (BasePart/Attachment = 3D),
--..       Key (throttle key, default = sound name), MinInterval (sec), MaxConcurrent,
--..       Variants ({names} -> random pick), RollOff/RollOffMin, Looped (caller
--..       owns stop/destroy of the returned Sound), MaxLife
function module.PlayFX(SoundName, opts)
	opts = opts or {}
	if not sfxAllowed() then return end
	if opts.Variants then
		SoundName = opts.Variants[rng:NextInteger(1, #opts.Variants)]
	end
	local template = Sounds:FindFirstChild(SoundName)
	if not template then return end

	local key = opts.Key or SoundName
	local now = os.clock()
	if opts.MinInterval and LastPlayed[key] and now - LastPlayed[key] < opts.MinInterval then
		return
	end
	local cap = opts.MaxConcurrent or DEFAULT_MAX_CONCURRENT
	if (ActiveCount[SoundName] or 0) >= cap then return end
	LastPlayed[key] = now
	ActiveCount[SoundName] = (ActiveCount[SoundName] or 0) + 1

	local Sound = template:Clone()
	Sound.Volume = opts.Volume or authoredVolume(template)
	Sound.PlaybackSpeed = opts.Speed or 1
	if opts.Pitch then
		Sound.PlaybackSpeed = Sound.PlaybackSpeed * (1 + rng:NextNumber(-opts.Pitch, opts.Pitch))
	end
	if opts.Looped then Sound.Looped = true end
	if opts.Parent then
		Sound.RollOffMinDistance = opts.RollOffMin or 8
		Sound.RollOffMaxDistance = opts.RollOff or 60
		Sound.Parent = opts.Parent
	else
		Sound.Parent = SoundService
	end

	local done = false
	local function finish()
		if done then return end
		done = true
		ActiveCount[SoundName] = math.max(0, (ActiveCount[SoundName] or 1) - 1)
	end
	Sound.Ended:Once(function()
		finish()
		if not opts.Looped then Sound:Destroy() end
	end)
	Sound.Destroying:Once(finish)
	if not opts.Looped then
		task.delay(opts.MaxLife or 10, function()
			finish()
			if Sound.Parent then Sound:Destroy() end
		end)
	end
	Sound:Play()
	return Sound
end

--.. 3D one-shot at a world POSITION (no part needed) # Client Use Only
function module.PlayFXAt(SoundName, position, opts)
	opts = opts or {}
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	opts.Parent = att
	local Sound = module.PlayFX(SoundName, opts)
	if Sound then
		Debris:AddItem(att, (opts.MaxLife or 10) + 1)
	else
		att:Destroy()
	end
	return Sound
end

--.. Legacy client entry point # Client Use Only
function module.PlayerSoundClient(SoundName)
	module.PlayFX(SoundName)
end

function module.Initialize()
end

return module

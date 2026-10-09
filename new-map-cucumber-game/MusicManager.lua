--.. MusicManager -- central music registry (ported verbatim from the Zombie Cucumber Game).
--.. Client-side use only. Gives every registered music track: the "Mute"
--.. toggle, fade in/out instead of hard cuts, and tag-based ducking for
--.. events/setpieces. The lobby track is SoundService."Background Music".
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local module = {}

local Registered = {}  -- Sound -> {authored = number}
local Ducks = {}       -- tag -> factor 0..1 (lowest active factor wins)
local Muted = false
local Tweens = {}      -- Sound -> Tween
local Gen = {}         -- Sound -> op generation (cancels stale delayed pause/stop)

local function duckFactor()
	local f = 1
	for _, v in pairs(Ducks) do
		if v < f then f = v end
	end
	return f
end

local function targetVolume(sound)
	if Muted then return 0 end
	local rec = Registered[sound]
	local base = rec and rec.authored or sound.Volume
	return base * duckFactor()
end

local function bump(sound)
	Gen[sound] = (Gen[sound] or 0) + 1
	return Gen[sound]
end

local function fadeTo(sound, vol, fadeTime)
	local old = Tweens[sound]
	if old then old:Cancel() end
	if not fadeTime or fadeTime <= 0 then
		sound.Volume = vol
		return
	end
	local tw = TweenService:Create(sound, TweenInfo.new(fadeTime, Enum.EasingStyle.Linear), {Volume = vol})
	Tweens[sound] = tw
	tw:Play()
end

local function refresh(fadeTime)
	for sound in pairs(Registered) do
		if sound.Parent and sound.Playing then
			fadeTo(sound, targetVolume(sound), fadeTime)
		end
	end
end

--.. Register a music Sound so Mute + ducking govern it. authoredVolume
--.. defaults to the sound's Volume at registration time.
function module.Register(sound, authoredVolume)
	if not sound then return end
	if Registered[sound] then return sound end
	Registered[sound] = {authored = authoredVolume or sound.Volume}
	sound.Destroying:Once(function()
		Registered[sound] = nil
		Tweens[sound] = nil
		Gen[sound] = nil
	end)
	if Muted and sound.Playing then sound.Volume = 0 end
	return sound
end

function module.Play(sound, fadeTime)
	if not sound then return end
	module.Register(sound)
	bump(sound)
	if fadeTime and fadeTime > 0 then
		sound.Volume = 0
		sound:Play()
		fadeTo(sound, targetVolume(sound), fadeTime)
	else
		sound.Volume = targetVolume(sound)
		sound:Play()
	end
end

function module.Resume(sound, fadeTime)
	if not sound then return end
	module.Register(sound)
	bump(sound)
	if fadeTime and fadeTime > 0 then
		sound.Volume = 0
		sound:Resume()
		fadeTo(sound, targetVolume(sound), fadeTime)
	else
		sound.Volume = targetVolume(sound)
		sound:Resume()
	end
end

local function fadeThen(sound, fadeTime, action)
	local g = bump(sound)
	if not fadeTime or fadeTime <= 0 then
		action()
		return
	end
	fadeTo(sound, 0, fadeTime)
	task.delay(fadeTime, function()
		if Gen[sound] == g then action() end
	end)
end

function module.Pause(sound, fadeTime)
	if not sound then return end
	module.Register(sound)
	fadeThen(sound, fadeTime, function() sound:Pause() end)
end

function module.Stop(sound, fadeTime)
	if not sound then return end
	module.Register(sound)
	fadeThen(sound, fadeTime, function() sound:Stop() end)
end

--.. Duck all music to `factor` (0..1) under `tag`; lowest active tag wins.
function module.SetDuck(tag, factor, fadeTime)
	Ducks[tag] = factor
	refresh(fadeTime or 0.5)
end

function module.ClearDuck(tag, fadeTime)
	Ducks[tag] = nil
	refresh(fadeTime or 0.5)
end

function module.IsMuted()
	return Muted
end

function module.SetMuted(muted)
	Muted = muted and true or false
	--.. instant-ish so the settings toggle feels responsive
	refresh(0.2)
	--.. legacy behavior: the lobby track also pauses/plays so a muted client
	--.. isn't silently streaming audio
	local bg = SoundService:FindFirstChild("Background Music")
	if bg then
		if Muted then
			bg:Pause()
		else
			bg:Resume()
			bg.Volume = targetVolume(bg)
		end
	end
end

--.. auto-register the lobby track
do
	local bg = SoundService:FindFirstChild("Background Music")
	if bg then module.Register(bg) end
end

return module

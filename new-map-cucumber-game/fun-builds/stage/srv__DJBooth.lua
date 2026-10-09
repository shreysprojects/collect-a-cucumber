--[[
	DJBooth  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the working DJ booth (fun-builds/CONTRACT.md, package DJBooth). Anyone may use it.
	  * "Play music" / "Stop music" prompt over the mixer (E / ButtonX): the ActionText flips with the music
	  * "Next track" prompt over the mixer (R / ButtonY, so both badges show at once), only while the music plays:
	    parented to the prompt anchor while playing and to nil while stopped (NOT Enabled = false - FunBuildClient's
	    build-mode hide / unhide flips Enabled locally and would bring a disabled prompt back). Its ObjectText names
	    the track that is on. It sits one prompt-height under the play prompt (UIOffset)
	  * the prompts live on an invisible helper part in the runtime folder, just above the mixer between the decks
	    (the prop is 11 merged meshes, none of them a sensible prompt spot)
	  * state (model attributes, replicated; ReplicatedStorage.FunBehavioursClient.DJBooth plays + draws it and the
	    DanceFloor client flashes along with it):
	      Fun_Playing    bool    the music is on
	      Fun_Track      number  index into FunAssets.Music (1-based)
	      Fun_StartedAt  number  Kit.Now() when the current track started - every client plays
	                             (Kit.Now() - StartedAt) % TimeLength, so everybody hears the same bar
	  * a short cooldown keeps people from strobing the music on and off
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)
local FunAssets = require(ReplicatedStorage.Modules.FunAssets)

--..Config..--
local PROMPT_SPOT = Vector3.new(0, 2.95, 0.45) -- authored: over the mixer, between the two decks (deck tops 2.90)
local PROMPT_DISTANCE = 11                     -- studs (the booth is ~10.5 wide at x1.3)
local TOGGLE_COOLDOWN = 0.75                   -- s between play / stop
local NEXT_COOLDOWN = 0.5                      -- s between track skips
local NEXT_PROMPT_DROP = 72                    -- px (the prompt layout is 66 px tall): "Next track" sits under the play prompt

local B = {}
B.Keys = {"DJBooth"}

--..Helpers..--
local function Tracks()
	return type(FunAssets.Music) == "table" and FunAssets.Music or {}
end

local function TrackCount()
	return math.max(1, #Tracks())
end

local function Wrap(index)
	return (math.floor(tonumber(index) or 1) - 1) % TrackCount() + 1
end

local function TrackLabel(index)
	local track = Tracks()[index]
	local name = type(track) == "table" and track.Name or nil
	return string.format("Track %d/%d  %s", index, TrackCount(), tostring(name or "No music"))
end

--..Behaviour..--
function B.Server(model, ctx)
	local anchor = ctx:Part({
		Name = "DJBoothPrompts",
		Size = Vector3.new(0.4, 0.4, 0.4),
		Transparency = 1,
		CFrame = CFrame.new(Kit.ToWorld(model, PROMPT_SPOT)) * Kit.Origin(model).Rotation,
	})

	ctx:SetState("Playing", false)
	ctx:SetState("Track", 1)

	local lastToggle, lastNext = 0, 0

	--..Prompts..--
	local toggle = ctx:Prompt(anchor, {
		Name = "DJPlayPrompt",
		Action = "Play music",
		Object = "DJ Booth",
		Distance = PROMPT_DISTANCE,
	})
	local nextTrack = ctx:Prompt(anchor, {
		Name = "DJNextPrompt",
		Action = "Next track",
		Object = TrackLabel(1),
		Key = Enum.KeyCode.R,
		Gamepad = Enum.KeyCode.ButtonY,
		Distance = PROMPT_DISTANCE,
	})
	nextTrack.UIOffset = Vector2.new(0, NEXT_PROMPT_DROP)

	local function Sync()
		local playing = ctx:GetState("Playing") == true
		toggle.ActionText = playing and "Stop music" or "Play music"
		nextTrack.ObjectText = TrackLabel(Wrap(ctx:GetState("Track")))
		nextTrack.Parent = playing and anchor or nil
	end

	ctx:Connect(toggle.Triggered, function()
		local t = os.clock()
		if t - lastToggle < TOGGLE_COOLDOWN then return end
		lastToggle = t
		if ctx:GetState("Playing") == true then
			ctx:SetState("Playing", false)
		else
			--.. StartedAt before Playing: a client that sees Playing = true already has the new start time
			ctx:SetState("Track", Wrap(ctx:GetState("Track")))
			ctx:SetState("StartedAt", Kit.Now())
			ctx:SetState("Playing", true)
		end
		Sync()
	end)

	ctx:Connect(nextTrack.Triggered, function()
		if ctx:GetState("Playing") ~= true then return end
		local t = os.clock()
		if t - lastNext < NEXT_COOLDOWN then return end
		lastNext = t
		ctx:SetState("StartedAt", Kit.Now())
		ctx:SetState("Track", Wrap((tonumber(ctx:GetState("Track")) or 1) + 1))
		Sync()
	end)

	Sync() -- (both prompts are ctx:Add-ed, so the ctx destroys the next prompt even while it is parked at nil)
end

return B

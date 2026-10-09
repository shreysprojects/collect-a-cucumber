--[[
	TV  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the working TV (fun-builds/CONTRACT.md, package TV). Anyone may use it.
	  * "Turn on" / "Turn off" prompt on the Panel (E / ButtonX): the ActionText flips with the power
	  * "Next channel" prompt on the Panel (R / ButtonY, so both badges show at once), only while the set is on:
	    it is parented to the Panel while on and to nil while off (NOT Enabled = false - FunBuildClient's build
	    mode hide / unhide flips Enabled locally and would bring a disabled prompt back). Its ObjectText names the
	    channel that is on now. It sits one prompt-height under the power prompt (UIOffset)
	  * state (model attributes, replicated; the client half ReplicatedStorage.FunBehavioursClient.TV draws it):
	      Fun_On      bool
	      Fun_Channel index into FunAssets.TVChannels (1-based)
	      Fun_Since   Kit.Now() when the channel started (power on / channel change) - clients derive the slide
	                  index and the video position from it, so every client shows the same picture
	  * cooldowns keep people from strobing the power or spinning the channels faster than the animations
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Modules.FunBuildKit)
local FunAssets = require(ReplicatedStorage.Modules.FunAssets)

--..Config..--
local PROMPT_DISTANCE = 12         -- studs from the Panel centre (the screen is ~5 studs up at x1.45)
local POWER_COOLDOWN = 0.6         -- s between power toggles (the CRT animations take ~0.45 s)
local CHANNEL_COOLDOWN = 0.4       -- s between channel changes (the static burst is 0.35 s)
local CHANNEL_PROMPT_DROP = 72     -- px (the prompt layout is 66 px tall): the channel prompt sits under the power one
local PROMPT_PARTS = {"Panel", "ScreenSky"} -- first one found carries the prompts (else the Hitbox)

local B = {}
B.Keys = {"TV"}

--..Helpers..--
local function Channels()
	return type(FunAssets.TVChannels) == "table" and FunAssets.TVChannels or {}
end

local function ChannelCount()
	return math.max(1, #Channels())
end

local function ChannelLabel(index)
	local ch = Channels()[index]
	local name = type(ch) == "table" and ch.Name or nil
	return string.format("CH %d  %s", index, tostring(name or "No channel"))
end

--..Behaviour..--
function B.Server(model, ctx)
	local panel
	for _, name in ipairs(PROMPT_PARTS) do
		panel = Kit.Part(model, name)
		if panel then break end
	end
	panel = panel or Kit.Hitbox(model)
	if not panel then return end

	ctx:SetState("Channel", 1)
	ctx:SetState("Since", Kit.Now())
	ctx:SetState("On", false)

	local lastPower, lastChannel = -math.huge, -math.huge

	--..Prompts..--
	local power = ctx:Prompt(panel, {
		Name = "TVPowerPrompt",
		Action = "Turn on",
		Object = "TV",
		Distance = PROMPT_DISTANCE,
	})
	local channel = ctx:Prompt(panel, {
		Name = "TVChannelPrompt",
		Action = "Next channel",
		Object = ChannelLabel(1),
		Key = Enum.KeyCode.R,
		Gamepad = Enum.KeyCode.ButtonY,
		Distance = PROMPT_DISTANCE,
	})
	channel.UIOffset = Vector2.new(0, CHANNEL_PROMPT_DROP)

	local function Sync()
		local on = ctx:GetState("On") == true
		power.ActionText = on and "Turn off" or "Turn on"
		channel.ObjectText = ChannelLabel(tonumber(ctx:GetState("Channel")) or 1)
		channel.Parent = on and panel or nil
	end

	ctx:Connect(power.Triggered, function()
		local t = os.clock()
		if t - lastPower < POWER_COOLDOWN then return end
		lastPower = t
		local on = ctx:GetState("On") ~= true
		if on then ctx:SetState("Since", Kit.Now()) end -- the channel starts over from the first slide
		ctx:SetState("On", on)
		Sync()
	end)

	ctx:Connect(channel.Triggered, function()
		if ctx:GetState("On") ~= true then return end
		local t = os.clock()
		if t - lastChannel < CHANNEL_COOLDOWN then return end
		lastChannel = t
		local index = (tonumber(ctx:GetState("Channel")) or 1) % ChannelCount() + 1
		ctx:SetState("Since", Kit.Now())
		ctx:SetState("Channel", index)
		Sync()
	end)

	Sync() -- (both prompts are ctx:Add-ed, so the ctx destroys the channel prompt even while it is parked at nil)
end

return B

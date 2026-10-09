--[[
	BoostPadService  (Script, ServerScriptService)  2026-09-19
	User: "Make the boost pad functional - prompt "Speed up" on it and triggering prompt shakes screen
	with zap sound effect, makes u 2x faster for 15 seconds".
	  * Every placed Boost Pad (CollectionService tag PlacedBuild, BuildKey "BoostPad": placed, restored by
	    BaseSaveService, moved - the prompt rides the model) gets a Custom-style "Speed up" ProximityPrompt
	    on its TreadDeck; StarterPlayerScripts.CucumberPromptClient draws it like the game's other prompts.
	    It cannot be authored on the ServerStorage.Builds model: BuildService.MakeTemplate strips prompts.
	  * Triggering sets the player attribute SpeedBoostUntil = server time + BOOST_SECONDS. Pressing again
	    restarts the 15 s; it never stacks past 2x. StrengthProgressionServer doubles the walk while it is
	    ahead and drops back when it runs out; StarterPlayerScripts.BoostPadClient plays the zap and the
	    screen shake, and hides pad prompts while its player is in build mode.
	  * A Broken pad (BuildHealthService) does not boost: its prompt is off until the pad is mended.
	  * Anyone may use a pad (like the egg and cucumber prompts). The boost ends when the character is
	    removed (death / respawn / admin reset).
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BuildCatalog"))

local KEY = "BoostPad"
local PROMPT_NAME = "SpeedUpPrompt"
local PROMPT_TAG = "BoostPadPrompt" -- BoostPadClient finds the prompts by this
local ATTR = "SpeedBoostUntil"
local BOOST_SECONDS = 15
local PROMPT_DISTANCE = 12
local TRIGGER_COOLDOWN = 1 -- seconds per player: holding / mashing E does not replay the zap every frame

local LastTrigger = {} -- [player] = os.clock()

local function PromptPartOf(model)
	local deck = model:FindFirstChild("TreadDeck", true)
	if deck and deck:IsA("BasePart") then return deck end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function Attach(model)
	if not (model:IsA("Model") and model:GetAttribute("BuildKey") == KEY and model:IsDescendantOf(workspace)) then return end
	local part = PromptPartOf(model)
	if not part or part:FindFirstChild(PROMPT_NAME) then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ObjectText = "Boost Pad"
	prompt.ActionText = "Speed up"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("BaseDistance", PROMPT_DISTANCE)
	local function sync() prompt.Enabled = model:GetAttribute("Broken") ~= true end -- Mend sets Broken to nil
	sync()
	model:GetAttributeChangedSignal("Broken"):Connect(sync)
	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("Broken") == true or not model:IsDescendantOf(workspace) then return end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local now = os.clock()
		if LastTrigger[player] and now - LastTrigger[player] < TRIGGER_COOLDOWN then return end
		LastTrigger[player] = now
		--.. 2026-09-23 (items): never cut a running Speed Potion short - the longer of the two timers stays
		player:SetAttribute(ATTR, math.max(tonumber(player:GetAttribute(ATTR)) or 0, workspace:GetServerTimeNow() + BOOST_SECONDS))
	end)
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Parent = part
end

--.. placed / restored pads (the tag goes on before the model is parented, so look a frame later)
CollectionService:GetInstanceAddedSignal(BuildCatalog.PLACED_TAG):Connect(function(model)
	task.defer(Attach, model)
end)
for _, model in ipairs(CollectionService:GetTagged(BuildCatalog.PLACED_TAG)) do Attach(model) end

--.. the boost does not outlive the character
local function Watch(player)
	player.CharacterRemoving:Connect(function()
		--.. 2026-09-23 (items): only a pad boost ends with the character; a Speed Potion's longer timer survives a respawn
		local untilTime = tonumber(player:GetAttribute(ATTR))
		if not untilTime or untilTime - workspace:GetServerTimeNow() <= BOOST_SECONDS then player:SetAttribute(ATTR, nil) end
	end)
end
Players.PlayerAdded:Connect(Watch)
Players.PlayerRemoving:Connect(function(player) LastTrigger[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do Watch(player) end

print(("[BoostPadService] placed Boost Pads get a \"Speed up\" prompt: %dx walk speed for %d s"):format(2, BOOST_SECONDS))

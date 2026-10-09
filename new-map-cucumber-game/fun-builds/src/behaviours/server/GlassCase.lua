--[[
	GlassCase  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GlassCase
	Server half of the TROPHY CASE (GlassCase, x1.25). The client half (ReplicatedStorage.FunBehavioursClient.GlassCase)
	builds the trophy out of Parts, floats + spins it over Pivot_DisplayPoint and plays every effect.
	  * GlassPanes and LightBeam stop colliding while this runs (the author's note: a spawned item stands inside the
	    beam); their own CanCollide comes back on cleanup - unless the build is Broken, when BuildHealthService owns
	    every part's collisions (it recorded ours and puts them back when it mends)
	  * state Design (1-5, model attribute Fun_Design): 1 Golden Cucumber, 2 Royal Crown, 3 Gold Star,
	    4 Champion Cup, 5 Diamond. Remembered per placed build for the whole server session, so a move or a
	    break / mend (both re-run the behaviour) keeps the owner's pick
	  * prompt "Change trophy" (F / ButtonY, OWNER ONLY: refused here for anyone else and hidden on their clients
	    by the client half) steps to the next design; it sits one prompt-height under "Admire" (UIOffset)
	  * prompt "Admire" (E, everyone): ctx:Fire("Admire", {At = server time, By = UserId}) - every client runs the
	    shine sweep + sparkle burst + Sparkle sound from that moment; one admire per ADMIRE_COOLDOWN per case
	  * a brass nameplate (helper part in the runtime folder, in front of the plinth's TROPHY plate) carries a
	    SurfaceGui "<OwnerName>'s Trophy"; the name comes from Players:GetNameFromUserIdAsync (pcall, cached)
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local DESIGNS = {"Golden Cucumber", "Royal Crown", "Gold Star", "Champion Cup", "Diamond"} -- = the client's TrophySpecs order
local ADMIRE_COOLDOWN = 1.2    -- seconds between admires of one case (the shine lasts ~1 s)
local CHANGE_COOLDOWN = 0.35   -- seconds between design changes
local PROMPT_DISTANCE = 10
local ADMIRE_REACH = 18        -- studs from the hitbox centre a Triggered admire is honoured
local SECOND_PROMPT_DROP = 72  -- px: "Change trophy" sits one prompt-height under "Admire" (CucumberPromptClient reads UIOffset)
local NON_COLLIDE = {"GlassPanes", "LightBeam"}
--.. the nameplate, AUTHORED frame (x ctx.Scale): it covers the plinth's brass TROPHY plate (x -1.24..1.24,
--.. y 0.28..0.78, face at z -1.44) and the engraved letters standing 0.05 proud of it; its back sinks 0.01 into the plate
local PLATE_CENTRE = Vector3.new(0, 0.53, -1.48)
local PLATE_SIZE = Vector3.new(2.5, 0.52, 0.1)
local PLATE_COLOR = Color3.fromRGB(201, 162, 39) -- the case's brass (c9a227)
local INK = Color3.fromRGB(47, 54, 64)            -- the engraving's colour (2f3640)
local PLATE_PPS = 120                             -- SurfaceGui pixels per stud

--..Variables..--
local NameCache = {} -- [userId] = username
local Remembered = setmetatable({}, {__mode = "k"}) -- [model] = design index
local OriginalCollide = setmetatable({}, {__mode = "k"}) -- [part] = CanCollide before this behaviour first touched it

local B = {}
B.Keys = {"GlassCase"}
B.ActionRange = 30

--..Helpers..--
local function OwnerName(userId)
	userId = tonumber(userId)
	if not userId or userId <= 0 then return nil end
	if NameCache[userId] then return NameCache[userId] end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.Name
	if not name then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		if ok and type(result) == "string" and result ~= "" then name = result end
	end
	if name then NameCache[userId] = name end
	return name
end

--.. "Shrey" -> "Shrey's Trophy", "James" -> "James' Trophy"
local function TrophyTitle(name)
	if not name then return "Trophy" end
	local tail = name:sub(-1):lower() == "s" and "'" or "'s"
	return name .. tail .. " Trophy"
end

local function NextOf(design)
	return design % #DESIGNS + 1
end

--..Nameplate..--
local function MakeNameplate(model, ctx)
	local plate = ctx:Part({
		Name = "TrophyNameplate",
		Size = PLATE_SIZE * ctx.Scale,
		CFrame = Kit.CFrameToWorld(model, CFrame.new(PLATE_CENTRE)),
		Color = PLATE_COLOR,
		Material = Enum.Material.Metal,
		Reflectance = 0.05,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Nameplate"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PLATE_PPS
	gui.LightInfluence = 0.6
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	--.. an engraved border line just inside the plate's edge
	local border = Instance.new("Frame")
	border.Name = "Border"
	border.AnchorPoint = Vector2.new(0.5, 0.5)
	border.Position = UDim2.fromScale(0.5, 0.5)
	border.Size = UDim2.new(1, -12, 1, -12)
	border.BackgroundTransparency = 1
	border.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Transparency = 0.2
	stroke.Parent = border
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = border
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -32, 1, -20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = INK
	label.TextScaled = true
	label.Text = TrophyTitle(nil)
	label.Parent = gui
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 64
	cap.MinTextSize = 8
	cap.Parent = label
	gui.Parent = plate
	--.. the owner's name (a web call when they are not in the server) - never blocks Server()
	task.spawn(function()
		local name = OwnerName(Kit.OwnerId(model))
		if name and ctx:Alive() and label.Parent then label.Text = TrophyTitle(name) end
	end)
	return plate
end

--..Behaviour..--
function B.Server(model, ctx)
	--..Glass + beam: no collisions (restored on cleanup)..--
	local noCollide = {}
	for _, name in ipairs(NON_COLLIDE) do
		local part = Kit.Part(model, name)
		if part then
			if OriginalCollide[part] == nil then OriginalCollide[part] = part.CanCollide end
			part.CanCollide = false
			table.insert(noCollide, part)
		end
	end

	--..Design state..--
	local design = Remembered[model] or 1
	ctx:SetState("Design", design)

	--..Prompts (both on the plinth: CucumberPromptClient floats them at the player's torso height)..--
	local base = Kit.Part(model, "Plinth") or Kit.Hitbox(model)
	local admire = ctx:Prompt(base, {
		Action = "Admire", Object = DESIGNS[design], Name = "AdmirePrompt", Distance = PROMPT_DISTANCE,
	})
	local change = ctx:Prompt(base, {
		Action = "Change trophy", Object = "Next: " .. DESIGNS[NextOf(design)], Name = "ChangeTrophyPrompt",
		Distance = PROMPT_DISTANCE, Key = Enum.KeyCode.F, Gamepad = Enum.KeyCode.ButtonY,
	})
	change.UIOffset = Vector2.new(0, SECOND_PROMPT_DROP)

	local lastAdmire = -math.huge
	ctx:Connect(admire.Triggered, function(player)
		local now = os.clock()
		if now - lastAdmire < ADMIRE_COOLDOWN then return end
		if not ctx:Near(player, ADMIRE_REACH * math.max(1, ctx.Scale)) then return end
		lastAdmire = now
		ctx:Fire("Admire", {At = Kit.Now(), By = player.UserId})
	end)

	local lastChange = -math.huge
	ctx:Connect(change.Triggered, function(player)
		if not ctx:IsOwner(player) then return end
		local now = os.clock()
		if now - lastChange < CHANGE_COOLDOWN then return end
		lastChange = now
		design = NextOf(design)
		Remembered[model] = design
		ctx:SetState("Design", design)
		admire.ObjectText = DESIGNS[design]
		change.ObjectText = "Next: " .. DESIGNS[NextOf(design)]
	end)

	--..Nameplate..--
	MakeNameplate(model, ctx)

	return function()
		--.. while Broken, BuildHealthService owns every part's CanCollide (it puts back what it recorded when it mends)
		if Kit.IsBroken(model) or not model.Parent then return end
		for _, part in ipairs(noCollide) do
			if part.Parent and OriginalCollide[part] ~= nil then part.CanCollide = OriginalCollide[part] end
		end
	end
end

return B

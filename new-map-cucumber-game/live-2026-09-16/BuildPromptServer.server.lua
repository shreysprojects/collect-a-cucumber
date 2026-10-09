--[[
	BuildPromptServer  (Script, ServerScriptService)  2026-09-11
	A "Build" ProximityPrompt floats ABOVE every plot's Upgrade Plot board (the per-plot copies
	PlotUpgradeService stands beside each plot: tag PlotUpgradeBoard, attribute Plot). Triggering it as
	the plot's owner:
	  * not in build mode -> the character is stood INSIDE the base (INSET studs in from the front edge,
	    facing in) and that client gets Remotes.BuildModeEnter {Kind = "Enter"} (BuildBarrierClient
	    waits for the HUD's BaseMode and fires the BuildMenu "enter" hook);
	  * already in build mode -> {Kind = "Leave"}: the same prompt is the way OUT (the client shows it
	    as "Leave build mode"); nothing is moved.
	The client reports its build state through the same remote (FireServer(true | false)), kept in
	Building[player]. Anyone else's trigger gets {Kind = "Refused", Reason = "That's not your base"};
	at night (workspace.CyclePhase == "Night") entering is refused too: "You can't build at night"
	(user 2026-09-12; leaving still works, and BuildMenuClient exits by itself when night falls).
	The prompt is Style Custom, so CucumberPromptClient draws it in the game's look; BuildBarrierClient
	enables it locally only on the player's own board. Prompts are tagged BuildPrompt, attribute Plot.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--..Config..--
local BOARD_TAG = "PlotUpgradeBoard"
local PROMPT_TAG = "BuildPrompt"
local ABOVE = 1.4  -- studs above the board's top edge
local INSET = 10   -- studs in from the front edge where the player lands
local REACH = 12   -- prompt distance
local FRONT = Vector3.new(-1, 0, 0) -- = PlotService.FRONT_DIRECTION

--..Instances..--
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Enter = Remotes:FindFirstChild("BuildModeEnter")
if not Enter then
	Enter = Instance.new("RemoteEvent")
	Enter.Name = "BuildModeEnter"
	Enter.Parent = Remotes
end

--..State..--
local Building = {} -- [player] = true while that client says it is in build mode
Enter.OnServerEvent:Connect(function(player, on)
	Building[player] = on == true or nil
end)
Players.PlayerRemoving:Connect(function(player) Building[player] = nil end)

--..Geometry..--
local function halfAlong(part, direction)
	local cf, size = part.CFrame, part.Size
	return math.abs(direction:Dot(cf.RightVector)) * size.X * 0.5
		+ math.abs(direction:Dot(cf.UpVector)) * size.Y * 0.5
		+ math.abs(direction:Dot(cf.LookVector)) * size.Z * 0.5
end

local function InsidePoint(plot)
	local frontX = plot.Position.X + FRONT.X * halfAlong(plot, FRONT)
	return Vector3.new(frontX + INSET, plot.Position.Y + plot.Size.Y * 0.5 + 3, plot.Position.Z)
end

local function PlotFor(board)
	local name = board:GetAttribute("Plot")
	return name and Plots:FindFirstChild(name) or nil
end

--..Trigger..--
local function OnTriggered(player, board)
	local plot = PlotFor(board)
	if not plot then return end
	if plot:GetAttribute("Owner") ~= player.UserId then
		Enter:FireClient(player, {Kind = "Refused", Reason = "That's not your base"})
		return
	end
	if Building[player] then
		Enter:FireClient(player, {Kind = "Leave", Plot = plot.Name})
		return
	end
	if workspace:GetAttribute("CyclePhase") == "Night" then
		Enter:FireClient(player, {Kind = "Refused", Reason = "You can't build at night"})
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 then return end
	humanoid.Sit = false
	local seat = humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then weld:Destroy() end
	local pos = InsidePoint(plot)
	character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)))
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	Enter:FireClient(player, {Kind = "Enter", Plot = plot.Name})
end

--..Prompts..--
local function AddPrompt(board)
	if not board:IsA("Model") then return end
	local panel = board:FindFirstChild("Panel") or board.PrimaryPart or board:FindFirstChildWhichIsA("BasePart")
	if not panel or panel:FindFirstChild("BuildPromptAnchor") then return end
	local anchor = Instance.new("Attachment")
	anchor.Name = "BuildPromptAnchor"
	anchor.Position = Vector3.new(0, panel.Size.Y * 0.5 + ABOVE, 0) -- the panel stands upright
	anchor.Parent = panel
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuildPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ObjectText = "Your base"
	prompt.ActionText = "Build"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = REACH
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("Plot", board:GetAttribute("Plot"))
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(OnTriggered, player, board)
		if not ok then warn("[BuildPrompt] " .. tostring(err)) end
	end)
	prompt.Parent = anchor
end

for _, board in ipairs(CollectionService:GetTagged(BOARD_TAG)) do AddPrompt(board) end
CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(function(board) task.defer(AddPrompt, board) end)
print(("[BuildPrompt] build prompts on %d plot boards (tag %s)"):format(#CollectionService:GetTagged(PROMPT_TAG), BOARD_TAG))

--[[
	BuildBarrierClient  (LocalScript, StarterPlayerScripts)  2026-09-11
	The client half of the board prompt and the build-mode fence:
	  1. Remotes.BuildModeEnter {Kind = "Enter"} (BuildPromptServer, right after it stood the character
	     inside the base): waits up to BASE_WAIT for the HUD attribute BaseMode to read true
	     (BaseHUDController, Heartbeat) and opens build mode through the BuildMenu's BuildDev hook
	     ("enter"). {Kind = "Leave"}: closes it ("exit"). {Kind = "Refused", Reason} -> Notify.
	  2. The client reports its build state to the server (FireServer(true | false) on the HUD's
	     BuildMode attribute) so the same prompt becomes the way out, and relabels its own board's
	     prompt locally: "Build" outside build mode, "Leave build mode" inside it.
	  3. While BuildMode is true, four faint walls (WALL_HEIGHT tall, Transparency 0.8, client-only,
	     collidable, CanQuery off so placement rays and the camera ignore them) ring the player's plot so
	     they cannot walk out; they follow the plot when it resizes and go when build mode ends. No
	     confirmation dialog (user 2026-09-11) - leave through the prompt or the menu.
	  Also: every BuildPrompt (tag) is enabled locally only on the player's own plot's board.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--..Modules..--
local Notify = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Notify"))

--..Config..--
local WALL_HEIGHT = 40
local WALL_THICK = 2
local WALL_MARGIN = 0.5 -- studs outside the plot edge
local WALL_TRANSPARENCY = 0.8
local WALL_COLOR = Color3.fromRGB(150, 255, 170)
local BASE_WAIT = 3     -- seconds to wait for BaseMode after the teleport
local TEXT_BUILD = "Build"
local TEXT_LEAVE = "Leave build mode"

--..Instances..--
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("CucumberHUDDesign")
local menu = playerGui:WaitForChild("BuildMenu")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Enter = Remotes:WaitForChild("BuildModeEnter")
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local function MyPlot()
	local name = player:GetAttribute("Plot")
	return name and Plots:FindFirstChild(name) or nil
end

local function InBuildMode()
	return hud:GetAttribute("BuildMode") == true
end

--..Prompts: only your own board offers it, and it says what it does..--
local function refreshPrompts()
	local mine = player:GetAttribute("Plot")
	local building = InBuildMode()
	for _, prompt in ipairs(CollectionService:GetTagged("BuildPrompt")) do
		if prompt:IsA("ProximityPrompt") then
			local own = prompt:GetAttribute("Plot") == mine
			prompt.Enabled = own
			if own then prompt.ActionText = building and TEXT_LEAVE or TEXT_BUILD end
		end
	end
end
CollectionService:GetInstanceAddedSignal("BuildPrompt"):Connect(function() task.defer(refreshPrompts) end)
player:GetAttributeChangedSignal("Plot"):Connect(refreshPrompts)

--..Barrier..--
local barrier
local function clearBarrier()
	if barrier then
		barrier:Destroy()
		barrier = nil
	end
end

local function buildBarrier(plot)
	clearBarrier()
	if not plot then return end
	barrier = Instance.new("Folder")
	barrier.Name = "BuildBarrier"
	local half = plot.Size * 0.5
	local out = WALL_MARGIN + WALL_THICK * 0.5
	local y = half.Y + WALL_HEIGHT * 0.5 - 2 -- from just under the plot top upward
	local alongZ = Vector3.new(WALL_THICK, WALL_HEIGHT, plot.Size.Z + 2 * (WALL_MARGIN + WALL_THICK))
	local alongX = Vector3.new(plot.Size.X + 2 * (WALL_MARGIN + WALL_THICK), WALL_HEIGHT, WALL_THICK)
	local specs = {
		{CFrame.new(half.X + out, y, 0), alongZ},
		{CFrame.new(-(half.X + out), y, 0), alongZ},
		{CFrame.new(0, y, half.Z + out), alongX},
		{CFrame.new(0, y, -(half.Z + out)), alongX},
	}
	for i, spec in ipairs(specs) do
		local wall = Instance.new("Part")
		wall.Name = "Wall" .. i
		wall.Size = spec[2]
		wall.CFrame = plot.CFrame * spec[1]
		wall.Anchored = true
		wall.Transparency = WALL_TRANSPARENCY
		wall.Color = WALL_COLOR
		wall.Material = Enum.Material.SmoothPlastic
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Parent = barrier
	end
	barrier.Parent = workspace
end

local plotConns = {}
local function onBuildMode()
	for _, c in ipairs(plotConns) do c:Disconnect() end
	table.clear(plotConns)
	local on = InBuildMode()
	Enter:FireServer(on) -- the server makes the board prompt the way out while this is true
	refreshPrompts()
	if on then
		local plot = MyPlot()
		if not plot then return end
		buildBarrier(plot)
		local pending = false
		local function rebuild()
			if pending then return end
			pending = true
			task.defer(function()
				pending = false
				if InBuildMode() then buildBarrier(plot) end
			end)
		end
		table.insert(plotConns, plot:GetPropertyChangedSignal("Size"):Connect(rebuild))
		table.insert(plotConns, plot:GetPropertyChangedSignal("CFrame"):Connect(rebuild))
	else
		clearBarrier()
	end
end
hud:GetAttributeChangedSignal("BuildMode"):Connect(onBuildMode)
onBuildMode()

--..Enter / leave from the board prompt..--
Enter.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.Kind == "Refused" then
		Notify.Error(payload.Reason or "That's not your base")
	elseif payload.Kind == "Leave" then
		if InBuildMode() then menu:SetAttribute("BuildDev", "exit") end
	elseif payload.Kind == "Enter" then
		if InBuildMode() then return end
		task.spawn(function()
			local t0 = os.clock()
			while hud:GetAttribute("BaseMode") ~= true and os.clock() - t0 < BASE_WAIT do task.wait(0.1) end
			if hud:GetAttribute("BaseMode") ~= true then
				Notify.Warn("Go to your base to build")
				return
			end
			menu:SetAttribute("BuildDev", "enter")
		end)
	end
end)

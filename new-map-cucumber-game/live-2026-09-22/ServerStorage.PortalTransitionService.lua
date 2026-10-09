local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local module = {}
local pending = {}
local transition

function module.Start(remotes)
	transition = Instance.new("RemoteEvent")
	transition.Name = "Transition"
	transition.Parent = remotes
	local ready = Instance.new("RemoteEvent")
	ready.Name = "TransitionReady"
	ready.Parent = remotes
	ready.OnServerEvent:Connect(function(player, token)
		local state = pending[player]
		if state and state.Token == token then state.Ready = true end
	end)
	Players.PlayerRemoving:Connect(function(player) pending[player] = nil end)
end

function module.Teleport(player, target, move)
	if pending[player] then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local state = {Token = HttpService:GenerateGUID(false), Ready = false}
	pending[player] = state
	player:SetAttribute("PortalTransitioning", true)
	local wasAnchored = root.Anchored
	root.Anchored = true
	transition:FireClient(player, "In", state.Token)
	local ok, moved = pcall(function()
		local deadline = os.clock() + 4
		while pending[player] == state and not state.Ready and os.clock() < deadline do RunService.Heartbeat:Wait() end
		if pending[player] ~= state or player.Parent ~= Players or player.Character ~= character or humanoid.Health <= 0 then return false end
		-- A missing client acknowledgment must not leave a player frozen.
		if not state.Ready then return false end
		pcall(function() player:RequestStreamAroundAsync(target.Position, 2) end)
		if player.Character ~= character or humanoid.Health <= 0 or player.Parent ~= Players then return false end
		local result = move(player, target)
		task.wait(0.12)
		return result
	end)
	if root.Parent then root.Anchored = wasAnchored end
	pending[player] = nil
	if player.Parent == Players then
		player:SetAttribute("PortalTransitioning", nil)
		transition:FireClient(player, "Out", state.Token)
	end
	if not ok then warn("[PortalTransition] " .. tostring(moved)) end
	return ok and moved == true
end

return module
--[[
	RewardSpinnerClient  (LocalScript, StarterPlayerScripts)  2026-09-23
	The client half of the portal reward spinner (port of the Zombie Cucumber Game's
	MinigameCompletionClient): Remotes.RewardSpinner {Kind = "Spin", Token, Selection} -> the confetti
	shower + win sting, then the SelectingReward reel (StarterGui.SelectingReward's Play BindableFunction,
	server-chosen winner) -> Remotes.RewardSpinnerFinished:FireServer(Token) so the server pays out;
	{Kind = "Granted", Text} -> a Notify toast + the cash-register sounds. Dev hook: none here (fire the
	server's RewardSpinnerDev attribute).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Notify = require(Modules:WaitForChild("Notify"))
local ButtonFX = require(Modules:WaitForChild("ButtonFX"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spinRemote = remotes:WaitForChild("RewardSpinner", 60)
local finishedRemote = remotes:WaitForChild("RewardSpinnerFinished", 60)
if not (spinRemote and finishedRemote) then
	warn("[RewardSpinnerClient] Remotes.RewardSpinner missing (RewardSpinnerServer not running?)")
	return
end

local COLORS = {
	Color3.new(1, 0.0666667, 0.0666667),
	Color3.new(0.921569, 1, 0.0627451),
	Color3.new(1, 0.219608, 0.921569),
	Color3.new(0.152941, 0.478431, 1),
	Color3.new(0.117647, 1, 0.411765),
}
local random = Random.new()
local queue = {}
local playing = false

local function confetti()
	local old = playerGui:FindFirstChild("RewardSpinnerConfetti")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RewardSpinnerConfetti"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 11000
	gui.Parent = playerGui
	task.delay(0.25, function()
		local sound = Instance.new("Sound")
		sound.Name = "RewardWinSound"
		sound.SoundId = "rbxassetid://7933571710"
		sound.Volume = 2
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 8)
	end)
	for _ = 1, 50 do
		if not gui.Parent then return end
		local x = random:NextNumber(0, 1)
		local particle = Instance.new("Frame")
		particle.Size = UDim2.fromOffset(20, 30)
		particle.Position = UDim2.fromScale(x, -0.2)
		particle.BorderSizePixel = 0
		particle.BackgroundColor3 = COLORS[random:NextInteger(1, #COLORS)]
		particle.Rotation = random:NextInteger(0, 90)
		particle.Parent = gui
		local tween = TweenService:Create(particle, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(x - random:NextNumber(-0.1, 0.1), 1),
			Rotation = random:NextInteger(-500, 500),
		})
		tween:Play()
		tween.Completed:Connect(function() particle:Destroy() end)
		task.wait(0.01)
	end
	task.wait(2)
	if gui.Parent then gui:Destroy() end
end

local function runSpin(payload)
	confetti()
	local reelGui = playerGui:FindFirstChild("SelectingReward") or playerGui:WaitForChild("SelectingReward", 10)
	local play = reelGui and (reelGui:FindFirstChild("Play") or reelGui:WaitForChild("Play", 5))
	if reelGui then
		local deadline = os.clock() + 5
		while not reelGui:GetAttribute("Ready") and os.clock() < deadline do RunService.Heartbeat:Wait() end
	end
	if play then
		local ok, err = pcall(play.Invoke, play, payload.Selection)
		if not ok then warn("[RewardSpinnerClient] reel failed: " .. tostring(err)) end
	else
		warn("[RewardSpinnerClient] StarterGui.SelectingReward is missing - skipping the reel")
	end
	finishedRemote:FireServer(payload.Token)
end

local function pump()
	if playing then return end
	playing = true
	while #queue > 0 do
		local payload = table.remove(queue, 1)
		local ok, err = pcall(runSpin, payload)
		if not ok then
			warn("[RewardSpinnerClient] spin failed: " .. tostring(err))
			pcall(finishedRemote.FireServer, finishedRemote, payload.Token)
		end
	end
	playing = false
end

spinRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.Kind == "Spin" and type(payload.Token) == "string" then
		table.insert(queue, payload)
		task.spawn(pump)
	elseif payload.Kind == "Granted" then
		for _, entry in ipairs(ButtonFX.SUCCESS_SOUNDS) do pcall(ButtonFX.Sound, entry) end
		Notify.Success(tostring(payload.Text or "Reward!"), 3)
	end
end)
print("[RewardSpinnerClient] confetti + reward reel ready")

--[[
	BoostPadClient  (LocalScript, StarterPlayerScripts)  2026-09-19
	The local half of the Boost Pad (ServerScriptService.BoostPadService):
	  * when the server gives this player a boost (player attribute SpeedBoostUntil jumps ahead), play the
	    "Zap" sound (ReplicatedStorage.Assets.Sounds, via SoundController) and shake the screen: a short,
	    fading jitter of Humanoid.CameraOffset, which the default camera applies itself - nothing else in
	    the game writes CameraOffset, and a Scriptable camera (lift / cutscene / hatch) is left alone
	  * while this player is in build mode (PlayerGui.CucumberHUDDesign attribute BuildMode) every pad's
	    "Speed up" prompt is hidden, so clicking a pad selects / sells it instead of boosting
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ATTR = "SpeedBoostUntil"
local PROMPT_TAG = "BoostPadPrompt"
local HUD_NAME = "CucumberHUDDesign"
local SHAKE_BIND = "BoostPadShake"
local SHAKE_TIME = 0.5 -- seconds
local SHAKE_AMP = 0.55 -- studs at the start, fading out (quadratic) ...
local SHAKE_PER_STUD = 0.045 -- ... and more when zoomed out, so it reads the same on screen at any zoom

--..Screen shake..--
local shakeHumanoid, shakeBase
local function StopShake()
	RunService:UnbindFromRenderStep(SHAKE_BIND)
	if shakeHumanoid and shakeHumanoid.Parent then shakeHumanoid.CameraOffset = shakeBase end
	shakeHumanoid, shakeBase = nil, nil
end

local function Shake()
	local camera = workspace.CurrentCamera
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid or camera.CameraType == Enum.CameraType.Scriptable then return end
	if shakeHumanoid ~= humanoid then
		StopShake()
		shakeHumanoid, shakeBase = humanoid, humanoid.CameraOffset
	end
	RunService:UnbindFromRenderStep(SHAKE_BIND)
	local started = os.clock()
	local rng = Random.new()
	--.. just before the camera update, so the default camera uses the offset the same frame
	RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value - 1, function()
		local a = (os.clock() - started) / SHAKE_TIME
		if a >= 1 or not humanoid.Parent then StopShake() return end
		local zoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		local k = math.max(SHAKE_AMP, SHAKE_PER_STUD * zoom) * (1 - a) * (1 - a)
		humanoid.CameraOffset = shakeBase + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5)) * k
	end)
end

--..The boost..--
local lastUntil = tonumber(player:GetAttribute(ATTR)) -- a boost already running when we join does not replay
player:GetAttributeChangedSignal(ATTR):Connect(function()
	local untilTime = tonumber(player:GetAttribute(ATTR))
	local fresh = untilTime and untilTime > workspace:GetServerTimeNow() and (not lastUntil or untilTime > lastUntil + 0.01)
	lastUntil = untilTime
	if not fresh then return end
	SoundController.PlayFX("Zap", {Volume = 0.9, Key = "BoostPadZap", MinInterval = 0.2, MaxLife = 4})
	Shake()
end)

--..Hide pad prompts in build mode..--
local function Building()
	local hud = playerGui:FindFirstChild(HUD_NAME)
	return hud ~= nil and hud:GetAttribute("BuildMode") == true
end

local function Apply(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	local base = tonumber(prompt:GetAttribute("BaseDistance")) or 12
	prompt.MaxActivationDistance = Building() and 0 or base -- local only; the server never changes it
end

local function ApplyAll()
	for _, prompt in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do Apply(prompt) end
end

CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(Apply)

local hudConnection
local function WatchHud(hud)
	if hud.Name ~= HUD_NAME then return end
	if hudConnection then hudConnection:Disconnect() end
	hudConnection = hud:GetAttributeChangedSignal("BuildMode"):Connect(ApplyAll)
	ApplyAll()
end
playerGui.ChildAdded:Connect(WatchHud)
local hud = playerGui:FindFirstChild(HUD_NAME)
if hud then WatchHud(hud) end
ApplyAll()

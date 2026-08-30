--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)

local FastWait = ControllerLoader.GetController("FastWait")

--..Variables..--
local Assets = ServerStorage.Assets
local Tag = Assets.Tag

local CharacterModule = {}

local R15_BODY_PARTS = {
	"Head";
	"UpperTorso"; "LowerTorso";
	"LeftUpperArm"; "LeftLowerArm"; "LeftHand";
	"RightUpperArm"; "RightLowerArm"; "RightHand";
	"LeftUpperLeg"; "LeftLowerLeg"; "LeftFoot";
	"RightUpperLeg"; "RightLowerLeg"; "RightFoot";
}

local function coreBodyHeight(Character)
	local lowest, highest
	for _, name in ipairs(R15_BODY_PARTS) do
		local part = Character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local half = part.Size * 0.5
			local cframe = part.CFrame
			local yExtent = math.abs(cframe.RightVector.Y) * half.X
				+ math.abs(cframe.UpVector.Y) * half.Y
				+ math.abs(cframe.LookVector.Y) * half.Z
			lowest = math.min(lowest or math.huge, part.Position.Y - yExtent)
			highest = math.max(highest or -math.huge, part.Position.Y + yExtent)
		end
	end
	if not lowest or not highest then return nil end
	return highest - lowest
end

-- Only naturally oversized R15 avatars are normalized, and their authored
-- core body height is fitted to a consistent six-stud target.
local NORMAL_R15_HEIGHT = 6

local NORMAL_SCALE_VALUES = {
	BodyHeightScale = 1;
	BodyWidthScale = 1;
	BodyDepthScale = 1;
	HeadScale = 1;
	BodyTypeScale = 0;
	BodyProportionScale = 0;
}

local function normalizeR15(Player, Character)
	task.spawn(function()
		local Humanoid = Character:WaitForChild("Humanoid", 10)
		if not Humanoid or Humanoid.RigType ~= Enum.HumanoidRigType.R15 then return end

		-- CharacterAdded precedes Roblox's avatar-description pass. Wait until the
		-- body packages and scale NumberValues are final so they cannot overwrite us.
		local deadline = os.clock() + 10
		while Player.Character == Character and Player.Parent == Players
			and not Player:HasAppearanceLoaded() and os.clock() < deadline
		do
			task.wait(0.05)
		end
		if Player.Character ~= Character or not Character.Parent then return end

		-- Preserve normal and short avatars exactly as Roblox loaded them. Only
		-- oversized R15 avatars are normalized to the authored reference rig.
		local originalHeight = coreBodyHeight(Character)
		if not originalHeight or originalHeight <= 7 then return end

		for name, value in pairs(NORMAL_SCALE_VALUES) do
			local scaleValue = Humanoid:FindFirstChild(name) or Humanoid:WaitForChild(name, 2)
			if scaleValue and scaleValue:IsA("NumberValue") then
				scaleValue.Value = value
			end
		end

		-- Allow Roblox's R15 scaler to rebuild joints/attachments, then fit the
		-- actual core body (never hats, wings, or layered-clothing bounds) to the rig.
		task.wait()
		if Player.Character ~= Character or not Character.Parent then return end
		local height = coreBodyHeight(Character)
		if not height or height <= 0 then return end
		local canonicalScale = Character:GetScale() * (NORMAL_R15_HEIGHT / height)

		if Player:GetAttribute("SuperStrengthActive") == true then
			Character:SetAttribute("SuperStrengthBaseScale", canonicalScale)
			Character:ScaleTo(canonicalScale * 2)
		else
			Character:SetAttribute("SuperStrengthBaseScale", nil)
			Character:ScaleTo(canonicalScale)
		end
		Character:SetAttribute("NormalizedAvatarScale", canonicalScale)
	end)
end

--..Functions..--

function CharacterModule.Tag(Character)
    local Player = Players:GetPlayerFromCharacter(Character)
    if not Player then return end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if Humanoid then
        -- Hide Roblox's built-in username/health nameplate. The authored Tag below
        -- is the only overhead identity UI players should see.
        Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end

    local Head = Character:FindFirstChild("Head")
    if not Head then return end

    local content = ""
    pcall(function()
        content = Players:GetUserThumbnailAsync(
            Player.UserId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size420x420
        )
    end)

    local ExistingTag = Head:FindFirstChild("Tag")
    if ExistingTag then ExistingTag:Destroy() end

    local PlayerTag = Tag:Clone()
    PlayerTag.Frame.PlayerName.Text = Player.DisplayName
    PlayerTag.Frame.Icon.Image = content
    PlayerTag.Parent = Head
end

function CharacterModule.CharacterJoined(Character)
    CharacterModule.Tag(Character)
    local Player = Players:GetPlayerFromCharacter(Character)
    if Player then normalizeR15(Player, Character) end
end

return CharacterModule

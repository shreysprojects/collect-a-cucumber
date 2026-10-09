local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local gui = script.Parent
local window = gui:WaitForChild("Window")
local close = window.Header.CloseButton
local claim = window.ClaimButton
local label = claim.Label
local folder = ReplicatedStorage:WaitForChild("GroupGift")
local remote = folder:WaitForChild("Claim")
local Zone = require(ReplicatedStorage.Modules:WaitForChild("GroupGiftZone"))
local Notify = require(ReplicatedStorage.Modules:WaitForChild("Notify"))
local busy = false

local function scaleOutlines()
 local scale = window.AbsoluteSize.X / 940
 for _, item in gui:GetDescendants() do
  if item:IsA("UIStroke") then
   local base = item:GetAttribute("DesignThickness")
   if base then item.Thickness = math.max(1, base * scale) end
  end
 end
end
window:GetPropertyChangedSignal("AbsoluteSize"):Connect(scaleOutlines)
scaleOutlines()
local function feedback(button)
 local scale = button:FindFirstChild("InteractionScale") or Instance.new("UIScale")
 scale.Name = "InteractionScale"
 scale.Parent = button
 local function animate(value)
  TweenService:Create(scale, TweenInfo.new(.1), {Scale = value}):Play()
 end
 button.MouseEnter:Connect(function() animate(1.025) end)
 button.MouseLeave:Connect(function() animate(1) end)
 button.SelectionGained:Connect(function() animate(1.025) end)
 button.SelectionLost:Connect(function() animate(1) end)
 button.MouseButton1Down:Connect(function() animate(.97) end)
 button.MouseButton1Up:Connect(function() animate(1) end)
end
feedback(close)
feedback(claim)
close.Activated:Connect(function() gui.Enabled = false end)
local function refreshClaim()
 if not busy then label.Text = player:GetAttribute("GroupGiftClaimed") and "Claimed!" or "Claim!" end
end
player:GetAttributeChangedSignal("GroupGiftClaimed"):Connect(refreshClaim)
refreshClaim()

local function requestClaim()
 local ok, result = pcall(function() return remote:InvokeServer() end)
 if not ok or type(result) ~= "table" then return {Status = "CheckFailed"} end
 return result
end
local function showResult(result)
 local status = result.Status
 if status == "Claimed" then
  Notify.Success("+10,000 Strength! Thanks for joining Group Frenzy!", 4)
 elseif status == "AlreadyClaimed" then
  Notify.Info("You already claimed this community gift.")
 elseif status == "TooFar" then
  Notify.Info("Stand inside the Group Chest circle to claim.")
 elseif status == "Loading" then
  Notify.Info("Your data is still loading. Try again in a moment.")
 elseif status == "Busy" then
  Notify.Info("Please wait a moment, then try again.")
 elseif status == "NotMember" then
  Notify.Info("Membership is still updating. Try Claim again shortly.", 4)
 else
  Notify.Error("Couldn't check your group membership. Please try again.")
 end
end
local function claimGift()
 if busy or player:GetAttribute("GroupGiftClaimed") then return end
 busy = true
 label.Text = "Checking..."
 local ok, err = pcall(function()
  local result = requestClaim()
  if result.Status == "NotMember" then
   label.Text = "Join Group!"
   local prompted, membership = pcall(function()
    return GroupService:PromptJoinAsync(folder:GetAttribute("GroupId"))
   end)
   if not prompted then
    Notify.Error("Couldn't open the group prompt. Please try again.")
    return
   end
   if membership == Enum.GroupMembershipStatus.JoinRequestPending then
    Notify.Info("Your join request is pending. Claim after it is approved.", 4)
    return
   end
   if membership ~= Enum.GroupMembershipStatus.Joined and membership ~= Enum.GroupMembershipStatus.AlreadyMember then
    Notify.Info("Join Group Frenzy to claim your 10,000 Strength.", 4)
    return
   end
   label.Text = "Verifying..."
   -- Allow Roblox time to propagate the join; every retry verifies on the server.
   for _, delaySeconds in ipairs({1.5, 2, 3, 4}) do
    task.wait(delaySeconds)
    result = requestClaim()
    if result.Status ~= "NotMember" and result.Status ~= "Busy" and result.Status ~= "CheckFailed" then break end
   end
  end
  showResult(result)
 end)
 busy = false
 refreshClaim()
 if not ok then
  warn("[GroupGift] " .. tostring(err))
  Notify.Error("Couldn't claim the gift. Please try again.")
 end
end
claim.Activated:Connect(claimGift)
-- Keep the existing local UI hook connected to the same guarded action.
gui:WaitForChild("ClaimRequested").Event:Connect(claimGift)

local wasInside = false
local elapsed = 0
local zoneConnection
zoneConnection = RunService.Heartbeat:Connect(function(dt)
 elapsed += dt
 if elapsed < .15 then return end
 elapsed = 0
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 local inside = root ~= nil and humanoid ~= nil and humanoid.Health > 0 and Zone.Contains(root.Position, .4)
 if inside and not wasInside then
  gui.Enabled = true
  refreshClaim()
 end
 wasInside = inside
end)
gui.Destroying:Connect(function() zoneConnection:Disconnect() end)

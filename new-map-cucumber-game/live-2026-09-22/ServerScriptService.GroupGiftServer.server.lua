local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Data = require(ServerStorage:WaitForChild("DataService"))
local Reward = require(ServerStorage:WaitForChild("GroupGiftReward"))
local Zone = require(ReplicatedStorage.Modules:WaitForChild("GroupGiftZone"))
local folder = ReplicatedStorage:WaitForChild("GroupGift")
local remote = folder:WaitForChild("Claim")
local GROUP_ID = 14583228
local busy, lastRequest = {}, {}

local function nearby(player)
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 return root and humanoid and humanoid.Health > 0 and Zone.Contains(root.Position, 3)
end
local function claim(player)
 if not nearby(player) then return "TooFar" end
 local profile = Data.GetProfile(player)
 if not profile or not profile:IsActive() then return "Loading" end
 if profile.Data.GroupGiftClaimed == true then return "AlreadyClaimed" end
 -- Fetch the server's membership list afresh, including after the client join prompt.
 -- Never accept a client-supplied membership result or reward amount.
 local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
 if not ok or type(groups) ~= "table" then return "CheckFailed" end
 local member = false
 for _, group in ipairs(groups) do
  if group.Id == GROUP_ID then member = true break end
 end
 if player.Parent ~= Players or Data.GetProfile(player) ~= profile or not profile:IsActive() then return "Loading" end
 if not nearby(player) then return "TooFar" end
 local status = Reward.Apply(profile.Data, member)
 if status == "Claimed" then
  Data.Set(player, "Strength", profile.Data.Strength, true)
  player:SetAttribute("GroupGiftClaimed", true)
  Data.RequestSave(player)
 end
 return status
end
remote.OnServerInvoke = function(player)
 local now = os.clock()
 if busy[player] or now - (lastRequest[player] or -math.huge) < 1 then
  return {Status = "Busy", GroupId = GROUP_ID}
 end
 busy[player], lastRequest[player] = true, now
 local ok, status = pcall(claim, player)
 busy[player] = nil
 if not ok then
  warn("[GroupGift] Claim failed: " .. tostring(status))
  status = "CheckFailed"
 end
 return {Status = status, GroupId = GROUP_ID}
end
Data.OnProfileLoaded(function(player, profile)
 player:SetAttribute("GroupGiftClaimed", profile.Data.GroupGiftClaimed == true)
end)
Players.PlayerRemoving:Connect(function(player)
 busy[player], lastRequest[player] = nil, nil
end)

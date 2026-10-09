-- Mutate both saved fields together, without yielding; the server persists them together.
local Reward = {}
function Reward.Apply(data, isMember)
 if type(data) ~= "table" then return "Loading" end
 if data.GroupGiftClaimed == true then return "AlreadyClaimed" end
 if isMember ~= true then return "NotMember" end
 if type(data.Strength) ~= "number" then return "Loading" end
 data.Strength += 10000
 data.GroupGiftClaimed = true
 return "Claimed"
end
return Reward

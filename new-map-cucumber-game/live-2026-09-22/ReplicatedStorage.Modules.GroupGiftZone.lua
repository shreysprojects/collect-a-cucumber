local Zone = {}
function Zone.Get()
 local map = workspace:FindFirstChild("Map")
 local lobby = map and map:FindFirstChild("Lobby")
 local stations = lobby and lobby:FindFirstChild("Stations")
 local chest = stations and stations:FindFirstChild("Group Chest")
 return chest and chest:FindFirstChild("GiftTrigger")
end
function Zone.Contains(position, padding)
 local part = Zone.Get()
 if not part then return false end
 local p = part.CFrame:PointToObjectSpace(position)
 local extra = padding or 0
 local x, z = part.Size.X / 2 + extra, part.Size.Z / 2 + extra
 return math.abs(p.Y) <= part.Size.Y / 2 + extra and (p.X / x)^2 + (p.Z / z)^2 <= 1
end
return Zone

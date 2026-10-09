-- Shared balance: six physique upgrades after the starting build.
local Progression = {}
Progression.BaseWalkSpeed = 25
Progression.MaxWalkSpeed = 120
Progression.Stages = {
 {Strength=0,        Name="Beginner",  Height=5.5, Width=.95, Depth=.95, Bulk=0},
 {Strength=100,      Name="Fit",       Height=5.8, Width=1.04,Depth=1.04,Bulk=.18},
 {Strength=1000,     Name="Athletic",  Height=6.1, Width=1.16,Depth=1.13,Bulk=.34},
 {Strength=10000,    Name="Strong",    Height=6.5, Width=1.31,Depth=1.24,Bulk=.50},
 {Strength=100000,   Name="Muscular",  Height=7.0, Width=1.48,Depth=1.36,Bulk=.68},
 {Strength=1000000,  Name="Powerhouse",Height=7.5, Width=1.66,Depth=1.49,Bulk=.84},
 {Strength=10000000, Name="Champion",  Height=8.0, Width=1.85,Depth=1.62,Bulk=1},
}
function Progression.CleanStrength(value)
 local n=tonumber(value) or 0
 if n~=n or n<0 then return 0 end
 return math.min(n,1e300)
end
function Progression.GetStage(strength)
 strength=Progression.CleanStrength(strength)
 for index=#Progression.Stages,1,-1 do
  if strength>=Progression.Stages[index].Strength then
   return index-1,Progression.Stages[index]
  end
 end
 return 0,Progression.Stages[1]
end
function Progression.GetWalkSpeed(strength)
 local value=Progression.CleanStrength(strength)
 return math.min(Progression.MaxWalkSpeed,Progression.BaseWalkSpeed+6*math.log10(1+value/100))
end
return Progression

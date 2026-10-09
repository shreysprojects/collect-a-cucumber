$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fb = "C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
function ReadF($p) { return [System.IO.File]::ReadAllText($p) }
$req = @'
local REAL_KIT, REAL_ASSETS
local require = function(x)
	if type(x) == "table" and x.Name == "FunBuildKit" then return REAL_KIT end
	if type(x) == "table" and x.Name == "FunAssets" then return REAL_ASSETS end
	error("unexpected require " .. tostring(x and x.Name))
end
'@
$all = (ReadF "$here\shim.luau") + "`n" + (ReadF "$here\runtime.luau") + "`n" + (ReadF "$here\parts.luau") + "`n" + $req + "`n" +
  "REAL_KIT = (function()`n" + (ReadF "$fb\src\FunBuildKit.lua") + "`nend)()`n" +
  "REAL_ASSETS = (function()`n" + (ReadF "$fb\src\FunAssets.lua") + "`nend)()`n" +
  "SERVER_GC = (function()`n" + (ReadF "$fb\src\behaviours\server\GlassCase.lua") + "`nend)()`n" +
  "CLIENT_GC = (function()`n" + (ReadF "$fb\src\behaviours\client\GlassCase.lua") + "`nend)()`n" +
  "SERVER_NS = (function()`n" + (ReadF "$fb\src\behaviours\server\NeonSign.lua") + "`nend)()`n" +
  "CLIENT_NS = (function()`n" + (ReadF "$fb\src\behaviours\client\NeonSign.lua") + "`nend)()`n" +
  (ReadF "$here\scenario.luau")
$tmp = Join-Path $here "run_combined.luau"
[System.IO.File]::WriteAllText($tmp, $all, (New-Object System.Text.UTF8Encoding($false)))
& $luau $tmp 2>&1



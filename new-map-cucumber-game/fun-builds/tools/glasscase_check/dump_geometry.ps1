# Combine shim + the two client behaviour modules + driver, run in the Luau CLI, write geometry.json
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fb = "C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
$shim = [System.IO.File]::ReadAllText((Join-Path $here "shim.luau"))
$gc = [System.IO.File]::ReadAllText("$fb\src\behaviours\client\GlassCase.lua")
$ns = [System.IO.File]::ReadAllText("$fb\src\behaviours\client\NeonSign.lua")
$drv = [System.IO.File]::ReadAllText((Join-Path $here "driver.luau"))
$all = $shim + "`nlocal require = STUB_REQUIRE`nGC = (function()`n" + $gc + "`nend)()`nNS = (function()`n" + $ns + "`nend)()`n" + $drv
$tmp = Join-Path $here "combined.luau"
[System.IO.File]::WriteAllText($tmp, $all, (New-Object System.Text.UTF8Encoding($false)))
$out = & $luau $tmp 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Output "LUAU FAIL: $out"; exit 1 }
[System.IO.File]::WriteAllText((Join-Path $here "geometry.json"), $out.Trim(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("OK " + $out.Length + " chars")

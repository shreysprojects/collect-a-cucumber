# Seesaw offline harness (2026-09-24): runs the REAL FunBuildKit + Seesaw server/client sources in the Luau CLI
# against stub CFrame/Vector3/instances (prelude.luau) and a scripted scenario (driver.luau). Prints PASS/FAIL lines
# and the sound log.   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Seesaw\run.ps1
$FB = Split-Path (Split-Path $PSScriptRoot)
$here = $PSScriptRoot
$parts = @(
  [IO.File]::ReadAllText("$here\prelude.luau"),
  "local KitMod = (function()`n" + [IO.File]::ReadAllText("$FB\src\FunBuildKit.lua") + "`nend)()`nModules.FunBuildKit.__module = KitMod`n",
  "local FunAssetsMod = (function()`n" + [IO.File]::ReadAllText("$FB\src\FunAssets.lua") + "`nend)()`nModules.FunAssets.__module = FunAssetsMod`n",
  "local ServerB = (function()`n" + [IO.File]::ReadAllText("$FB\src\behaviours\server\Seesaw.lua") + "`nend)()`n",
  "local ClientB = (function()`n" + [IO.File]::ReadAllText("$FB\src\behaviours\client\Seesaw.lua") + "`nend)()`n",
  [IO.File]::ReadAllText("$here\driver.luau")
)
$tmp = Join-Path $env:TEMP ("seesaw_test_" + [guid]::NewGuid().ToString("N") + ".luau")
[IO.File]::WriteAllText($tmp, ($parts -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
& "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe" $tmp
Remove-Item $tmp -ErrorAction SilentlyContinue
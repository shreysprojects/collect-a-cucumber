# Offline run of the HomeLaundry behaviours (WashingMachine + Dryer) against mocked Roblox types (fun-builds, 2026-09-24).
# build_test.py inlines the REAL framework (FunBuildKit / FunAssets / FunBuildService / FunBuildClient), the four laundry
# modules and the two models (models/out/*.parts.json) into run_test.luau; the Luau CLI runs the scenario (test.luau).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\HomeLaundry\run.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
& py (Join-Path $here "build_test.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $luau (Join-Path $here "run_test.luau")
exit $LASTEXITCODE

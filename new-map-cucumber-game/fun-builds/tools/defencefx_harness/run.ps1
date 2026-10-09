# DefenceFX offline harness (fun-builds, 2026-09-24): wraps the scripts (gen.py) and runs both suites.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\defencefx_harness\run.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
Push-Location $here
try {
  py gen.py
  & $luau test_client.luau
  $c = $LASTEXITCODE
  & $luau test_server.luau
  $s = $LASTEXITCODE
  if ($c -ne 0 -or $s -ne 0) { exit 1 } else { exit 0 }
} finally { Pop-Location }

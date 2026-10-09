# Kitchen (Fridge / Microwave) offline harness (fun-builds, 2026-09-24): wraps the real modules + parts.json (gen.py)
# and runs test.luau on the mocks. Exit 0 = ALL OK.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\kitchen_harness\run.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
Push-Location $here
try {
  py gen.py
  & $luau test.luau
  exit $LASTEXITCODE
} finally { Pop-Location }

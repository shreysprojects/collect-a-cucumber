# Offline run of the Trampoline client behaviour against mocked Roblox types (fun-builds, 2026-09-24).
# Concatenates prelude.luau (Vector3/CFrame/Instance/service mocks + a simulated clock) + the REAL
# src/FunBuildKit.lua, src/FunAssets.lua, src/behaviours/client/Trampoline.lua + test.luau (a scripted
# character whose Jumping impulse replaces / adds / is late / is absent, 60 and 30 fps, Step once or twice
# per frame, remote players with and without replicated velocity, cleanup) and runs it in the Luau CLI.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\trampoline\run.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "..\..\src"
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
$parts = @(
  [IO.File]::ReadAllText((Join-Path $here "prelude.luau")),
  "local KitModule = (function()`n" + [IO.File]::ReadAllText((Join-Path $src "FunBuildKit.lua")) + "`nend)()`n",
  "local AssetsModule = (function()`n" + [IO.File]::ReadAllText((Join-Path $src "FunAssets.lua")) + "`nend)()`n",
  "KitScript.Module = KitModule`nAssetsScript.Module = AssetsModule`n",
  "local B = (function()`n" + [IO.File]::ReadAllText((Join-Path $src "behaviours\client\Trampoline.lua")) + "`nend)()`n",
  [IO.File]::ReadAllText((Join-Path $here "test.luau"))
)
$tmp = Join-Path $env:TEMP ("tramp_harness_" + [guid]::NewGuid().ToString("N") + ".luau")
[IO.File]::WriteAllText($tmp, ($parts -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
& $luau $tmp
$code = $LASTEXITCODE
Remove-Item $tmp -ErrorAction SilentlyContinue
exit $code

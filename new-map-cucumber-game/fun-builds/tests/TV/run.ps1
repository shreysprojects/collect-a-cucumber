# Offline smoke test of the TV behaviour (fun-builds, 2026-09-24): mocked Roblox runtime (prelude.luau) + the REAL
# FunBuildKit, FunAssets and both TV halves + test.luau, run in the Luau CLI with a strict global environment
# (any misspelled name errors). Prints the measured screen geometry and "<n> checks, 0 failed".
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\TV\run.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "..\..\src"
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
function Wrap($name, $path, $register) {
  $body = [System.IO.File]::ReadAllText((Resolve-Path $path))
  $out = "`nlocal $name = (function()`n" + $body + "`nend)()`n"
  if ($register) { $out += "RegisterModule(`"$register`", $name)`n" }
  return $out
}
$text = [System.IO.File]::ReadAllText((Join-Path $here "prelude.luau"))
$text += Wrap "KitModule" (Join-Path $src "FunBuildKit.lua") "FunBuildKit"
$text += Wrap "FunAssetsModule" (Join-Path $src "FunAssets.lua") "FunAssets"
$text += Wrap "ClientB" (Join-Path $src "behaviours\client\TV.lua") $null
$text += Wrap "ServerB" (Join-Path $src "behaviours\server\TV.lua") $null
$text += [System.IO.File]::ReadAllText((Join-Path $here "test.luau"))
$tmp = Join-Path $env:TEMP ("tvtest_" + [guid]::NewGuid().ToString("N") + ".luau")
[System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
& $luau $tmp
$code = $LASTEXITCODE
Remove-Item $tmp -ErrorAction SilentlyContinue
exit $code

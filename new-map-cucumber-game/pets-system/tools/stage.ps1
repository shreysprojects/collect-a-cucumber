param(
  [string[]]$Src = @(),      # src file names to stage (empty = none)
  [string[]]$Patched = @()   # patched file names to stage (empty = none)
)
# Builds pets-system\stage\ (flat) for serve.ps1: the selected src\ files + _install.json, the
# surgical patches.json for the selected patched\ files (mkpatch.py against the 2026-09-22 live
# snapshot), and the two Luau installers. 2026-09-22.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path (Split-Path -Parent $root) "live-2026-09-22"
$stage = Join-Path $root "stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

$srcDir = Join-Path $root "src"

$install = @()
foreach ($f in $Src) {
  $class = "ModuleScript"; $path = $f -replace '\.lua$', ''
  if ($f -like "*.server.lua") { $class = "Script"; $path = $f -replace '\.server\.lua$', '' }
  elseif ($f -like "*.client.lua") { $class = "LocalScript"; $path = $f -replace '\.client\.lua$', '' }
  Copy-Item (Join-Path $srcDir $f) (Join-Path $stage $f)
  $install += [pscustomobject]@{ file = $f; path = $path; class = $class }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $stage "_install.json"), (ConvertTo-Json @($install) -Depth 3), $utf8)

$patchedDir = Join-Path $root "patched"

if ($Patched.Count -gt 0) {
  $manifest = Get-Content (Join-Path $live "_manifest.json") -Raw | ConvertFrom-Json
  $specs = @()
  foreach ($f in $Patched) {
    $m = $manifest | Where-Object { $_.file -eq $f }
    if (-not $m) { throw "no manifest entry for $f" }
    $specs += "$f=game.$($m.path)"
  }
  # diff base per file = the version last pushed live (pushed\<file>, written by tools\mark_pushed.ps1)
  # or, before its first push, the 2026-09-22 snapshot
  $base = Join-Path $stage "_base"
  New-Item -ItemType Directory -Force $base | Out-Null
  $pushedDir = Join-Path $root "pushed"
  foreach ($f in $Patched) {
    $from = Join-Path $pushedDir $f
    if (-not (Test-Path $from)) { $from = Join-Path $live $f }
    Copy-Item $from (Join-Path $base $f)
  }
  & "C:\Users\shrey\AppData\Local\Programs\Python\Python312\python.exe" (Join-Path (Split-Path -Parent (Split-Path -Parent $root)) "pets-remake\mkpatch.py") $base $patchedDir (Join-Path $stage "patches.json") @specs
  if ($LASTEXITCODE -ne 0) { throw "mkpatch failed" }
} else {
  [System.IO.File]::WriteAllText((Join-Path $stage "patches.json"), "[]", $utf8)
}
Copy-Item (Join-Path $PSScriptRoot "install_new.lua") $stage
# S0a (2026-09-22): the test-profile tools ride along so every stage serves them at :8796
foreach ($t in @("snapshot_profile.lua", "restore_profile.lua")) {
  $tp = Join-Path $PSScriptRoot $t
  if (Test-Path $tp) { Copy-Item $tp $stage }
}
Copy-Item (Join-Path (Split-Path -Parent (Split-Path -Parent $root)) "pets-remake\apply_patches.lua") $stage
"staged: $($Src.Count) new, $($Patched.Count) patched -> $stage"




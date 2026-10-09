param([string[]]$Patched = @())
# After a SUCCESSFUL push (apply_patches wrote the script and the live Source was verified), record the
# pushed version so the next stage.ps1 diff for that file starts from what is live. 2026-09-22.
$root = Split-Path -Parent $PSScriptRoot
$pushed = Join-Path $root "pushed"
New-Item -ItemType Directory -Force $pushed | Out-Null
foreach ($f in $Patched) { Copy-Item (Join-Path $root "patched\$f") (Join-Path $pushed $f) -Force; "pushed: $f" }

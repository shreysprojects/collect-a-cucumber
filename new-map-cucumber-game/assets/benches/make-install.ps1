# Fills install_benches.lua with asset-ids.json + manifest.json -> install_benches.generated.lua
# (run that file's content through the Studio MCP execute_luau in edit mode).
$here = $PSScriptRoot
$assets = (Get-Content (Join-Path $here "asset-ids.json") -Raw).Trim()
$manifest = (Get-Content (Join-Path $here "manifest.json") -Raw).Trim()
$src = Get-Content (Join-Path $here "install_benches.lua") -Raw
$src = $src.Replace("__ASSETS__", $assets).Replace("__MANIFEST__", $manifest)
[IO.File]::WriteAllText((Join-Path $here "install_benches.generated.lua"), $src, (New-Object Text.UTF8Encoding($false)))
"wrote install_benches.generated.lua ($($src.Length) chars)"

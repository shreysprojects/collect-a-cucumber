# Uploads every tier's <Tier>_Bench.fbx and <Tier>_Barbell.fbx as Roblox Model assets through
# Open Cloud (upload-model.ps1) and records the ids in asset-ids.json (re-runs skip what is done).
#   $env:ROBLOX_OPEN_CLOUD_API_KEY = "..." ; .\upload-all.ps1        (or -KeyFile path)
param([string]$KeyFile = "", [string]$GroupId = "", [string[]]$Tiers = @("Starter", "Iron", "Gold", "Frost", "Inferno", "Cosmic"))
$here = $PSScriptRoot
$idsPath = Join-Path $here "asset-ids.json"
$ids = @{}
if (Test-Path $idsPath) {
	$obj = Get-Content $idsPath -Raw | ConvertFrom-Json
	foreach ($p in $obj.PSObject.Properties) { $ids[$p.Name] = @{ bench = $p.Value.bench; barbell = $p.Value.barbell } }
}
function Save-Ids { $ids | ConvertTo-Json -Depth 4 | Set-Content -Path $idsPath -Encoding ascii }
function Upload-One([string]$file, [string]$name) {
	$args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $here "upload-model.ps1"), "-File", $file, "-Name", $name, "-Description", "Low-poly themed bench press tier for the cucumber gym (Blender)")
	if ($KeyFile) { $args += @("-KeyFile", $KeyFile) }
	if ($GroupId) { $args += @("-GroupId", $GroupId) }
	$out = & powershell @args 2>&1 | Out-String
	Write-Host $out
	if ($out -match "ASSET ID: (\d+)") { return [string]$Matches[1] }
	throw "upload failed for $file"
}
foreach ($t in $Tiers) {
	if (-not $ids.ContainsKey($t)) { $ids[$t] = @{ bench = $null; barbell = $null } }
	if (-not $ids[$t].bench) { $ids[$t].bench = Upload-One (Join-Path $here "$t`_Bench.fbx") "Bench $t"; Save-Ids }
	if (-not $ids[$t].barbell) { $ids[$t].barbell = Upload-One (Join-Path $here "$t`_Barbell.fbx") "Barbell $t"; Save-Ids }
}
Write-Host "done:"
Get-Content $idsPath

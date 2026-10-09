# upload-set2.ps1: uploads the five 2026-09-16 defence FBX files as GROUP-owned Model assets
# (Group Frenzy 14583228) through new-map-cucumber-game/assets/benches/upload-model.ps1 and writes
# fbx/asset-ids-set2.json. The key file is never committed (pass the scratchpad path).
#   .\upload-set2.ps1 -KeyFile C:\...\oc.key [-Names Mortar,TeslaCoil,...]
param(
	[Parameter(Mandatory = $true)][string]$KeyFile,
	[string[]]$Names = @("Mortar", "TeslaCoil", "FreezeTower", "Minigun", "LaserGate"),
	[string]$GroupId = "14583228"
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$uploader = Join-Path $here "..\new-map-cucumber-game\assets\benches\upload-model.ps1"
$out = Join-Path $here "fbx\asset-ids-set2.json"
$ids = @{}
if (Test-Path $out) { try { (Get-Content $out -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $ids[$_.Name] = $_.Value } } catch {} }
foreach ($n in $Names) {
	$fbx = Join-Path $here ("fbx\" + $n + ".fbx")
	if (-not (Test-Path $fbx)) { Write-Host "SKIP $n (no fbx)"; continue }
	Write-Host "== $n"
	$lines = & powershell -NoProfile -File $uploader -File $fbx -Name ("Defence " + $n) -Description "New Map Cucumber Game defence prop (Blender, 2026-09-16)" -GroupId $GroupId -KeyFile $KeyFile 2>&1
	$lines | ForEach-Object { Write-Host $_ }
	$idLine = $lines | Where-Object { $_ -match "ASSET ID: (\d+)" } | Select-Object -Last 1
	if ($idLine -and $idLine -match "ASSET ID: (\d+)") { $ids[$n] = $Matches[1] } else { Write-Host "FAILED $n" }
}
$ids | ConvertTo-Json | Set-Content -Path $out -Encoding ascii
Write-Host ("wrote " + $out + ": " + ($ids.Keys -join ", "))

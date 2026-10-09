# Uploads every KeyframeSequence .rbxm in .\anims as a Roblox "Animation" asset through
# Open Cloud and writes anims\anim-ids.json.  Same fire-all-then-poll shape as
# upload-guardians.ps1, because 70 sequential uploads would take twenty minutes.
#
# CREATOR: group only.  The key family the user pastes is group-write; a userId creator
# context returns 403 "User not authenticated".  The note in
# assets/anims/upload-animations.ps1 that "a group-owned animation only plays in
# group-owned experiences" is NOT true here and was tested on 2026-09-15: animation
# 129265796517160, owned by group 14583228, loaded and played on a rig in the
# USER-owned New Map place (LoadAnimation ok, track length 1.10, the head moved).
#
#   .\upload-anims.ps1 -KeyFile C:\path\oc.key
#   .\upload-anims.ps1 -KeyFile C:\path\oc.key -Only Strawman_Wake,Pinch_Snap
param(
    [string]$KeyFile = "",
    [string]$GroupId = "14583228",
    [string[]]$Only = @(),
    [switch]$Force,
    [int]$PollSeconds = 4,
    [int]$MaxPolls = 90
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = Join-Path $here "anims"
$outFile = Join-Path $dir "anim-ids.json"

$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }

$results = @{}
if (Test-Path $outFile) {
    try {
        (Get-Content $outFile -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $results[$_.Name] = $_.Value }
    } catch {}
}
function Save-Results { ($results | ConvertTo-Json -Depth 4) | Set-Content -Path $outFile -Encoding utf8 }

$files = Get-ChildItem -Path $dir -Filter *.rbxm | Sort-Object Name
if ($Only.Count -gt 0) { $files = $files | Where-Object { $Only -contains $_.BaseName } }
if (-not $files) { throw "no .rbxm files in $dir" }

$creator = @{ groupId = $GroupId }

$pending = @()
foreach ($f in $files) {
    $name = $f.BaseName                                   # e.g. Strawman_Wake
    if (-not $Force -and $results[$name]) { Write-Host "skip  $name"; continue }
    $pretty = "Guardian " + ($name -replace "_", " ")
    $request = @{
        assetType       = "Animation"
        displayName     = $pretty
        description     = "Biome guardian animation for the cucumber game."
        creationContext = @{ creator = $creator }
    } | ConvertTo-Json -Compress -Depth 5

    $tmp = New-TemporaryFile
    $request | Set-Content -Path $tmp -Encoding ascii -NoNewline
    $resp = & curl.exe -sS -X POST "https://apis.roblox.com/assets/v1/assets" `
        -H "x-api-key: $key" `
        --form "request=<$tmp;type=application/json" `
        --form "fileContent=@`"$($f.FullName)`";type=model/x-rbxm"
    Remove-Item $tmp -Force

    $op = $null
    try { $op = (($resp -join "`n") | ConvertFrom-Json).operationId } catch {}
    if (-not $op) { Write-Host "FAILED $name : $resp"; continue }
    $pending += [pscustomobject]@{ Name = $name; Op = $op }
}

Write-Host ""
Write-Host "$($pending.Count) animation uploads in flight; polling..."

for ($p = 0; $p -lt $MaxPolls -and $pending.Count -gt 0; $p++) {
    Start-Sleep -Seconds $PollSeconds
    $still = @()
    foreach ($item in $pending) {
        $raw = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$($item.Op)" -H "x-api-key: $key"
        $r = $null
        try { $r = $raw | ConvertFrom-Json } catch { $still += $item; continue }
        if ($r.done) {
            if ($r.error) { Write-Host "FAILED $($item.Name) : $raw" }
            else {
                $results[$item.Name] = $r.response.assetId
                Write-Host "OK    $($item.Name) -> $($r.response.assetId)"
            }
        } else { $still += $item }
    }
    $pending = $still
    if ($pending.Count -gt 0) { Save-Results }
}

foreach ($item in $pending) { Write-Host "TIMEOUT $($item.Name)" }
Save-Results
Write-Host ""
Write-Host "wrote $outFile  ($($results.Count) animations)"

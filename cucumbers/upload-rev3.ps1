# Uploads the named cucumber FBX files in .\fbx as GROUP-owned Roblox "Model" assets through
# Open Cloud and MERGES their ids into fbx\asset-ids.json (existing entries are kept).
#
# Written 2026-09-18 for the Toyland + Neon batch (CUCUMBERS-REV3.md). It replaces
# upload-cucumbers.ps1 for new work: that older script pre-flights on the `exp` of the JWT
# embedded in the pasted key and REFUSES to run when it reads as stale, which is wrong (the
# `w/...` prefix is the real key; a key whose JWT had "expired" uploaded fine). This one only
# prints that number and lets the server judge - a dead key 401s at once.
#
# The key family the user pastes is GROUP-write only (creator.userId -> 403), so the
# default creator is group 14583228 (Group Frenzy).
#
#   .\upload-rev3.ps1 -KeyFile <path> -Only ToylandToySlice,NeonPalm
#   .\upload-rev3.ps1 -KeyFile <path> -Only (Get-Content names.txt) -Force
param(
    [string]$KeyFile = "",
    [string]$GroupId = "14583228",
    [Parameter(Mandatory = $true)][string[]]$Only,
    [switch]$Force,
    [int]$PollSeconds = 3,
    [int]$MaxPolls = 100
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fbxDir = Join-Path $here "fbx"
$outFile = Join-Path $fbxDir "asset-ids.json"

$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }

try {
    $i = $key.IndexOf("ZXlK")
    if ($i -gt 0) {
        $jwt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.Substring($i)))
        $payload = $jwt.Split(".")[1].Replace("-", "+").Replace("_", "/")
        while ($payload.Length % 4) { $payload += "=" }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $left = [int]($claims.exp - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Write-Host ("key: ownerId {0}, embedded JWT says {1} minutes left (informational only)" -f `
            $claims.ownerId, [math]::Round($left / 60))
    }
} catch { Write-Host "note: could not decode the embedded JWT, continuing" }

# keep every existing id (the 57 older models live in the same file)
$results = [ordered]@{}
if (Test-Path $outFile) {
    (Get-Content $outFile -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $results[$_.Name] = $_.Value }
}
function Save-Results { ($results | ConvertTo-Json -Depth 4) | Set-Content -Path $outFile -Encoding utf8 }

# -Only arrives as one comma-joined string when called through powershell -File
$names = @($Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$files = @()
foreach ($n in $names) {
    $p = Join-Path $fbxDir ($n + ".fbx")
    if (-not (Test-Path $p)) { throw "missing $p - export it from Blender first" }
    $files += Get-Item $p
}

# ---- pass 1: fire every create request ------------------------------------------------
$pending = @()
foreach ($f in $files) {
    $name = $f.BaseName
    if (-not $Force -and $results[$name]) { Write-Host "skip  $name (have $($results[$name]))"; continue }

    # "ToylandToyTrainCucumber" -> "Cucumber Toyland Toy Train Cucumber"
    $pretty = "Cucumber " + [Regex]::Replace($name, '(?<!^)(?=[A-Z])', ' ')
    $request = @{
        assetType       = "Model"
        displayName     = $pretty
        description     = "Low-poly cucumber model for the cucumber game (Toyland / Neon set)."
        creationContext = @{ creator = @{ groupId = $GroupId } }
    } | ConvertTo-Json -Compress -Depth 5

    $tmp = New-TemporaryFile
    $request | Set-Content -Path $tmp -Encoding ascii -NoNewline
    $resp = & curl.exe -sS -X POST "https://apis.roblox.com/assets/v1/assets" `
        -H "x-api-key: $key" `
        --form "request=<$tmp;type=application/json" `
        --form "fileContent=@`"$($f.FullName)`";type=model/fbx"
    Remove-Item $tmp -Force

    $body = ($resp -join "`n")
    $op = $null
    try { $op = ($body | ConvertFrom-Json).operationId } catch {}
    if (-not $op) { Write-Host "FAILED $name : $body"; continue }
    $pending += [pscustomobject]@{ Name = $name; Op = $op }
    Write-Host "sent  $name"
}

Write-Host ""
Write-Host "$($pending.Count) uploads in flight; polling..."

# ---- pass 2: poll them all together ---------------------------------------------------
for ($p = 0; $p -lt $MaxPolls -and $pending.Count -gt 0; $p++) {
    Start-Sleep -Seconds $PollSeconds
    $still = @()
    foreach ($item in $pending) {
        $raw = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$($item.Op)" -H "x-api-key: $key"
        $r = $null
        try { $r = $raw | ConvertFrom-Json } catch { $still += $item; continue }
        if ($r.done) {
            if ($r.error) {
                Write-Host "FAILED $($item.Name) : $raw"
            } else {
                $results[$item.Name] = $r.response.assetId
                Write-Host "OK    $($item.Name) -> $($r.response.assetId)"
            }
        } else {
            $still += $item
        }
    }
    $pending = $still
    Save-Results
}

foreach ($item in $pending) { Write-Host "TIMEOUT $($item.Name) (operation $($item.Op))" }

Save-Results
Write-Host ""
Write-Host "wrote $outFile  ($($results.Count) assets)"

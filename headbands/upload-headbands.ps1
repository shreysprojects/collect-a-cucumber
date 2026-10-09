# Uploads every headband .fbx in .\fbx as a Roblox "Model" asset through Open Cloud and
# writes asset-ids.json next to this script.  Reuses the proven request shape from
# new-map-cucumber-game/assets/benches/upload-model.ps1.
#
# The key family the user pastes is GROUP-write only, so -GroupId is the default path;
# a userId creator context returns 403 "User not authenticated" with these tokens.
#
#   .\upload-headbands.ps1 -KeyFile C:\path\oc.key
#   .\upload-headbands.ps1 -KeyFile C:\path\oc.key -Only CucumberBand,GoldBand
param(
    [string]$KeyFile = "",
    [string]$GroupId = "14583228",
    [string]$UserId = "",
    [string[]]$Only = @(),
    [int]$PollSeconds = 2,
    [int]$MaxPolls = 45
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fbxDir = Join-Path $here "fbx"
$outFile = Join-Path $here "asset-ids.json"

$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }

# Decode the JWT half of the key and refuse to start if it is already dead - these tokens
# last one hour and a stale one fails 12 times in a row with an unhelpful 401.
try {
    $i = $key.IndexOf("ZXlKa")
    if ($i -gt 0) {
        $jwt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.Substring($i)))
        $payload = $jwt.Split(".")[1].Replace("-", "+").Replace("_", "/")
        while ($payload.Length % 4) { $payload += "=" }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $left = [int]($claims.exp - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Write-Host ("key: ownerId {0}, {1} minutes left" -f $claims.ownerId, [math]::Round($left / 60))
        if ($left -le 30) { throw "Open Cloud key expires in $left seconds - paste a fresh one before uploading." }
    }
} catch {
    if ($_.Exception.Message -like "*expires in*") { throw }
    Write-Host "note: could not decode key expiry, continuing"
}

$order = @(
    @{ n = "Sweatband";     d = "Sweatband" },
    @{ n = "RedBandana";    d = "Red Bandana" },
    @{ n = "CamoBand";      d = "Camo Band" },
    @{ n = "CucumberBand";  d = "Cucumber Band" },
    @{ n = "StrawBand";     d = "Straw Band" },
    @{ n = "LeafCrown";     d = "Leaf Crown" },
    @{ n = "SteelBand";     d = "Steel Band" },
    @{ n = "CactusBand";    d = "Cactus Band" },
    @{ n = "FrostBand";     d = "Frost Band" },
    @{ n = "GoldBand";      d = "Gold Band" },
    @{ n = "LavaBand";      d = "Lava Band" },
    @{ n = "ChampionBand";  d = "Champion Band" }
)

$results = @{}
if (Test-Path $outFile) {
    try { (Get-Content $outFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $results[$_.Name] = $_.Value } } catch {}
}

function Save-Results {
    ($results | ConvertTo-Json -Depth 4) | Set-Content -Path $outFile -Encoding utf8
}

foreach ($item in $order) {
    $name = $item.n
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    if ($results[$name]) { Write-Host "skip $name (already have $($results[$name]))"; continue }

    $file = Join-Path $fbxDir "$name.fbx"
    if (-not (Test-Path $file)) { Write-Host "MISSING $file - skipping"; continue }

    $creator = if ($GroupId) { @{ groupId = $GroupId } } else { @{ userId = $UserId } }
    $request = @{
        assetType       = "Model"
        displayName     = $item.d + " Headband"
        description     = "Headband tier accessory for the cucumber game."
        creationContext = @{ creator = $creator }
    } | ConvertTo-Json -Compress -Depth 5

    $tmp = New-TemporaryFile
    $request | Set-Content -Path $tmp -Encoding ascii -NoNewline
    $resp = & curl.exe -sS -X POST "https://apis.roblox.com/assets/v1/assets" `
        -H "x-api-key: $key" `
        --form "request=<$tmp;type=application/json" `
        --form "fileContent=@`"$file`";type=model/fbx"
    Remove-Item $tmp -Force

    $body = ($resp -join "`n")
    $op = $null
    try { $op = ($body | ConvertFrom-Json).operationId } catch {}
    if (-not $op) { Write-Host "FAILED $name : $body"; continue }

    $assetId = $null
    for ($p = 0; $p -lt $MaxPolls; $p++) {
        Start-Sleep -Seconds $PollSeconds
        $raw = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$op" -H "x-api-key: $key"
        $r = $null
        try { $r = $raw | ConvertFrom-Json } catch { continue }
        if ($r.done) {
            if ($r.error) { Write-Host "FAILED $name : $raw"; break }
            $assetId = $r.response.assetId
            break
        }
    }
    if ($assetId) {
        $results[$name] = $assetId
        Save-Results
        Write-Host "OK   $name -> $assetId"
    } else {
        Write-Host "TIMEOUT $name (operation $op)"
    }
}

Save-Results
Write-Host ""
Write-Host "wrote $outFile"
$results.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Value) }

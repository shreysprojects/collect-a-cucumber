# Uploads every cucumber .fbx in .\fbx as a Roblox "Model" asset through Open Cloud and
# writes fbx\asset-ids.json next to them.  Same request shape as headbands\upload-headbands.ps1.
#
# It FIRES EVERY CREATE REQUEST FIRST and only then polls the operations, which is what
# made 32 prop uploads take ~3 minutes instead of ~20.
#
# The key family the user pastes is GROUP-write only: a userId creator context returns
# 403 "User not authenticated" with these tokens, so -GroupId is the default path.
# These keys live ONE HOUR - paste a fresh one right before running.
#
#   .\upload-cucumbers.ps1 -KeyFile C:\path\oc.key
#   .\upload-cucumbers.ps1 -KeyFile C:\path\oc.key -Only Cucumber,CucumberTree
#   .\upload-cucumbers.ps1 -KeyFile C:\path\oc.key -Force        # re-upload even if known
param(
    [string]$KeyFile = "",
    [string]$GroupId = "14583228",
    [string]$UserId = "",
    [string[]]$Only = @(),
    [switch]$Force,
    [int]$MinMinutes = 8,
    [int]$PollSeconds = 3,
    [int]$MaxPolls = 90
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fbxDir = Join-Path $here "fbx"
$outFile = Join-Path $fbxDir "asset-ids.json"

$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }

# Decode the JWT half of the key and refuse to start if it is already dead - a stale token
# fails N times in a row with an unhelpful 401.
try {
    $i = $key.IndexOf("ZXlKa")
    if ($i -gt 0) {
        $jwt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.Substring($i)))
        $payload = $jwt.Split(".")[1].Replace("-", "+").Replace("_", "/")
        while ($payload.Length % 4) { $payload += "=" }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $left = [int]($claims.exp - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Write-Host ("key: ownerId {0}, {1} minutes left" -f $claims.ownerId, [math]::Round($left / 60))
        if ($left -le ($MinMinutes * 60)) {
            throw "Open Cloud key has $([math]::Round($left/60)) minutes left - paste a fresh one before uploading."
        }
    }
} catch {
    if ($_.Exception.Message -like "*minutes left*") { throw }
    Write-Host "note: could not decode key expiry, continuing"
}

$results = @{}
if (Test-Path $outFile) {
    try {
        (Get-Content $outFile -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $results[$_.Name] = $_.Value }
    } catch {}
}
function Save-Results { ($results | ConvertTo-Json -Depth 4) | Set-Content -Path $outFile -Encoding utf8 }

$files = Get-ChildItem -Path $fbxDir -Filter *.fbx | Sort-Object Name
if ($Only.Count -gt 0) { $files = $files | Where-Object { $Only -contains $_.BaseName } }

$creator = if ($GroupId) { @{ groupId = $GroupId } } else { @{ userId = $UserId } }

# ---- pass 1: fire every create request ------------------------------------------------
$pending = @()
foreach ($f in $files) {
    $name = $f.BaseName
    if (-not $Force -and $results[$name]) { Write-Host "skip  $name (have $($results[$name]))"; continue }

    # displayName: "DesertSunDriedSlice" -> "Desert Sun Dried Slice"
    $pretty = [Regex]::Replace($name, '(?<!^)(?=[A-Z])', ' ')
    $request = @{
        assetType       = "Model"
        displayName     = $pretty
        description     = "Cucumber set model for the cucumber game."
        creationContext = @{ creator = $creator }
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
    if ($pending.Count -gt 0) { Save-Results }
}

foreach ($item in $pending) { Write-Host "TIMEOUT $($item.Name) (operation $($item.Op))" }

Save-Results
Write-Host ""
Write-Host "wrote $outFile  ($($results.Count) assets)"

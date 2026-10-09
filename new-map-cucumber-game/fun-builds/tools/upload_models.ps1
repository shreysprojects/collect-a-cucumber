param(
  [Parameter(Mandatory = $true)][string[]]$Keys,
  [Parameter(Mandatory = $true)][string]$KeyFile,
  [string]$GroupId = "14583228",   # Group Frenzy
  [int]$PollSeconds = 4,
  [int]$MaxPolls = 90
)
# Upload models\out\<Key>.fbx files as group-owned Roblox Model assets through Open Cloud (fun-builds, 2026-09-24).
# All create requests go out first, then every operation is polled in one loop. Results merge into
# models\out\asset-ids.json = {<Key>: {id, hash (parts_hash of the uploaded .mesh.json), uploaded}}.
# The key file lives in the session scratchpad only - never in the repo.
$fb = Split-Path -Parent $PSScriptRoot
$out = Join-Path $fb "models\out"
$key = ([IO.File]::ReadAllText($KeyFile)).Trim()
$idsPath = Join-Path $out "asset-ids.json"
$ids = @{}
if (Test-Path $idsPath) { (Get-Content $idsPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $ids[$_.Name] = $_.Value } }
$ops = @{}
foreach ($k in $Keys) {
  $fbx = Join-Path $out "$k.fbx"
  $meta = Join-Path $out "$k.mesh.json"
  if (-not (Test-Path $fbx) -or -not (Test-Path $meta)) { Write-Output "SKIP $k (no fbx/mesh.json)"; continue }
  $hash = (Get-Content $meta -Raw | ConvertFrom-Json).parts_hash
  $request = @{ assetType = "Model"; displayName = "FunBuild $k"; description = "New Map Cucumber Game build $k (fun-builds $hash)"; creationContext = @{ creator = @{ groupId = $GroupId } } } | ConvertTo-Json -Compress -Depth 5
  $tmp = New-TemporaryFile
  $request | Set-Content -Path $tmp -Encoding ascii -NoNewline
  $resp = & curl.exe -sS -w "`nHTTP %{http_code}" -X POST "https://apis.roblox.com/assets/v1/assets" -H "x-api-key: $key" --form "request=<$tmp;type=application/json" --form "fileContent=@`"$fbx`";type=model/fbx"
  Remove-Item $tmp -Force
  $text = ($resp -join "`n")
  $body = ($text -split "`nHTTP ")[0]
  $op = $null
  try { $op = ($body | ConvertFrom-Json).operationId } catch {}
  if ($op) { $ops[$k] = @{ Op = $op; Hash = $hash }; Write-Output "CREATE $k -> $op" } else { Write-Output "FAIL CREATE $k : $text" }
}
for ($i = 0; $i -lt $MaxPolls -and $ops.Count -gt 0; $i++) {
  Start-Sleep -Seconds $PollSeconds
  foreach ($k in @($ops.Keys)) {
    $raw = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$($ops[$k].Op)" -H "x-api-key: $key"
    try { $r = $raw | ConvertFrom-Json } catch { continue }
    if ($r.done) {
      if ($r.error) { Write-Output "FAIL $k : $raw" } else {
        $ids[$k] = [ordered]@{ id = [string]$r.response.assetId; hash = $ops[$k].Hash; uploaded = (Get-Date).ToString("s") }
        Write-Output "ASSET $k = $($r.response.assetId)"
      }
      $ops.Remove($k)
    }
  }
}
foreach ($k in $ops.Keys) { Write-Output "PENDING $k $($ops[$k].Op)" }
$json = $ids | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($idsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
"asset-ids.json: " + $ids.Count + " entries"

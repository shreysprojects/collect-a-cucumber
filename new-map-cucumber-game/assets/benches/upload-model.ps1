# Uploads one .fbx as a Roblox "Model" asset through Open Cloud (Assets API), polls the operation
# and prints "ASSET ID: <id>". The key comes from $env:ROBLOX_OPEN_CLOUD_API_KEY or -KeyFile
# (never commit a key file). The key needs the Assets API with READ + WRITE for the creator.
#   .\upload-model.ps1 -File Starter_Bench.fbx -Name "Bench Starter" -KeyFile C:\path\oc.key
param(
	[Parameter(Mandatory = $true)][string]$File,
	[Parameter(Mandatory = $true)][string]$Name,
	[string]$Description = "",
	[string]$UserId = "140977250",
	[string]$GroupId = "",
	[string]$KeyFile = "",
	[int]$PollSeconds = 3,
	[int]$MaxPolls = 60
)
$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }
if (-not (Test-Path $File)) { throw "Missing $File" }
$File = (Resolve-Path $File).Path
$request = @{ assetType = "Model"; displayName = $Name; description = $Description; creationContext = @{ creator = $(if ($GroupId) { @{ groupId = $GroupId } } else { @{ userId = $UserId } }) } } | ConvertTo-Json -Compress -Depth 5
$tmp = New-TemporaryFile
$request | Set-Content -Path $tmp -Encoding ascii -NoNewline
$resp = & curl.exe -sS -w "`nHTTP %{http_code}" -X POST "https://apis.roblox.com/assets/v1/assets" -H "x-api-key: $key" --form "request=<$tmp;type=application/json" --form "fileContent=@`"$File`";type=model/fbx"
Remove-Item $tmp -Force
$respText = ($resp -join "`n")
Write-Host "create: $respText"
$body = ($respText -split "`nHTTP ")[0]
$op = $null
try { $op = ($body | ConvertFrom-Json).operationId } catch {}
if (-not $op) { throw "no operationId (key lacks Assets Write, or request rejected)" }
for ($i = 0; $i -lt $MaxPolls; $i++) {
	Start-Sleep -Seconds $PollSeconds
	$raw = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$op" -H "x-api-key: $key"
	try { $r = $raw | ConvertFrom-Json } catch { Write-Host "poll: $raw"; continue }
	if ($r.done) {
		if ($r.error) { throw "operation failed: $raw" }
		$id = $r.response.assetId
		Write-Host "ASSET ID: $id"
		exit 0
	}
}
throw "operation $op still pending after $($PollSeconds * $MaxPolls) seconds"

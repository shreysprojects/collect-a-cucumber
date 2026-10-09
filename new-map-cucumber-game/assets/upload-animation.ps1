# Uploads assets\BenchPressAnimation.rbxm (a KeyframeSequence) to Roblox as an Animation asset
# through Open Cloud, polls the operation and prints the asset id.
# Needs an Open Cloud API key with "Assets API" READ + WRITE for user 140977250 in $env:ROBLOX_OPEN_CLOUD_API_KEY.
#   $env:ROBLOX_OPEN_CLOUD_API_KEY = "..." ; .\upload-animation.ps1
param(
	[string]$File = (Join-Path $PSScriptRoot "BenchPressAnimation.rbxm"),
	[string]$Name = "BenchPress",
	[string]$Description = "Bench press loop for the lie-down bench (2 s, looped)",
	[string]$UserId = "140977250"
)
$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY first" }
if (-not (Test-Path $File)) { throw "Missing $File" }
$request = @{ assetType = "Animation"; displayName = $Name; description = $Description; creationContext = @{ creator = @{ userId = $UserId } } } | ConvertTo-Json -Compress -Depth 5
$tmp = New-TemporaryFile
$request | Set-Content -Path $tmp -Encoding ascii -NoNewline
$resp = & curl.exe -sS -X POST "https://apis.roblox.com/assets/v1/assets" -H "x-api-key: $key" --form "request=<$tmp;type=application/json" --form "fileContent=@`"$File`";type=model/x-rbxm"
Remove-Item $tmp -Force
Write-Host "create: $resp"
$op = ($resp | ConvertFrom-Json).operationId
if (-not $op) { throw "no operationId (key lacks Assets Write, or request rejected)" }
for ($i = 0; $i -lt 40; $i++) {
	Start-Sleep -Seconds 3
	$r = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$op" -H "x-api-key: $key" | ConvertFrom-Json
	if ($r.done) {
		$id = $r.response.assetId
		Write-Host "ASSET ID: $id  ->  rbxassetid://$id"
		Write-Host "Now set workspace.Map.Lobby.Props.BenchPress.LieSeat attribute AnimationId = rbxassetid://$id"
		exit 0
	}
}
throw "operation $op still pending after 2 minutes"

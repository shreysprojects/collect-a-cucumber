# Uploads the two cucumber-collect KeyframeSequences (CucumberPickUp.rbxm / CucumberStruggle.rbxm,
# exported from ReplicatedStorage.Assets.Animations) to Roblox as Animation assets through Open Cloud,
# polls each operation and prints the asset ids plus the Studio one-liner that wires them up.
#
#   $env:ROBLOX_OPEN_CLOUD_API_KEY = "..." ; .\upload-animations.ps1        (or -KeyFile C:\path\oc.key)
#
# The key needs the Assets API with READ + WRITE for user 140977250 (create.roblox.com > Open Cloud >
# API Keys; add an IP rule for this PC). Never commit a key.
#   -GroupId <id>   publish under a group instead of the user (the key must have Assets Read + Write
#                   for that group; a group-owned animation only plays in group-owned experiences)
param(
	[string]$KeyFile = "",
	[string]$UserId = "140977250",
	[string]$GroupId = "",
	[string[]]$Names = @("CucumberPickUp", "CucumberStruggle")
)
$here = $PSScriptRoot
$key = $env:ROBLOX_OPEN_CLOUD_API_KEY
if (-not $key -and $KeyFile) { $key = ([IO.File]::ReadAllText($KeyFile)).Trim() }
if (-not $key) { throw "Set ROBLOX_OPEN_CLOUD_API_KEY or pass -KeyFile" }
$creator = if ($GroupId) { @{ groupId = $GroupId } } else { @{ userId = $UserId } }

$descriptions = @{
	CucumberPickUp   = "Bend down, grip the cucumber with both hands, lift it to the chest and stand up (1.4 s, one-shot)"
	CucumberStruggle = "Tug-of-war loop: gripping the cucumber, hips-back pull with straight arms, slip back (1 s, looped)"
	CucumberFall     = "Heavy-carry stumble: trip, face-plant dropping the cucumber, push up and stand (2.4 s, one-shot)"
}
$ids = @{}
foreach ($name in $Names) {
	$file = Join-Path $here "$name.rbxm"
	if (-not (Test-Path $file)) { throw "Missing $file (export the KeyframeSequence from Studio first)" }
	$request = @{ assetType = "Animation"; displayName = $name; description = $descriptions[$name]; creationContext = @{ creator = $creator } } | ConvertTo-Json -Compress -Depth 5
	$tmp = New-TemporaryFile
	$request | Set-Content -Path $tmp -Encoding ascii -NoNewline
	$resp = & curl.exe -sS -X POST "https://apis.roblox.com/assets/v1/assets" -H "x-api-key: $key" --form "request=<$tmp;type=application/json" --form "fileContent=@`"$file`";type=model/x-rbxm"
	Remove-Item $tmp -Force
	Write-Host "create $name -> $resp"
	$op = ($resp | ConvertFrom-Json).operationId
	if (-not $op) { throw "no operationId for $name (key lacks Assets Write, or the request was rejected)" }
	$done = $false
	for ($i = 0; $i -lt 40 -and -not $done; $i++) {
		Start-Sleep -Seconds 3
		$r = & curl.exe -sS "https://apis.roblox.com/assets/v1/operations/$op" -H "x-api-key: $key" | ConvertFrom-Json
		if ($r.done) {
			$ids[$name] = [string]$r.response.assetId
			Write-Host "ASSET ID $name = $($ids[$name])"
			$done = $true
		}
	}
	if (-not $done) { throw "operation $op for $name still pending after 2 minutes" }
}
Write-Host ""
Write-Host "Paste this into the Studio command bar to wire the ids up:"
$parts = @()
foreach ($name in $Names) { $parts += "game.ReplicatedStorage.Assets.Animations.$name.AnimationId = 'rbxassetid://$($ids[$name])'" }
Write-Host ($parts -join "; ")

param([string[]]$Only = @())
# Stage every behaviour module + stand-alone script into FB\stage (flat names) with _behaviours.json for
# install\install_behaviours.lua, syntax-checking each file first (fun-builds, 2026-09-24).
$fb = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $fb "stage"
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $fb "install\install_behaviours.lua") $stage -Force
$list = @()
foreach ($kind in @("server", "client")) {
  $dir = Join-Path $fb "src\behaviours\$kind"
  if (-not (Test-Path $dir)) { continue }
  foreach ($f in Get-ChildItem $dir -Filter *.lua) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { continue }
    $flat = ($(if ($kind -eq "server") { "srv__" } else { "cli__" })) + $f.Name
    Copy-Item $f.FullName (Join-Path $stage $flat) -Force
    $list += [ordered]@{ File = $flat; Kind = $kind; Name = $name }
  }
}
$scripts = @(
  @{ Src = "src\DefenceFXClient.client.lua"; Name = "DefenceFXClient"; Parent = "StarterPlayer.StarterPlayerScripts"; Class = "LocalScript" },
  @{ Src = "src\DefenceStatsClient.client.lua"; Name = "DefenceStatsClient"; Parent = "StarterPlayer.StarterPlayerScripts"; Class = "LocalScript" }
)
foreach ($s in $scripts) {
  $p = Join-Path $fb $s.Src
  if ((Test-Path $p) -and ($Only.Count -eq 0 -or $Only -contains $s.Name)) {
    $flat = "scr__" + [IO.Path]::GetFileName($p)
    Copy-Item $p (Join-Path $stage $flat) -Force
    $list += [ordered]@{ File = $flat; Kind = "script"; Name = $s.Name; Parent = $s.Parent; Class = $s.Class }
  }
}
$json = ConvertTo-Json -InputObject @($list) -Depth 4
[IO.File]::WriteAllText((Join-Path $stage "_behaviours.json"), $json, (New-Object System.Text.UTF8Encoding($false)))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "luacheck.ps1") (Join-Path $stage "*__*.lua")
"staged " + $list.Count + " files"

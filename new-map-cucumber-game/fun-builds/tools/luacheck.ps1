param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
# Luau SYNTAX check without running anything Roblox-specific (fun-builds, 2026-09-24).
# Each file is copied with "do return end" in front (so it compiles in full but executes nothing) and run
# through the official Luau CLI (rokit: luau-lang/luau). Prints "OK <file>" or "FAIL <file>: <error>".
#   powershell -File tools\luacheck.ps1 src\FunBuildKit.lua src\behaviours\server\*.lua
$luau = "C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
$fail = 0
$expanded = @()
foreach ($f in $Files) { $expanded += (Get-ChildItem -Path $f -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
foreach ($file in $expanded) {
  $tmp = Join-Path $env:TEMP ("luacheck_" + [guid]::NewGuid().ToString("N") + ".luau")
  $src = [System.IO.File]::ReadAllText($file)
  # the source becomes the body of a never-called function: it is compiled in full (register / upvalue limits
  # included - a bare "do return end" prefix let the compiler drop the dead code and missed "Out of local
  # registers" on 2026-09-24) but nothing Roblox-specific runs
  [System.IO.File]::WriteAllText($tmp, "local function __luacheck(...)`n" + $src + "`nend`n", (New-Object System.Text.UTF8Encoding($false)))
  $out = & $luau $tmp 2>&1 | Out-String
  Remove-Item $tmp -ErrorAction SilentlyContinue
  if ($LASTEXITCODE -ne 0 -or $out.Trim().Length -gt 0) {
    $fail++
    # line numbers are off by one (the prefix line): report them corrected
    $eval = [System.Text.RegularExpressions.MatchEvaluator] { param($m) ":" + ([int]$m.Groups[1].Value - 1) + ":" }
    $first = ($out -split "`n" | Where-Object { $_ -match "luacheck_.*\.luau:\d+:" } | Select-Object -First 1)
    if (-not $first) { $first = $out.Trim() }
    $msg = [regex]::Replace($first.Trim(), ":(\d+):", $eval) -replace "^.*luacheck_[0-9a-f]+\.luau", "line"
    Write-Output ("FAIL " + $file + ": " + $msg)
  } else {
    Write-Output ("OK " + $file)
  }
}
if ($fail -gt 0) { exit 1 } else { exit 0 }

# keep-awake.ps1: keeps Windows from sleeping (and the display from switching off) while it runs, the way
# a video player does - SetThreadExecutionState, no power settings are changed. It ends on its own after
# -Hours (default 6); closing the window or stopping the powershell process ends it early and the normal
# sleep timers apply again.
#   powershell -File keep-awake.ps1 -Hours 6
param([int]$Hours = 6)
Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true)] public static extern uint SetThreadExecutionState(uint esFlags);'
# decimal on purpose: Windows PowerShell 5.1 reads 0x80000000 as a negative int32 and refuses the uint32 cast
$ES_CONTINUOUS = [uint32]2147483648
$ES_SYSTEM_REQUIRED = [uint32]1
$ES_DISPLAY_REQUIRED = [uint32]2
$flags = [uint32]($ES_CONTINUOUS + $ES_SYSTEM_REQUIRED + $ES_DISPLAY_REQUIRED)
$result = [Win32.Power]::SetThreadExecutionState($flags)
if ($result -eq 0) { Write-Host "keep-awake: SetThreadExecutionState failed"; exit 1 }
Write-Host ("keep-awake: sleep and display-off blocked until {0} (Ctrl+C to stop)" -f (Get-Date).AddHours($Hours).ToString("HH:mm"))
Start-Sleep -Seconds ($Hours * 3600)
[void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS)
Write-Host "keep-awake: done, normal sleep timers apply again"

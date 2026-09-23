param([int]$Port = 8768, [string]$Root = "C:\Users\shrey\AppData\Local\Temp\claude\C--Users-shrey-OneDrive-Documents-RobloxGames\6fe56255-290c-431a-9d96-168d6bd843fe\scratchpad\shots", [int]$Minutes = 40)
# Loopback receiver for raw screenshot pixels posted from Roblox Studio (plugin-context HttpService).
#   POST http://127.0.0.1:<Port>/<name>.b64            -> overwrite $Root\<name>.b64 with the body text
#   POST http://127.0.0.1:<Port>/<name>.b64?append=1   -> append the body text
#   GET  http://127.0.0.1:<Port>/__stop                -> stop
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
  $ctxTask = $listener.GetContextAsync()
  while (-not $ctxTask.Wait(1000)) { if ((Get-Date) -ge $deadline) { break } }
  if (-not $ctxTask.IsCompleted) { continue }
  $ctx = $ctxTask.Result
  $name = [System.IO.Path]::GetFileName($ctx.Request.Url.LocalPath)
  if ($name -eq "__stop") { $ctx.Response.StatusCode = 200; $ctx.Response.Close(); break }
  if ($ctx.Request.HttpMethod -eq "POST" -and $name) {
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::ASCII)
    $body = $reader.ReadToEnd()
    $path = Join-Path $Root $name
    $append = $ctx.Request.QueryString["append"] -eq "1"
    if ($append) { [System.IO.File]::AppendAllText($path, $body) } else { [System.IO.File]::WriteAllText($path, $body) }
    $msg = [System.Text.Encoding]::UTF8.GetBytes("ok $name +$($body.Length) chars, total $((Get-Item $path).Length)")
    $ctx.Response.StatusCode = 200
    $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
  } else {
    $ctx.Response.StatusCode = 400
  }
  $ctx.Response.Close()
}
$listener.Stop()

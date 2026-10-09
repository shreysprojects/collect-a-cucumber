param([int]$Port = 8765, [string]$Root = "C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake", [int]$Minutes = 90)
# Tiny loopback file server so Roblox Studio (plugin-context HttpService) can pull the generated
# pet geometry modules straight from disk. Serves only files inside $Root, only on 127.0.0.1.
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
  $path = Join-Path $Root $name
  if ($name -eq "__stop") { $ctx.Response.StatusCode = 200; $ctx.Response.Close(); break }
  if ($name -and (Test-Path $path)) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $ctx.Response.ContentType = "text/plain; charset=utf-8"
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $ctx.Response.StatusCode = 404
  }
  $ctx.Response.Close()
}
$listener.Stop()

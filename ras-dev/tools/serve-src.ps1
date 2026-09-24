param([int]$Port = 8797, [string]$Root = "C:\Users\shrey\RAS\src", [int]$Minutes = 60)
# Loopback file server for pushing repo sources into Studio when the Rojo plugin is disconnected:
# an edit-mode execute_luau does HttpService:GetAsync("http://127.0.0.1:8797/<path under src>")
# and writes the body into the ModuleScript's Source. Serves only files inside $Root, only on
# 127.0.0.1, and stops on GET /__stop or after $Minutes.
$rootFull = [System.IO.Path]::GetFullPath($Root)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "serve-src: http://127.0.0.1:$Port/ -> $rootFull (until $((Get-Date).AddMinutes($Minutes).ToString('HH:mm')))"
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
  $ctxTask = $listener.GetContextAsync()
  while (-not $ctxTask.Wait(1000)) { if ((Get-Date) -ge $deadline) { break } }
  if (-not $ctxTask.IsCompleted) { continue }
  $ctx = $ctxTask.Result
  $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
  if ($rel -eq "__stop") { $ctx.Response.StatusCode = 200; $ctx.Response.Close(); break }
  $path = [System.IO.Path]::GetFullPath((Join-Path $rootFull ($rel -replace '/', '\')))
  if ($rel -and $path.StartsWith($rootFull) -and (Test-Path $path -PathType Leaf)) {
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

param([int]$Port = 8766, [string]$Root = "C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake", [int]$Minutes = 30)
# Loopback companion to serve.ps1: Roblox Studio (plugin-context HttpService:PostAsync) POSTs a
# script's Source to http://127.0.0.1:<Port>/<FileName> and it lands as $Root\<FileName> (UTF-8, no
# BOM, CRLF line endings like the other mirrors). Only bare file names, only 127.0.0.1.
#   Studio side:  HttpService:PostAsync("http://127.0.0.1:8766/Foo.server.lua", script.Source, Enum.HttpContentType.TextPlain)
#   GET /__stop ends the listener.
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
$deadline = (Get-Date).AddMinutes($Minutes)
$utf8 = New-Object System.Text.UTF8Encoding($false)
while ((Get-Date) -lt $deadline) {
  $ctxTask = $listener.GetContextAsync()
  while (-not $ctxTask.Wait(1000)) { if ((Get-Date) -ge $deadline) { break } }
  if (-not $ctxTask.IsCompleted) { continue }
  $ctx = $ctxTask.Result
  $name = [System.IO.Path]::GetFileName($ctx.Request.Url.LocalPath)
  if ($name -eq "__stop") { $ctx.Response.StatusCode = 200; $ctx.Response.Close(); break }
  if ($ctx.Request.HttpMethod -eq "POST" -and $name) {
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $body = $reader.ReadToEnd()
    $body = $body -replace "`r?`n", "`r`n"
    $path = Join-Path $Root $name
    [System.IO.File]::WriteAllText($path, $body, $utf8)
    $msg = [System.Text.Encoding]::UTF8.GetBytes("wrote $name ($($body.Length) chars)")
    $ctx.Response.StatusCode = 200
    $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
  } else {
    $ctx.Response.StatusCode = 400
  }
  $ctx.Response.Close()
}
$listener.Stop()

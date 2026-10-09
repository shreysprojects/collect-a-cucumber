param([string]$Root = (Join-Path $PSScriptRoot "shots"))
# Turns every <name>.b64 in $Root into <name>.png.
#   <name>.b64                 base64 of a PNG file (StudioCaptureService PNG format)
#   <name>_<w>x<h>.rgba.b64    base64 of raw RGBA8 pixels -> encoded to PNG with System.Drawing
Add-Type -AssemblyName System.Drawing
Get-ChildItem $Root -Filter *.b64 | ForEach-Object {
  $txt = [System.IO.File]::ReadAllText($_.FullName).Trim()
  $bytes = [Convert]::FromBase64String($txt)
  if ($_.Name -match '^(.*)_(\d+)x(\d+)\.rgba\.b64$') {
    $name = $Matches[1]; $w = [int]$Matches[2]; $h = [int]$Matches[3]
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    # RGBA -> BGRA
    for ($i = 0; $i -lt $bytes.Length; $i += 4) { $t = $bytes[$i]; $bytes[$i] = $bytes[$i+2]; $bytes[$i+2] = $t }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $bmp.UnlockBits($data)
    $out = Join-Path $Root "$name.png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  } else {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $out = Join-Path $Root "$name.png"
    [System.IO.File]::WriteAllBytes($out, $bytes)
  }
  $img = [System.Drawing.Image]::FromFile($out)
  Write-Output ("{0}: {1} bytes, {2}x{3}" -f (Split-Path $out -Leaf), (Get-Item $out).Length, $img.Width, $img.Height)
  $img.Dispose()
}

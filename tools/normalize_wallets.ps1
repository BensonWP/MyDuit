# One-off: normalisasi PNG wallet ke kanvas square 96x96 (contain, transparan).
# Sumber aslinya acak-acakan (32px s/d 1000px, non-square) — display maksimal
# di UI cuma 48px, jadi 96 = 2x untuk DPI tinggi. Jalankan dari root repo:
#   powershell -File tools\normalize_wallets.ps1
Add-Type -AssemblyName System.Drawing

$size = 96
$dir = Join-Path $PSScriptRoot '..\assets\wallets'

foreach ($f in Get-ChildItem (Join-Path $dir '*.png')) {
  $img = [System.Drawing.Image]::FromFile($f.FullName)

  $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

  $scale = [Math]::Min($size / $img.Width, $size / $img.Height)
  $w = [Math]::Max(1, [int]($img.Width * $scale))
  $h = [Math]::Max(1, [int]($img.Height * $scale))
  $x = [int](($size - $w) / 2)
  $y = [int](($size - $h) / 2)

  # TileFlipXY: hindari artifact tepi gelap khas GDI+ saat downscale.
  $attr = New-Object System.Drawing.Imaging.ImageAttributes
  $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)

  $g.Dispose()
  $attr.Dispose()
  $img.Dispose()

  $tmp = "$($f.FullName).tmp"
  $canvas.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Dispose()
  Move-Item -Force $tmp $f.FullName
  "OK  $($f.Name)"
}

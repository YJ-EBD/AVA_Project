param(
  [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

function New-Color($hex) {
  return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function ConvertFrom-CodePoints([int[]]$Codes) {
  return -join ($Codes | ForEach-Object { [char]$_ })
}

function New-FontFromCandidates([string[]]$Families, [float]$Size, [System.Drawing.FontStyle]$Style) {
  foreach ($family in $Families) {
    try {
      return [System.Drawing.Font]::new($family, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
    } catch {
    }
  }

  return [System.Drawing.Font]::new([System.Drawing.FontFamily]::GenericSansSerif, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Use-Graphics($Bitmap) {
  $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  return $graphics
}

function Draw-AvaMark($Graphics, [System.Drawing.RectangleF]$Bounds, [System.Drawing.Color]$LineColor, [float]$StrokeWidth) {
  $pen = [System.Drawing.Pen]::new($LineColor, $StrokeWidth)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

  $points = @(
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.04, $Bounds.Top + $Bounds.Height * 0.84),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.25, $Bounds.Top + $Bounds.Height * 0.04),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.45, $Bounds.Top + $Bounds.Height * 0.66),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.50, $Bounds.Top + $Bounds.Height * 0.72),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.55, $Bounds.Top + $Bounds.Height * 0.66),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.75, $Bounds.Top + $Bounds.Height * 0.04),
    [System.Drawing.PointF]::new($Bounds.Left + $Bounds.Width * 0.96, $Bounds.Top + $Bounds.Height * 0.84)
  )

  $Graphics.DrawLines($pen, $points)
  $pen.Dispose()

  $dotSize = [Math]::Max(4.0, $Bounds.Width * 0.055)
  $purple = [System.Drawing.SolidBrush]::new((New-Color '#7B61FF'))
  $blue = [System.Drawing.SolidBrush]::new((New-Color '#2F6BFF'))
  $Graphics.FillEllipse($purple, $Bounds.Left + $Bounds.Width * 0.26 - $dotSize / 2, $Bounds.Top + $Bounds.Height * 0.43 - $dotSize / 2, $dotSize, $dotSize)
  $Graphics.FillEllipse($blue, $Bounds.Left + $Bounds.Width * 0.74 - $dotSize / 2, $Bounds.Top + $Bounds.Height * 0.43 - $dotSize / 2, $dotSize, $dotSize)
  $purple.Dispose()
  $blue.Dispose()
}

function Draw-Waves($Graphics, [int]$Width, [int]$Height) {
  for ($i = 0; $i -lt 9; $i++) {
    $alpha = 58 - ($i * 4)
    $color = [System.Drawing.Color]::FromArgb([Math]::Max(18, $alpha), 123, 97, 255)
    $pen = [System.Drawing.Pen]::new($color, 1.35)
    $points = New-Object System.Collections.Generic.List[System.Drawing.PointF]

    for ($x = -40; $x -le $Width + 40; $x += 18) {
      $progress = $x / [double]$Width
      $y = $Height * (0.70 + $i * 0.018) + [Math]::Sin(($progress * 2.4 + $i * 0.12) * [Math]::PI * 2) * 18
      $points.Add([System.Drawing.PointF]::new($x, [float]$y))
    }

    $Graphics.DrawCurve($pen, $points.ToArray(), 0.48)
    $pen.Dispose()
  }
}

function Save-Png($Bitmap, [string]$Path) {
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }
  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-AvaIconBitmap([int]$Size) {
  $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = Use-Graphics $bitmap
  $rect = [System.Drawing.Rectangle]::new(0, 0, $Size, $Size)
  $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, (New-Color '#0F1530'), (New-Color '#1E2A5B'), 45)
  $graphics.FillRectangle($background, $rect)
  $background.Dispose()

  Draw-Waves $graphics $Size $Size
  Draw-AvaMark $graphics ([System.Drawing.RectangleF]::new($Size * 0.18, $Size * 0.17, $Size * 0.64, $Size * 0.28)) ([System.Drawing.Color]::White) ([Math]::Max(2.2, $Size * 0.026))

  $font = New-FontFromCandidates @('Segoe UI Black', 'Arial Black', 'Segoe UI') ($Size * 0.235) ([System.Drawing.FontStyle]::Bold)
  $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  $center = [System.Drawing.StringFormat]::new()
  $center.Alignment = [System.Drawing.StringAlignment]::Center
  $center.LineAlignment = [System.Drawing.StringAlignment]::Center
  $graphics.DrawString('AVA', $font, $white, [System.Drawing.RectangleF]::new(0, $Size * 0.48, $Size, $Size * 0.22), $center)

  if ($Size -ge 128) {
    $subtitle = New-FontFromCandidates @('Segoe UI Semibold', 'Segoe UI') ($Size * 0.045) ([System.Drawing.FontStyle]::Regular)
    $graphics.DrawString('Abbas Vanguard AI', $subtitle, $white, [System.Drawing.RectangleF]::new(0, $Size * 0.70, $Size, $Size * 0.08), $center)
    $subtitle.Dispose()
  }

  $center.Dispose()
  $white.Dispose()
  $font.Dispose()
  $graphics.Dispose()
  return $bitmap
}

function New-BannerBitmap([int]$Width, [int]$Height) {
  $bitmap = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = Use-Graphics $bitmap
  $rect = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
  $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, (New-Color '#0F1530'), (New-Color '#162C4D'), 0)
  $graphics.FillRectangle($background, $rect)
  $background.Dispose()
  Draw-Waves $graphics $Width $Height

  $divider = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(55, 255, 255, 255), 1)
  $graphics.DrawLine($divider, 300, 42, 300, $Height - 42)
  $divider.Dispose()

  Draw-AvaMark $graphics ([System.Drawing.RectangleF]::new(54, 34, 178, 72)) ([System.Drawing.Color]::White) 6.5

  $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  $muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(210, 230, 235, 246))
  $purple = [System.Drawing.SolidBrush]::new((New-Color '#7B61FF'))
  $aiBlue = [System.Drawing.SolidBrush]::new((New-Color '#2F6BFF'))
  $titleFont = New-FontFromCandidates @('Segoe UI Black', 'Arial Black', 'Segoe UI') 54 ([System.Drawing.FontStyle]::Bold)
  $brandFont = New-FontFromCandidates @('Segoe UI Semibold', 'Segoe UI') 18 ([System.Drawing.FontStyle]::Regular)
  $copyFont = New-FontFromCandidates @('Malgun Gothic', 'Segoe UI') 32 ([System.Drawing.FontStyle]::Bold)
  $smallFont = New-FontFromCandidates @('Malgun Gothic', 'Segoe UI') 17 ([System.Drawing.FontStyle]::Regular)
  $formatLeft = [System.Drawing.StringFormat]::new()
  $formatLeft.Alignment = [System.Drawing.StringAlignment]::Near
  $formatLeft.LineAlignment = [System.Drawing.StringAlignment]::Near
  $slogan = ConvertFrom-CodePoints @(
    0xC55E, 0xC120, 0x20, 0xAE30, 0xC220, 0xB85C, 0x2C, 0x0A,
    0xB354, 0x20, 0xB098, 0xC740, 0x20, 0xBBF8, 0xB798, 0xB97C,
    0x20, 0xB9CC, 0xB4ED, 0xB2C8, 0xB2E4, 0x2E
  )

  $graphics.DrawString('AVA', $titleFont, $white, [System.Drawing.RectangleF]::new(68, 106, 160, 62), $formatLeft)
  $graphics.DrawString('Abbas ', $brandFont, $muted, [System.Drawing.PointF]::new(62, 174))
  $graphics.DrawString('Vanguard', $brandFont, $purple, [System.Drawing.PointF]::new(123, 174))
  $graphics.DrawString(' AI', $brandFont, $aiBlue, [System.Drawing.PointF]::new(217, 174))

  $graphics.DrawString($slogan, $copyFont, $white, [System.Drawing.RectangleF]::new(336, 54, 520, 86), $formatLeft)
  $graphics.DrawString('AVA Internal Messenger  |  Abbas Vanguard AI', $smallFont, $muted, [System.Drawing.RectangleF]::new(340, 158, 560, 30), $formatLeft)

  $tagPen = [System.Drawing.Pen]::new((New-Color '#7B61FF'), 2)
  $graphics.DrawLine($tagPen, 342, 204, 568, 204)
  $tagPen.Dispose()

  $formatLeft.Dispose()
  $smallFont.Dispose()
  $copyFont.Dispose()
  $brandFont.Dispose()
  $titleFont.Dispose()
  $aiBlue.Dispose()
  $purple.Dispose()
  $muted.Dispose()
  $white.Dispose()
  $graphics.Dispose()
  return $bitmap
}

function Save-Ico([string]$Path, [int[]]$Sizes) {
  $entries = @()

  foreach ($size in $Sizes) {
    $bitmap = New-AvaIconBitmap $size
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $entries += [PSCustomObject]@{
      Size = $size
      Bytes = $stream.ToArray()
    }
    $stream.Dispose()
    $bitmap.Dispose()
  }

  $directory = Split-Path -Parent $Path
  if (-not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }

  $file = [System.IO.File]::Create($Path)
  $writer = [System.IO.BinaryWriter]::new($file)
  $writer.Write([UInt16]0)
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]$entries.Count)

  $offset = 6 + ($entries.Count * 16)
  foreach ($entry in $entries) {
    $icoSizeByte = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
    $writer.Write([byte]$icoSizeByte)
    $writer.Write([byte]$icoSizeByte)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$entry.Bytes.Length)
    $writer.Write([UInt32]$offset)
    $offset += $entry.Bytes.Length
  }

  foreach ($entry in $entries) {
    $writer.Write($entry.Bytes)
  }

  $writer.Dispose()
  $file.Dispose()
}

$assetsDir = Join-Path $ProjectRoot 'assets\images'
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

$banner = New-BannerBitmap 1000 260
Save-Png $banner (Join-Path $assetsDir 'ava_bottom_banner.png')
$banner.Dispose()

$sourceIcon = New-AvaIconBitmap 1024
Save-Png $sourceIcon (Join-Path $assetsDir 'ava_app_icon.png')
$sourceIcon.Dispose()

Save-Ico (Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico') @(16, 24, 32, 48, 64, 128, 256)

$androidIcons = @{
  'android\app\src\main\res\mipmap-mdpi\ic_launcher.png' = 48
  'android\app\src\main\res\mipmap-hdpi\ic_launcher.png' = 72
  'android\app\src\main\res\mipmap-xhdpi\ic_launcher.png' = 96
  'android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png' = 144
  'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png' = 192
}

foreach ($entry in $androidIcons.GetEnumerator()) {
  $bitmap = New-AvaIconBitmap $entry.Value
  Save-Png $bitmap (Join-Path $ProjectRoot $entry.Key)
  $bitmap.Dispose()
}

$iosIconDir = Join-Path $ProjectRoot 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
if (Test-Path $iosIconDir) {
  Get-ChildItem -Path $iosIconDir -Filter 'Icon-App-*.png' | ForEach-Object {
    if ($_.Name -match 'Icon-App-([0-9.]+)x[0-9.]+@([0-9])x\.png') {
      $size = [int][Math]::Round(([double]$Matches[1]) * ([double]$Matches[2]))
      $bitmap = New-AvaIconBitmap $size
      Save-Png $bitmap $_.FullName
      $bitmap.Dispose()
    }
  }
}

Write-Host "Generated AVA brand assets in $ProjectRoot"

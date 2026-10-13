# Gen logo NixxToon: N gradient + 2 garis kecepatan amber.
# Run: powershell -ExecutionPolicy Bypass -File tool/gen_icon.ps1
Add-Type -AssemblyName System.Drawing

$BG = [System.Drawing.Color]::FromArgb(15, 15, 26)
$P1 = [System.Drawing.Color]::FromArgb(124, 58, 237)
$P2 = [System.Drawing.Color]::FromArgb(6, 182, 212)
$AM = [System.Drawing.Color]::FromArgb(255, 178, 36)

function New-NRegion {
  param([int]$dx, [int]$dy, [int]$size)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $fam = New-Object System.Drawing.FontFamily('Arial Black')
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF($dx, $dy, 1024, $size)
  $path.AddString('N', $fam, 0, $size * 0.72, $rect, $fmt)
  $r = New-Object System.Drawing.Region($path)
  $path.Dispose(); $fam.Dispose(); $fmt.Dispose()
  return $r
}

function Draw-Logo {
  param($g, [bool]$mono)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gradRect = New-Object System.Drawing.RectangleF(232, 232, 560, 560)
  $brush = if ($mono) {
    New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  } else {
    New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      $gradRect, $P1, $P2, 45.0)
  }
  # N sedikit ke kiri biar ada ruang garis kecepatan
  $region = New-NRegion -dx -60 -dy 200 -size 640
  $g.FillRegion($brush, $region)
  $region.Dispose()
  $barBrush = if ($mono) {
    New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  } else {
    New-Object System.Drawing.SolidBrush($AM)
  }
  # 2 garis kecepatan horizontal di kanan N
  $g.FillRoundedRectangle($barBrush, 700, 440, 170, 36, 18)
  $g.FillRoundedRectangle($barBrush, 700, 500, 110, 36, 18)
  $brush.Dispose(); $barBrush.Dispose()
}

# Greatest compatibility: manual rounded rect (FillRoundedRectangle .NET 8+ tidak ada di Framework)
# -> pakai FillRectangle biasa. (di-override di bawah)
function Draw-LogoSimple {
  param($g, [bool]$mono)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gradRect = New-Object System.Drawing.RectangleF(232, 232, 560, 560)
  $brush = if ($mono) {
    New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  } else {
    New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      $gradRect, $P1, $P2, 45.0)
  }
  $region = New-NRegion -dx -60 -dy 200 -size 640
  $g.FillRegion($brush, $region)
  $region.Dispose()
  $barBrush = if ($mono) {
    New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  } else {
    New-Object System.Drawing.SolidBrush($AM)
  }
  $g.FillRectangle($barBrush, 700, 440, 170, 36)
  $g.FillRectangle($barBrush, 700, 500, 110, 36)
  $brush.Dispose(); $barBrush.Dispose()
}

New-Item -ItemType Directory -Path 'assets\icon' -Force | Out-Null

# foreground adaptif (transparan)
$bmp = New-Object System.Drawing.Bitmap(1024, 1024)
$g = [System.Drawing.Graphics]::FromImage($bmp)
Draw-LogoSimple $g $false
$g.Dispose()
$bmp.Save('assets\icon\nixx_fg.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# full-bleed legacy (bg gelap)
$bmp = New-Object System.Drawing.Bitmap(1024, 1024)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear($BG)
Draw-LogoSimple $g $false
$g.Dispose()
$bmp.Save('assets\icon\nixx_full.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# monokrom (themed icon)
$bmp = New-Object System.Drawing.Bitmap(1024, 1024)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
Draw-LogoSimple $g $true
$g.Dispose()
$bmp.Save('assets\icon\nixx_mono.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output 'icons written'

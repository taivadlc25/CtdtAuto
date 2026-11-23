Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\taivadlc\.gemini\antigravity\brain\75092598-07dd-44cb-be87-c86258150c68\ctdt_auto_app_icon_1795417090424.jpg"
$destPng = "d:\Game\AUTOCTDT\CtdtLogo.png"
$icoPath = "d:\Game\AUTOCTDT\CtdtAuto.ico"

# 1. Load source image and create clean transparent circular badge
$srcImg = [System.Drawing.Image]::FromFile($srcPath)
$w = $srcImg.Width
$h = $srcImg.Height

$badge = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($badge)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# Circular clip mask centered at (w/2, h/2) with radius 495 (offset 17px)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$clipRect = New-Object System.Drawing.RectangleF (17), (17), ($w - 34), ($h - 34)
$path.AddEllipse($clipRect)

$g.SetClip($path)
$g.DrawImage($srcImg, 0, 0, $w, $h)
$g.ResetClip()
$path.Dispose()
$g.Dispose()
$srcImg.Dispose()

$badge.Save($destPng, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved transparent circular logo to $destPng"

# 2. Build multi-size Windows .ico with proper DIB structure
$sizes = @(256, 128, 64, 48, 32, 16)
$entriesData = @()

foreach ($sz in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gb = [System.Drawing.Graphics]::FromImage($bmp)
    $gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gb.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gb.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gb.DrawImage($badge, 0, 0, $sz, $sz)
    $gb.Dispose()

    if ($sz -eq 256) {
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray()
        $ms.Dispose()

        $entriesData += [PSCustomObject]@{
            Width = [byte]0 # 256
            Height = [byte]0
            Data = $bytes
        }
    } else {
        $ms = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter $ms

        # BITMAPINFOHEADER (40 bytes)
        $bw.Write([uint32]40)              # biSize
        $bw.Write([int32]$sz)              # biWidth
        $bw.Write([int32]($sz * 2))        # biHeight (double height for XOR + AND masks)
        $bw.Write([uint16]1)               # biPlanes
        $bw.Write([uint16]32)              # biBitCount
        $bw.Write([uint32]0)               # biCompression = BI_RGB
        $bw.Write([uint32]($sz * $sz * 4)) # biSizeImage
        $bw.Write([int32]0)                # biXPelsPerMeter
        $bw.Write([int32]0)                # biYPelsPerMeter
        $bw.Write([uint32]0)               # biClrUsed
        $bw.Write([uint32]0)               # biClrImportant

        # Lock bits for raw BGRA
        $rect = New-Object System.Drawing.Rectangle 0, 0, $sz, $sz
        $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = [Math]::Abs($bd.Stride)
        $pixels = New-Object byte[] ($stride * $sz)
        [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $pixels, 0, $pixels.Length)
        $bmp.UnlockBits($bd)

        # Bottom-up XOR mask (BGRA)
        for ($y = $sz - 1; $y -ge 0; $y--) {
            $offset = $y * $stride
            $bw.Write($pixels, $offset, ($sz * 4))
        }

        # Bottom-up AND mask (1bpp, row aligned to 32 bits / 4 bytes)
        $andRowBytes = [int][Math]::Ceiling($sz / 32.0) * 4
        $andMask = New-Object byte[] ($andRowBytes * $sz)
        for ($y = 0; $y -lt $sz; $y++) {
            $srcY = ($sz - 1 - $y) # bottom up
            for ($x = 0; $x -lt $sz; $x++) {
                $alpha = $pixels[$srcY * $stride + $x * 4 + 3]
                if ($alpha -lt 128) {
                    $byteIdx = ($y * $andRowBytes) + [int][Math]::Floor($x / 8.0)
                    $bitIdx = 7 - ($x % 8)
                    $andMask[$byteIdx] = $andMask[$byteIdx] -bor (1 -shl $bitIdx)
                }
            }
        }
        $bw.Write($andMask)

        $bw.Flush()
        $bytes = $ms.ToArray()
        $ms.Dispose()

        $entriesData += [PSCustomObject]@{
            Width = [byte]$sz
            Height = [byte]$sz
            Data = $bytes
        }
    }
    $bmp.Dispose()
}

$badge.Dispose()

# Write ICO file
$fs = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$bw = New-Object System.IO.BinaryWriter $fs

$bw.Write([uint16]0) # Reserved
$bw.Write([uint16]1) # Type 1 = Icon
$bw.Write([uint16]$entriesData.Count)

$offset = 6 + ($entriesData.Count * 16)
foreach ($e in $entriesData) {
    $bw.Write($e.Width)
    $bw.Write($e.Height)
    $bw.Write([byte]0)   # ColorCount
    $bw.Write([byte]0)   # Reserved
    $bw.Write([uint16]1) # Planes
    $bw.Write([uint16]32)# BitCount
    $bw.Write([uint32]$e.Data.Length)
    $bw.Write([uint32]$offset)
    $offset += $e.Data.Length
}

foreach ($e in $entriesData) {
    $bw.Write($e.Data)
}

$bw.Flush()
$fs.Dispose()

Write-Host "Successfully generated $icoPath"

# Validate that System.Drawing can load it as a valid icon
$testIcon = New-Object System.Drawing.Icon $icoPath
Write-Host "Validated ICO: Width=$($testIcon.Width), Height=$($testIcon.Height)"
$testIcon.Dispose()

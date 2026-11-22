Add-Type -AssemblyName System.Drawing

function New-CtdtBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $scale = $size / 256.0

    # Background circle / crest with metallic gold border
    $margin = 10 * $scale
    $rect = New-Object System.Drawing.RectangleF $margin, $margin, ($size - 2 * $margin), ($size - 2 * $margin)

    # Outer glow / shadow
    $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
    $shadowRect = New-Object System.Drawing.RectangleF ($margin + 3 * $scale), ($margin + 5 * $scale), ($size - 2 * $margin), ($size - 2 * $margin)
    $g.FillEllipse($shadowBrush, $shadowRect)
    $shadowBrush.Dispose()

    # Outer border (Gold gradient)
    $goldBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 235, 160)), ([System.Drawing.Color]::FromArgb(180, 120, 20)), 45.0
    $g.FillEllipse($goldBrush, $rect)
    $goldBrush.Dispose()

    # Inner circle (Royal Navy Blue gradient)
    $innerMargin = $margin + 7 * $scale
    $innerRect = New-Object System.Drawing.RectangleF $innerMargin, $innerMargin, ($size - 2 * $innerMargin), ($size - 2 * $innerMargin)
    $navyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $innerRect, ([System.Drawing.Color]::FromArgb(24, 48, 89)), ([System.Drawing.Color]::FromArgb(8, 16, 36)), 90.0
    $g.FillEllipse($navyBrush, $innerRect)
    $navyBrush.Dispose()

    # Dynamic fiery / speed energy arc behind ball (Tsubasa Drive Shoot flame)
    $arcPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(190, 255, 140, 0)), (8 * $scale)
    $arcRect = New-Object System.Drawing.RectangleF ($margin + 16 * $scale), ($margin + 16 * $scale), ($size - 2 * ($margin + 16 * $scale)), ($size - 2 * ($margin + 16 * $scale))
    $g.DrawArc($arcPen, $arcRect, 190, 160)
    $arcPen.Color = [System.Drawing.Color]::FromArgb(220, 255, 215, 0)
    $arcPen.Width = 4 * $scale
    $g.DrawArc($arcPen, $arcRect, 205, 130)
    $arcPen.Dispose()

    # Soccer ball in center
    $ballRadius = 56 * $scale
    $cx = $size / 2.0
    $cy = $size / 2.0 - 10 * $scale
    $ballRect = New-Object System.Drawing.RectangleF ($cx - $ballRadius), ($cy - $ballRadius), (2 * $ballRadius), (2 * $ballRadius)

    # Ball shadow
    $ballShadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
    $g.FillEllipse($ballShadow, ($cx - $ballRadius + 4 * $scale), ($cy - $ballRadius + 6 * $scale), (2 * $ballRadius), (2 * $ballRadius))
    $ballShadow.Dispose()

    # Ball body (Soft white / light silver gradient)
    # unused
    $ballPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $ballPath.AddEllipse($ballRect)
    $ballPgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $ballPath
    $ballPgb.CenterPoint = New-Object System.Drawing.PointF ($cx - 15 * $scale), ($cy - 18 * $scale)
    $ballPgb.CenterColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $ballPgb.SurroundColors = @([System.Drawing.Color]::FromArgb(195, 205, 220))
    $g.FillPath($ballPgb, $ballPath)
    $ballPgb.Dispose()
    $ballPath.Dispose()

    # Ball black pentagons
    $patchBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(35, 40, 55))
    $centerPatch = @(
        (New-Object System.Drawing.PointF $cx, ($cy - 12 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 12 * $scale), ($cy - 3 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 8 * $scale), ($cy + 11 * $scale)),
        (New-Object System.Drawing.PointF ($cx - 8 * $scale), ($cy + 11 * $scale)),
        (New-Object System.Drawing.PointF ($cx - 12 * $scale), ($cy - 3 * $scale))
    )
    $g.FillPolygon($patchBrush, $centerPatch)

    # Outer patches
    $topPatch = @(
        (New-Object System.Drawing.PointF ($cx - 10 * $scale), ($cy - $ballRadius + 4 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 10 * $scale), ($cy - $ballRadius + 4 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 14 * $scale), ($cy - 30 * $scale)),
        (New-Object System.Drawing.PointF ($cx - 14 * $scale), ($cy - 30 * $scale))
    )
    $g.FillPolygon($patchBrush, $topPatch)

    $leftPatch = @(
        (New-Object System.Drawing.PointF ($cx - $ballRadius + 5 * $scale), ($cy - 10 * $scale)),
        (New-Object System.Drawing.PointF ($cx - 32 * $scale), ($cy - 20 * $scale)),
        (New-Object System.Drawing.PointF ($cx - 30 * $scale), ($cy + 8 * $scale)),
        (New-Object System.Drawing.PointF ($cx - $ballRadius + 8 * $scale), ($cy + 16 * $scale))
    )
    $g.FillPolygon($patchBrush, $leftPatch)

    $rightPatch = @(
        (New-Object System.Drawing.PointF ($cx + $ballRadius - 5 * $scale), ($cy - 10 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 32 * $scale), ($cy - 20 * $scale)),
        (New-Object System.Drawing.PointF ($cx + 30 * $scale), ($cy + 8 * $scale)),
        (New-Object System.Drawing.PointF ($cx + $ballRadius - 8 * $scale), ($cy + 16 * $scale))
    )
    $g.FillPolygon($patchBrush, $rightPatch)

    # Lines connecting patches
    $seamPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, 30, 35, 50)), (2 * $scale)
    $g.DrawLine($seamPen, $cx, ($cy - 12 * $scale), $cx, ($cy - 30 * $scale))
    $g.DrawLine($seamPen, ($cx - 12 * $scale), ($cy - 3 * $scale), ($cx - 32 * $scale), ($cy - 5 * $scale))
    $g.DrawLine($seamPen, ($cx + 12 * $scale), ($cy - 3 * $scale), ($cx + 32 * $scale), ($cy - 5 * $scale))
    $g.DrawLine($seamPen, ($cx - 8 * $scale), ($cy + 11 * $scale), ($cx - 24 * $scale), ($cy + 32 * $scale))
    $g.DrawLine($seamPen, ($cx + 8 * $scale), ($cy + 11 * $scale), ($cx + 24 * $scale), ($cy + 32 * $scale))
    $seamPen.Dispose()
    $patchBrush.Dispose()

    # Glass highlight on upper ball
    $highlightBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF ($cx - 38 * $scale), ($cy - 48 * $scale), (76 * $scale), (40 * $scale)), ([System.Drawing.Color]::FromArgb(140, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(0, 255, 255, 255)), 90.0
    $g.FillEllipse($highlightBrush, ($cx - 34 * $scale), ($cy - 46 * $scale), (68 * $scale), (34 * $scale))
    $highlightBrush.Dispose()

    # Lower Golden Banner for CTDT text
    $bannerY = $cy + 42 * $scale
    $bannerW = 164 * $scale
    $bannerH = 46 * $scale
    $bannerX = ($size - $bannerW) / 2.0
    $bannerRect = New-Object System.Drawing.RectangleF $bannerX, $bannerY, $bannerW, $bannerH

    # Banner ribbon polygon
    $bannerPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bannerPts = @(
        (New-Object System.Drawing.PointF $bannerX, $bannerY),
        (New-Object System.Drawing.PointF ($bannerX + $bannerW), $bannerY),
        (New-Object System.Drawing.PointF ($bannerX + $bannerW - 8 * $scale), ($bannerY + $bannerH)),
        (New-Object System.Drawing.PointF ($bannerX + 8 * $scale), ($bannerY + $bannerH))
    )
    $bannerPath.AddPolygon($bannerPts)

    # Banner shadow
    $g.TranslateTransform((2 * $scale), (3 * $scale))
    $bannerShadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(100, 0, 0, 0))
    $g.FillPath($bannerShadow, $bannerPath)
    $bannerShadow.Dispose()
    $g.TranslateTransform((-2 * $scale), (-3 * $scale))

    # Banner fill (Gold/Crimson shield gradient)
    $ribbonBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bannerRect, ([System.Drawing.Color]::FromArgb(218, 41, 28)), ([System.Drawing.Color]::FromArgb(140, 15, 10)), 90.0
    $g.FillPath($ribbonBrush, $bannerPath)
    $ribbonBrush.Dispose()

    # Banner border (Gold)
    $bannerBorderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 225, 100)), (2.5 * $scale)
    $g.DrawPath($bannerBorderPen, $bannerPath)
    $bannerBorderPen.Dispose()
    $bannerPath.Dispose()

    # CTDT Text in Banner
    $fontFamily = [System.Drawing.FontFamily]::GenericSansSerif
    $fontSize = 24.0 * $scale
    $font = New-Object System.Drawing.Font $fontFamily, $fontSize, ([System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    # Text shadow
    $textShadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
    $textRectShadow = New-Object System.Drawing.RectangleF ($bannerX + 1.5 * $scale), ($bannerY + 2 * $scale), $bannerW, $bannerH
    $g.DrawString("CTDT", $font, $textShadowBrush, $textRectShadow, $sf)
    $textShadowBrush.Dispose()

    # Text main (Bright Metallic Gold)
    $textBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bannerRect, ([System.Drawing.Color]::FromArgb(255, 245, 175)), ([System.Drawing.Color]::FromArgb(255, 205, 50)), 90.0
    $g.DrawString("CTDT", $font, $textBrush, $bannerRect, $sf)
    $textBrush.Dispose()

    # Small AUTO badge at top
    $badgeRect = New-Object System.Drawing.RectangleF ($cx - 28 * $scale), ($margin + 12 * $scale), (56 * $scale), (16 * $scale)
    $badgeBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 20, 60, 120))
    $g.FillRectangle($badgeBrush, $badgeRect)
    $badgeBrush.Dispose()
    $badgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 215, 0)), (1 * $scale)
    $g.DrawRectangle($badgePen, $badgeRect.X, $badgeRect.Y, $badgeRect.Width, $badgeRect.Height)
    $badgePen.Dispose()

    $badgeFont = New-Object System.Drawing.Font $fontFamily, (9.0 * $scale), ([System.Drawing.FontStyle]::Bold)
    $badgeTextBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 140))
    $g.DrawString("AUTO", $badgeFont, $badgeTextBrush, $badgeRect, $sf)
    $badgeTextBrush.Dispose()
    $badgeFont.Dispose()

    $font.Dispose()
    $sf.Dispose()
    $g.Dispose()

    return $bmp
}

# Write valid multi-size Windows .ico with PNG encoded frames
function Save-Ico([System.Drawing.Bitmap[]]$bitmaps, [string]$outFile) {
    $fs = [System.IO.File]::Open($outFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $bw = New-Object System.IO.BinaryWriter $fs

    # ICONDIR
    $bw.Write([uint16]0) # Reserved
    $bw.Write([uint16]1) # Type: 1 = Icon
    $bw.Write([uint16]$bitmaps.Length) # Count

    $pngBytesList = @()
    foreach ($b in $bitmaps) {
        $ms = New-Object System.IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBytesList += ,$ms.ToArray()
        $ms.Dispose()
    }

    $offset = 6 + ($bitmaps.Length * 16)

    for ($i = 0; $i -lt $bitmaps.Length; $i++) {
        $b = $bitmaps[$i]
        $bytes = $pngBytesList[$i]
        $w = if ($b.Width -ge 256) { 0 } else { [byte]$b.Width }
        $h = if ($b.Height -ge 256) { 0 } else { [byte]$b.Height }

        $bw.Write($w) # Width
        $bw.Write($h) # Height
        $bw.Write([byte]0) # Color count
        $bw.Write([byte]0) # Reserved
        $bw.Write([uint16]1) # Planes
        $bw.Write([uint16]32) # Bit count
        $bw.Write([uint32]$bytes.Length) # Bytes in resource
        $bw.Write([uint32]$offset) # Offset
        $offset += $bytes.Length
    }

    for ($i = 0; $i -lt $bitmaps.Length; $i++) {
        $bw.Write($pngBytesList[$i])
    }

    $bw.Flush()
    $fs.Dispose()
}

$sizes = @(256, 128, 64, 48, 32, 16)
$bitmaps = @()
foreach ($sz in $sizes) {
    $bitmaps += (New-CtdtBitmap $sz)
}

$icoPath = "d:\Game\AUTOCTDT\CtdtAuto.ico"
Save-Ico $bitmaps $icoPath
Write-Output "Successfully generated $icoPath"

# Also save 256x256 preview png
$bitmaps[0].Save("d:\Game\AUTOCTDT\CtdtAuto_preview.png", [System.Drawing.Imaging.ImageFormat]::Png)
foreach ($b in $bitmaps) { $b.Dispose() }


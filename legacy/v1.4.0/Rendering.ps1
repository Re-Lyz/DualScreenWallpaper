Add-Type -AssemblyName System.Drawing
# Shared bitmap rendering for previews and transition frames.
. (Join-Path $PSScriptRoot 'ImageProcessing.ps1')
function Read-PreviewImage([string]$path) {
    $frame=Get-WallpaperFrame $path
    $encoder=[Windows.Media.Imaging.JpegBitmapEncoder]::new()
    $encoder.QualityLevel=95
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($frame))
    $stream=[IO.MemoryStream]::new()
    try {
        $encoder.Save($stream); $stream.Position=0
        $decoded=[Drawing.Image]::FromStream($stream)
        try {return [Drawing.Bitmap]::new($decoded)} finally {$decoded.Dispose()}
    } finally {$stream.Dispose()}
}
function Get-PreviewImageRect([double]$imageWidth,[double]$imageHeight,[double]$screenWidth,[double]$screenHeight,[string]$mode) {
    $w=$imageWidth; $h=$imageHeight
    switch($mode) {
        'Fill' {$scale=[Math]::Max($screenWidth/$w,$screenHeight/$h); $w*=$scale; $h*=$scale}
        'Fit' {$scale=[Math]::Min($screenWidth/$w,$screenHeight/$h); $w*=$scale; $h*=$scale}
        'Stretch' {$w=$screenWidth; $h=$screenHeight}
    }
    [Drawing.RectangleF]::new([single](($screenWidth-$w)/2),[single](($screenHeight-$h)/2),[single]$w,[single]$h)
}
function Draw-PreviewScreen($graphics,$image,$rect,$monitor,[string]$mode,$background) {
    $saved=$graphics.Save()
    $brush=[Drawing.SolidBrush]::new($background)
    try {
        $graphics.SetClip($rect)
        $graphics.FillRectangle($brush,$rect)
        if(!$image){return}
        $sx=$rect.Width/$monitor.Width; $sy=$rect.Height/$monitor.Height
        if($mode -eq 'Tile') {
            $texture=[Drawing.TextureBrush]::new($image,[Drawing.Drawing2D.WrapMode]::Tile)
            try {
                $transform=[Drawing.Drawing2D.Matrix]::new([single]$sx,0,0,[single]$sy,$rect.X,$rect.Y)
                try {$texture.Transform=$transform} finally {$transform.Dispose()}
                $graphics.FillRectangle($texture,$rect)
            } finally {$texture.Dispose()}
        } else {
            $dest=Get-PreviewImageRect $image.Width $image.Height $monitor.Width $monitor.Height $mode
            $target=[Drawing.RectangleF]::new([single]($rect.X+$dest.X*$sx),[single]($rect.Y+$dest.Y*$sy),[single]($dest.Width*$sx),[single]($dest.Height*$sy))
            $graphics.DrawImage($image,$target,[Drawing.RectangleF]::new(0,0,$image.Width,$image.Height),[Drawing.GraphicsUnit]::Pixel)
        }
    } finally {$brush.Dispose(); $graphics.Restore($saved)}
}

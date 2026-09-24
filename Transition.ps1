. (Join-Path $PSScriptRoot 'Rendering.ps1')
function New-TransitionCanvas($image,$monitor,[string]$mode,$background) {
    $canvas=[Drawing.Bitmap]::new($monitor.Width,$monitor.Height)
    $g=[Drawing.Graphics]::FromImage($canvas)
    try {
        $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        Draw-PreviewScreen $g $image ([Drawing.RectangleF]::new(0,0,$monitor.Width,$monitor.Height)) $monitor $mode $background
        return $canvas
    } catch {$canvas.Dispose(); throw} finally {$g.Dispose()}
}
function New-BlendFrame($old,$next,[single]$alpha) {
    $frame=[Drawing.Bitmap]::new($next.Width,$next.Height)
    $g=[Drawing.Graphics]::FromImage($frame); $attributes=[Drawing.Imaging.ImageAttributes]::new()
    try {
        $g.DrawImageUnscaled($old,0,0)
        $matrix=[Drawing.Imaging.ColorMatrix]::new(); $matrix.Matrix33=[single][Math]::Max(0.0,[Math]::Min(1.0,[double]$alpha))
        $attributes.SetColorMatrix($matrix)
        $g.DrawImage($next,[Drawing.Rectangle]::new(0,0,$next.Width,$next.Height),0,0,$next.Width,$next.Height,[Drawing.GraphicsUnit]::Pixel,$attributes)
        return $frame
    } catch {$frame.Dispose(); throw} finally {$g.Dispose();$attributes.Dispose()}
}
function Set-WallpaperWithTransition($desktop,$monitor,[string]$output,[string]$mode,[string]$effect,[int]$oldPosition,[string]$cachePrefix) {
    if($effect -eq 'CrossFade' -and $mode -ne 'Tile' -and $oldPosition -ne 1 -and ([long]$monitor.Width*$monitor.Height) -le 16000000) {
        $oldImage=$null; $newImage=$null; $oldCanvas=$null; $newCanvas=$null
        try {
            $oldPath=$desktop.GetWallpaper($monitor.Id)
            if($oldPath -and (Test-Path -LiteralPath $oldPath -PathType Leaf)) {
                $oldMode=@('Center','Tile','Stretch','Fit','Fill')[$oldPosition]
                if(!$oldMode){throw 'Previous wallpaper position cannot be animated.'}
                $color=$desktop.GetBackgroundColor()
                $background=[Drawing.Color]::FromArgb([int]($color -band 255),[int](($color -shr 8) -band 255),[int](($color -shr 16) -band 255))
                $oldImage=Read-PreviewImage $oldPath; $newImage=Read-PreviewImage $output
                $oldCanvas=New-TransitionCanvas $oldImage $monitor $oldMode $background
                $newCanvas=New-TransitionCanvas $newImage $monitor $mode $background
                for($step=1;$step -le 8;$step++) {
                    $watch=[Diagnostics.Stopwatch]::StartNew()
                    $frame=New-BlendFrame $oldCanvas $newCanvas ([single]($step/9.0))
                    $path="$cachePrefix-transition-$($step%2).jpg"
                    try {$frame.Save($path,[Drawing.Imaging.ImageFormat]::Jpeg)} finally {$frame.Dispose()}
                    $desktop.SetWallpaper($monitor.Id,$path)
                    $remaining=100-[int]$watch.ElapsedMilliseconds
                    if($remaining -gt 0){Start-Sleep -Milliseconds $remaining}
                }
            }
        } catch {Write-Warning "Crossfade unavailable; applying wallpaper directly: $_"}
        finally {foreach($resource in @($oldCanvas,$newCanvas,$oldImage,$newImage)){if($resource){$resource.Dispose()}}}
    }
    # Always finish on the normal cache, including after a failed animation.
    $desktop.SetWallpaper($monitor.Id,$output)
}

Add-Type -AssemblyName PresentationCore,WindowsBase
if(!('Wallpaper.ImageHeader' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'ImageHeader.cs')}

function Get-Frame($path) {
    $header = [Wallpaper.ImageHeader]::Read($path)
    if ($header) { return [pscustomobject]@{ Width=$header[0]; Height=$header[1]; Orientation=$header[2] } }
    $stream = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation, [Windows.Media.Imaging.BitmapCacheOption]::None)
        $frame = $decoder.Frames[0]
        $rotation = 0
        try {
            $orientation = $frame.Metadata.GetQuery('/app1/ifd/{ushort=274}')
            if ($orientation) { $rotation = [int]$orientation }
        } catch {}
        $w = $frame.PixelWidth; $h = $frame.PixelHeight
        if ($rotation -in 5,6,7,8) { $w = $frame.PixelHeight; $h = $frame.PixelWidth }
        [pscustomobject]@{ Width=$w; Height=$h; Orientation=$rotation }
    } finally { $stream.Dispose() }
}

function Get-Monitors($desktop) {
    for ($i=0; $i -lt $desktop.GetMonitorDevicePathCount(); $i++) {
        $id = $desktop.GetMonitorDevicePathAt($i)
        try { $rect = $desktop.GetMonitorRECT($id) } catch { continue } # Disconnected display
        $w = $rect.Right-$rect.Left; $h = $rect.Bottom-$rect.Top
        if ($w -gt 0 -and $h -gt 0) {
            [pscustomobject]@{ Id=$id; Left=$rect.Left; Top=$rect.Top; Width=$w; Height=$h; Kind=(Get-MonitorRole $rect) }
        }
    }
}

function Get-WallpaperFrame($source) {
    $info = Get-Frame $source
    $stream = [IO.File]::Open($source, 'Open', 'Read', 'ReadWrite')
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        $frame = $decoder.Frames[0]
    } finally { $stream.Dispose() }
    $matrix = [Windows.Media.Matrix]::Identity
    switch ($info.Orientation) {
        2 { $matrix.Scale(-1,1) }
        3 { $matrix.Rotate(180) }
        4 { $matrix.Scale(1,-1) }
        5 { $matrix = [Windows.Media.Matrix]::new(0,1,1,0,0,0) }
        6 { $matrix.Rotate(90) }
        7 { $matrix = [Windows.Media.Matrix]::new(0,-1,-1,0,0,0) }
        8 { $matrix.Rotate(270) }
    }
    if (!$matrix.IsIdentity) { $frame = [Windows.Media.Imaging.TransformedBitmap]::new($frame, [Windows.Media.MatrixTransform]::new($matrix)) }
    return $frame
}
function Convert-Wallpaper($source, $destination) {
    $frame=Get-WallpaperFrame $source
    $encoder = [Windows.Media.Imaging.JpegBitmapEncoder]::new()
    $encoder.QualityLevel = 95
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($frame))
    $out = [IO.File]::Create($destination)
    try { $encoder.Save($out) } finally { $out.Dispose() }
}

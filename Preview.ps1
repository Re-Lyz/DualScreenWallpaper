# Read-only preview; image decoding and EXIF transforms are shared with the worker.
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
function New-LayoutPreview($monitors,$images,[string]$mode,[int]$width,[int]$height,$background) {
    $bitmap=[Drawing.Bitmap]::new([Math]::Max(1,$width),[Math]::Max(1,$height))
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $font=[Drawing.Font]::new('Microsoft YaHei UI',9)
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(35,38,43))
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        if(!$monitors.Count){return $bitmap}
        $left=($monitors | Measure-Object Left -Minimum).Minimum
        $top=($monitors | Measure-Object Top -Minimum).Minimum
        $right=($monitors | ForEach-Object {$_.Left+$_.Width} | Measure-Object -Maximum).Maximum
        $bottom=($monitors | ForEach-Object {$_.Top+$_.Height} | Measure-Object -Maximum).Maximum
        $scale=[Math]::Min([Math]::Max(1,$width-48)/($right-$left),[Math]::Max(1,$height-48)/($bottom-$top))
        $ox=($width-($right-$left)*$scale)/2; $oy=($height-($bottom-$top)*$scale)/2
        $number=0
        foreach($monitor in $monitors) {
            $number++
            $rect=[Drawing.RectangleF]::new([single]($ox+($monitor.Left-$left)*$scale),[single]($oy+($monitor.Top-$top)*$scale),[single]($monitor.Width*$scale),[single]($monitor.Height*$scale))
            Draw-PreviewScreen $graphics $images[$monitor.Id] $rect $monitor $mode $background
            $graphics.DrawRectangle([Drawing.Pens]::LightSteelBlue,$rect.X,$rect.Y,$rect.Width,$rect.Height)
            $role=Get-UiText $(if($monitor.Kind -eq 'Primary'){'主屏'}else{'副屏'})
            $label="$number · $role · $($monitor.Width) × $($monitor.Height)"
            $saved=$graphics.Save()
            try {
                $graphics.SetClip($rect)
                $graphics.FillRectangle([Drawing.Brushes]::Black,$rect.X,$rect.Y,$rect.Width,24)
                $graphics.DrawString($label,$font,[Drawing.Brushes]::White,($rect.X+4),($rect.Y+3))
                if(!$images[$monitor.Id]){$graphics.DrawString((Get-UiText '请选择示例图片'),$font,[Drawing.Brushes]::White,($rect.X+8),($rect.Y+32))}
            } finally {$graphics.Restore($saved)}
        }
        return $bitmap
    } catch {$bitmap.Dispose(); throw} finally {$font.Dispose(); $graphics.Dispose()}
}
function Show-WallpaperPreview($owner,[string]$initialMode,[string]$CapturePath,[object[]]$MonitorOverride,[hashtable]$SourceOverride) {
    if(!('Wallpaper.Desktop' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Desktop.cs')}
    $sources=@{}; $images=@{}; $background=[Drawing.Color]::Black
    if($MonitorOverride) {
        $monitors=$MonitorOverride
        if($SourceOverride){$sources=$SourceOverride}
    } else {
        $desktop=[Wallpaper.Desktop]::Open()
        try {
            $monitors=@(Get-Monitors $desktop)
            $color=$desktop.GetBackgroundColor()
            $background=[Drawing.Color]::FromArgb([int]($color -band 255),[int](($color -shr 8) -band 255),[int](($color -shr 16) -band 255))
            foreach($monitor in $monitors){$sources[$monitor.Id]=$desktop.GetWallpaper($monitor.Id)}
        } finally {$desktop.Dispose()}
    }
    if(!$monitors.Count){throw (Get-UiText '没有可预览的显示器。')}
    $window=[Windows.Forms.Form]::new(); $window.Text=Get-UiText '壁纸预览'
    $window.ClientSize=[Drawing.Size]::new(900,640); $window.MinimumSize=[Drawing.Size]::new(700,500)
    $window.StartPosition='CenterParent'; $window.Font=$owner.Font
    $canvas=[Windows.Forms.PictureBox]::new(); $canvas.SetBounds(16,155,868,421); $canvas.Anchor='Top,Bottom,Left,Right'; $window.Controls.Add($canvas)
    $screen=[Windows.Forms.ComboBox]::new(); $screen.DropDownStyle='DropDownList'; $screen.SetBounds(16,15,300,28); $window.Controls.Add($screen)
    $number=0
    foreach($monitor in $monitors){$number++; [void]$screen.Items.Add("$number · $(Get-UiText $(if($monitor.Kind -eq 'Primary'){'主屏'}else{'副屏'})) · $($monitor.Width) × $($monitor.Height)")}
    $choose=[Windows.Forms.Button]::new(); $choose.Text=Get-UiText '选择示例图片…'; $choose.SetBounds(330,12,185,32); $window.Controls.Add($choose)
    $modes=@('Fill','Fit','Stretch','Center','Tile')
    $mode=[Windows.Forms.ComboBox]::new(); $mode.DropDownStyle='DropDownList'; $mode.SetBounds(530,15,354,28); $mode.Anchor='Top,Left,Right'; $window.Controls.Add($mode)
    foreach($key in @('填充（等比铺满，裁剪边缘）','适应（完整显示，可能留边）','拉伸（铺满，可能变形）','居中（原始尺寸，可能裁剪）','平铺（原始尺寸，重复排列）')){[void]$mode.Items.Add((Get-UiText $key))}
    $mode.SelectedIndex=[Array]::IndexOf($modes,$initialMode)
    $pathLabel=[Windows.Forms.TextBox]::new(); $pathLabel.ReadOnly=$true; $pathLabel.SetBounds(16,53,868,28); $pathLabel.Anchor='Top,Left,Right'; $window.Controls.Add($pathLabel)
    $hint=[Windows.Forms.Label]::new(); $hint.Text=Get-UiText '示例预览，不代表下一张轮播图片；平铺按单屏示意。'; $hint.SetBounds(16,88,868,26); $hint.Anchor='Top,Left,Right'; $window.Controls.Add($hint)
    $errors=[Windows.Forms.Label]::new(); $errors.ForeColor=[Drawing.Color]::DarkRed; $errors.SetBounds(16,117,868,30); $errors.Anchor='Top,Left,Right'; $window.Controls.Add($errors)
    $use=[Windows.Forms.Button]::new(); $use.Text=Get-UiText '使用此显示方式'; $use.SetBounds(16,592,220,32); $use.Anchor='Bottom,Left'; $use.DialogResult='OK'; $window.Controls.Add($use)
    $close=[Windows.Forms.Button]::new(); $close.Text=Get-UiText '关闭'; $close.SetBounds(744,592,140,32); $close.Anchor='Bottom,Right'; $close.DialogResult='Cancel'; $window.Controls.Add($close); $window.CancelButton=$close
    $refresh={
        try {
            $next=New-LayoutPreview $monitors $images $modes[$mode.SelectedIndex] $canvas.ClientSize.Width $canvas.ClientSize.Height $background
            $oldImage=$canvas.Image; $canvas.Image=$next; if($oldImage){$oldImage.Dispose()}
        } catch {$errors.Text=[string]$_}
    }.GetNewClosure()
    $screen.Add_SelectedIndexChanged({$pathLabel.Text=$sources[$monitors[$screen.SelectedIndex].Id]}.GetNewClosure())
    $mode.Add_SelectedIndexChanged($refresh); $canvas.Add_SizeChanged($refresh)
    $choose.Add_Click({
        $dialog=[Windows.Forms.OpenFileDialog]::new(); $dialog.Filter='Images|*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.gif;*.tif;*.tiff;*.ico;*.wdp;*.jxr;*.webp;*.heic;*.heif;*.avif|All files|*.*'
        try {
            if($dialog.ShowDialog($window) -eq 'OK') {
                $next=Read-PreviewImage $dialog.FileName
                $id=$monitors[$screen.SelectedIndex].Id
                if($images[$id]){$images[$id].Dispose()}
                $images[$id]=$next; $sources[$id]=$dialog.FileName; $pathLabel.Text=$dialog.FileName
                $errors.Text=''; & $refresh
            }
        } catch {$errors.Text=Get-UiText '图片无法读取：{0}' @([string]$_)} finally {$dialog.Dispose()}
    }.GetNewClosure())
    try {
        foreach($monitor in $monitors) {
            if($sources[$monitor.Id]) {
                try {$images[$monitor.Id]=Read-PreviewImage $sources[$monitor.Id]} catch {$errors.Text=Get-UiText '部分图片无法读取，请重新选择示例图片。'}
            }
        }
        $screen.SelectedIndex=0; & $refresh
        if($CapturePath) {
            foreach($index in 0..4){$mode.SelectedIndex=$index; if($errors.Text){throw $errors.Text}}
            $mode.SelectedIndex=[Array]::IndexOf($modes,$initialMode)
            $screen.SelectedIndex=$monitors.Count-1; $screen.SelectedIndex=0
            if($pathLabel.Text -ne $sources[$monitors[0].Id]){throw 'Preview monitor selection did not update source path.'}
            $window.StartPosition='Manual'; $window.Location=[Drawing.Point]::new(-10000,-10000); $window.ShowInTaskbar=$false
            $window.Show(); [Windows.Forms.Application]::DoEvents()
            $capture=[Drawing.Bitmap]::new($window.Width,$window.Height)
            try {$window.DrawToBitmap($capture,[Drawing.Rectangle]::new(0,0,$window.Width,$window.Height)); $capture.Save($CapturePath)} finally {$capture.Dispose()}
        } elseif($window.ShowDialog($owner) -eq 'OK'){return $modes[$mode.SelectedIndex]}
    } finally {
        if($canvas.Image){$canvas.Image.Dispose(); $canvas.Image=$null}
        foreach($image in $images.Values){$image.Dispose()}
        $window.Dispose()
    }
}

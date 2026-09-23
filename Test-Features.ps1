$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'Language.ps1')
. (Join-Path $PSScriptRoot 'Preview.ps1')
function Assert($condition,$message){if(!$condition){throw "FAILED: $message"}}
$script:uiLanguage='en-US'
$paths=@('D:\b\02.jpg','D:\a\01.jpg','D:\a\02.jpg')
Assert ((@(Get-PlaybackCandidates $paths '' 'Sequential') -join '|') -eq 'D:\a\01.jpg|D:\a\02.jpg|D:\b\02.jpg') 'filename sorting and full-path tie break'
Assert ((@(Get-PlaybackCandidates $paths 'D:\b\02.jpg' 'Sequential'))[0] -eq 'D:\a\01.jpg') 'sequence wraps'
Assert ((@(Get-PlaybackCandidates $paths 'deleted.jpg' 'Sequential'))[0] -eq 'D:\a\01.jpg') 'missing previous starts first'
Assert ((@(Get-PlaybackCandidates @('one.jpg') 'one.jpg' 'Sequential'))[0] -eq 'one.jpg') 'one-image sequence repeats'
Assert (@(Get-PlaybackCandidates @() '' 'Sequential').Count -eq 0) 'empty pool'
Assert (@(Get-PlaybackCandidates $paths $paths[0] 'Random') -notcontains $paths[0]) 'random avoids previous'
$data=Join-Path $PSScriptRoot ('data\features-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $data -Force | Out-Null
try {
    $config=Read-SettingsFile (Join-Path $PSScriptRoot 'config.example.json')
    $signature=Index-Signature $config
    $config.PlaybackOrder='Sequential'
    Assert ($signature -eq (Index-Signature $config)) 'order does not invalidate index'
    foreach($invalid in @('[]','{}','{"SchemaVersion":99}','{"SchemaVersion":2,"AutoStart":"false"}')) {
        $invalid | Set-Content -LiteralPath (Join-Path $data 'invalid.json') -Encoding UTF8
        $failed=$false
        try {$null=Read-SettingsFile (Join-Path $data 'invalid.json')} catch {$failed=$true}
        Assert $failed 'malformed import rejected'
    }
    foreach($field in 'AutoStart','IntervalMinutes','PlaybackOrder','DisplayMode') {
        $bad=$config | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $bad.$field='invalid'
        $bad | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'invalid.json') -Encoding UTF8
        $failed=$false
        try {$null=Read-SettingsFile (Join-Path $data 'invalid.json')} catch {$failed=$true}
        Assert $failed "invalid field rejected: $field"
    }
    $image=[Drawing.Bitmap]::new(120,60)
    $graphics=[Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear([Drawing.Color]::Red)
        $graphics.FillRectangle([Drawing.Brushes]::Lime,40,0,40,60)
        $graphics.FillRectangle([Drawing.Brushes]::Blue,80,0,40,60)
        $image.Save((Join-Path $data '01.png'),[Drawing.Imaging.ImageFormat]::Png)
        $image.Save((Join-Path $data '03.png'),[Drawing.Imaging.ImageFormat]::Png)
    } finally {$graphics.Dispose(); $image.Dispose()}
    'broken' | Set-Content -LiteralPath (Join-Path $data '02.png')
    $image=Read-PreviewImage (Join-Path $data '01.png')
    try {
        $monitor=[pscustomobject]@{Width=100;Height=100}
        foreach($mode in 'Fill','Fit','Stretch','Center','Tile') {
            $canvas=[Drawing.Bitmap]::new(100,100); $g=[Drawing.Graphics]::FromImage($canvas)
            try {
                Draw-PreviewScreen $g $image ([Drawing.RectangleF]::new(0,0,100,100)) $monitor $mode ([Drawing.Color]::Black)
                if($mode -eq 'Fit'){Assert ($canvas.GetPixel(50,5).R -eq 0 -and $canvas.GetPixel(50,50).G -gt 200) 'Fit letterboxes'}
                if($mode -eq 'Fill'){Assert ($canvas.GetPixel(50,5).G -gt 200) 'Fill covers and center crops'}
                if($mode -eq 'Stretch'){Assert ($canvas.GetPixel(5,5).R -gt 200 -and $canvas.GetPixel(95,95).B -gt 200) 'Stretch covers without cropping'}
                if($mode -eq 'Center'){Assert ($canvas.GetPixel(50,5).R -eq 0 -and $canvas.GetPixel(50,50).G -gt 200) 'Center preserves original height'}
                if($mode -eq 'Tile'){Assert ($canvas.GetPixel(5,5).R -gt 200 -and $canvas.GetPixel(5,65).R -gt 200) 'Tile repeats image'}
            } finally {$g.Dispose(); $canvas.Dispose()}
        }
    } finally {$image.Dispose()}
    # A JPEG with EXIF rotation verifies the same transform is used by preview and wallpaper conversion.
    $frame=Get-WallpaperFrame (Join-Path $data '01.png')
    $metadata=[Windows.Media.Imaging.BitmapMetadata]::new('jpg')
    $metadata.SetQuery('/app1/ifd/{ushort=274}',[uint16]6)
    $encoder=[Windows.Media.Imaging.JpegBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($frame,$null,$metadata,$null))
    $stream=[IO.File]::Create((Join-Path $data 'rotated.jpg'))
    try {$encoder.Save($stream)} finally {$stream.Dispose()}
    $rotated=Read-PreviewImage (Join-Path $data 'rotated.jpg')
    try {Assert ($rotated.Width -eq 60 -and $rotated.Height -eq 120) 'EXIF rotation applied in preview'} finally {$rotated.Dispose()}
    # Only the desktop boundary is mocked: exercise conversion, retries, persisted state and next invocation.
    Add-Type @'
namespace Wallpaper {
 public class TestRect { public int Left=0,Top=0,Right=1920,Bottom=1080; }
 public class Desktop : System.IDisposable {
  public static string LastWallpaper;
  public static Desktop Open(){return new Desktop();}
  public uint GetMonitorDevicePathCount(){return 1;}
  public string GetMonitorDevicePathAt(uint i){return "test-monitor";}
  public TestRect GetMonitorRECT(string id){return new TestRect();}
  public int GetPosition(){return 4;}
  public string GetWallpaper(string id){return "";}
  public void SetPosition(int p){}
  public void SetWallpaper(string id,string path){LastWallpaper=path;}
  public void Dispose(){}
 }
}
'@
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Wallpaper.ps1'),[ref]$tokens,[ref]$errors)
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Run-Wallpaper'},$true)
    . ([scriptblock]::Create($node.Extent.Text))
    $pool=@('01.png','02.png','03.png') | ForEach-Object {Join-Path $data $_}
    @{Config=($config | ConvertTo-Json -Depth 6 -Compress); Images=@{Primary=$pool;Secondary=$pool}} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'index.json') -Encoding UTF8
    foreach($expected in '01.png','03.png','01.png') {
        Run-Wallpaper
        $state=Get-Content -LiteralPath (Join-Path $data 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert ([IO.Path]::GetFileName($state.'test-monitor'.Source) -eq $expected) 'worker resumes, skips corrupt image and wraps'
        Assert (Test-Path -LiteralPath ([Wallpaper.Desktop]::LastWallpaper)) 'worker produced actual JPEG'
    }
    $owner=[Windows.Forms.Form]::new()
    $owner.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
    try {
        $monitors=@([pscustomobject]@{Id='portrait';Kind='Secondary';Left=-1080;Top=-240;Width=1080;Height=1920},[pscustomobject]@{Id='main';Kind='Primary';Left=0;Top=0;Width=2560;Height=1440})
        foreach($lang in 'zh-CN','en-US') {
            $script:uiLanguage=$lang
            Show-WallpaperPreview $owner 'Fit' (Join-Path $PSScriptRoot "data\wallpaper-preview-$lang.png") $monitors @{portrait=(Join-Path $data 'rotated.jpg');main=(Join-Path $data '01.png')}
        }
    } finally {$owner.Dispose()}
    Write-Output 'PASS: playback persistence/retries, import validation, five preview modes, EXIF rotation and bilingual preview windows.'
} finally {
    $resolved=[IO.Path]::GetFullPath($data)
    $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'data')).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

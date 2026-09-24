# Integration test: briefly shows red/blue on active screens, then restores the exact previous wallpapers.
param([string]$ApplicationPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$ApplicationPath){$ApplicationPath=Join-Path $repo 'dist\csharp-v2\DualScreenWallpaper.exe'}
$job=Join-Path $repo ('data\desktop-validation-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $job 'data') -Force | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $repo 'Desktop.cs')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class PixelProbe { [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr window); [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr window, IntPtr dc); [DllImport("gdi32.dll")] public static extern uint GetPixel(IntPtr dc,int x,int y); }'
foreach($name in @('red','blue')){
    $bmp=New-Object Drawing.Bitmap 64,64;$graphics=[Drawing.Graphics]::FromImage($bmp)
    try {$graphics.Clear($(if($name -eq 'red'){[Drawing.Color]::Red}else{[Drawing.Color]::Blue}));$bmp.Save((Join-Path $job ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png)}
    finally {$graphics.Dispose();$bmp.Dispose()}
}
$config=Get-Content (Join-Path $repo 'config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$config.TransitionEffect='CrossFade';$config.AutoStart=$false;$config.SetupCompleted=$true
foreach($profile in @($config.Primary,$config.Secondary)){$profile.Roots=@((Join-Path $job 'blue.png'));$profile.OrientationEnabled=$false;$profile.MinResolutionEnabled=$false}
$config | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $job 'config.json') -Encoding UTF8
$desktop=[Wallpaper.Desktop]::Open();$original=@();$oldPosition=$desktop.GetPosition()
$observations=[Collections.Generic.List[object]]::new()
$dc=[IntPtr]::Zero;$p=$null
try {
    for($i=0;$i -lt $desktop.GetMonitorDevicePathCount();$i++){
        $id=$desktop.GetMonitorDevicePathAt($i)
        try {$rect=$desktop.GetMonitorRECT($id)}catch{continue}
        if($rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top){$original+=@{Id=$id;Path=$desktop.GetWallpaper($id);Rect=$rect}}
    }
    if(!$original.Count){throw 'No active monitors'}
    foreach($m in $original){if(!(Test-Path -LiteralPath $m.Path -PathType Leaf)){throw 'Cannot guarantee restoration of the current wallpaper; test cancelled.'}}
    $original | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $job 'desktop-before.json') -Encoding UTF8
    $dc=[PixelProbe]::GetDC([IntPtr]::Zero)
    $desktop.SetPosition(4)
    foreach($m in $original){$desktop.SetWallpaper($m.Id,(Join-Path $job 'red.png'))}
    Start-Sleep -Milliseconds 1000
    $p=Start-Process -FilePath $ApplicationPath -ArgumentList @('--run','--root',('"'+$job+'"')) -PassThru -WindowStyle Hidden
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $finishedAt=$null
    do {
        foreach($m in $original){
            $rect=$m.Rect;$pixel=[PixelProbe]::GetPixel($dc,($rect.Left+30),($rect.Bottom-90))
            $observations.Add([pscustomobject]@{TimeMs=$watch.ElapsedMilliseconds;Monitor=$m.Id;Pixel=$pixel;Red=($pixel -band 255);Blue=(($pixel -shr 16) -band 255);Wallpaper=$desktop.GetWallpaper($m.Id)})
        }
        Start-Sleep -Milliseconds 80
        if($p.HasExited -and $null -eq $finishedAt){$finishedAt=$watch.Elapsed.TotalSeconds}
    }while(($null -eq $finishedAt -or $watch.Elapsed.TotalSeconds-$finishedAt -lt 3) -and $watch.Elapsed.TotalSeconds -lt 60)
    if(!$p.HasExited){$p.Kill();throw 'Wallpaper worker timed out'}
    if($p.ExitCode -ne 0){throw ('Wallpaper worker failed: '+$p.ExitCode)}
    $observations | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $job 'observations.json') -Encoding UTF8
    Get-Content (Join-Path $job 'data\worker.log') -Encoding UTF8
    $observations | Group-Object Monitor | ForEach-Object {
        [pscustomobject]@{Samples=$_.Count;UniqueDesktopColors=@($_.Group.Pixel | Select-Object -Unique).Count;IntermediatePurple=@($_.Group | Where-Object {$_.Red -gt 20 -and $_.Red -lt 235 -and $_.Blue -gt 20 -and $_.Blue -lt 235}).Count;DistinctWallpaperFrames=@($_.Group.Wallpaper | Select-Object -Unique).Count}
    } | Format-Table
    Write-Output "Desktop validation (a covered sample point cannot prove visible animation): $job"
} finally {
    if($p -and !$p.HasExited){$p.Kill();$p.WaitForExit()}
    foreach($m in $original){if(Test-Path -LiteralPath $m.Path){$desktop.SetWallpaper($m.Id,$m.Path)}}
    $desktop.SetPosition($oldPosition);$desktop.Dispose()
    if($dc -ne [IntPtr]::Zero){[void][PixelProbe]::ReleaseDC([IntPtr]::Zero,$dc)}
}

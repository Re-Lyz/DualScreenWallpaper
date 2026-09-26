$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'ImageProcessing.ps1')
function Assert($condition,$message){if(!$condition){throw "FAILED: $message"}}
$old=[pscustomobject]@{LandscapeRoots=@('D:\old-main');PortraitRoots=@('D:\old-secondary');OnlyPortrait=$true;PortraitMinWidth=1440;PortraitMinHeight=2560;IntervalMinutes=3;AutoStart=$false}
$config=Convert-Settings $old
Assert ($config.DisplayMode -eq 'Fill') 'legacy display defaults to Fill'
$missingMode=[pscustomobject]@{SchemaVersion=2}
Assert ((Convert-Settings $missingMode).DisplayMode -eq 'Fill') 'v2 display defaults to Fill'
foreach($entry in @(@('Center',0),@('Tile',1),@('Stretch',2),@('Fit',3),@('Fill',4))) {
    Assert ((Get-WallpaperPosition $entry[0]) -eq $entry[1]) 'Windows display position mapping'
}
$invalidMode=$false
try {Convert-Settings ([pscustomobject]@{SchemaVersion=2;DisplayMode='invalid'})} catch {$invalidMode=$true}
Assert $invalidMode 'unknown display mode rejected'
Assert ($config.SchemaVersion -eq 2 -and $config.Primary.Roots[0] -eq 'D:\old-main' -and $config.Secondary.MinHeight -eq 2560 -and !$config.AutoStart) 'legacy settings migrated'
Assert (!(Test-ImageDimensions ([pscustomobject]@{Width=2560;Height=1440}) $config.Secondary)) 'portrait rejects landscape'
Assert (Test-ImageDimensions ([pscustomobject]@{Width=1440;Height=2560}) $config.Secondary) 'portrait accepts threshold'
Assert (!(Test-ImageDimensions ([pscustomobject]@{Width=1439;Height=2560}) $config.Secondary)) 'minimum width enforced'
$config.Primary.OrientationEnabled=$true; $config.Primary.MinResolutionEnabled=$true
Assert (Test-ImageDimensions ([pscustomobject]@{Width=1920;Height=1080}) $config.Primary) 'primary landscape threshold'
Assert (!(Test-ImageDimensions ([pscustomobject]@{Width=1919;Height=1080}) $config.Primary)) 'primary minimum width enforced'
Assert (!(Test-ImageDimensions ([pscustomobject]@{Width=2000;Height=2000}) $config.Primary)) 'square rejected by orientation'
$config.Secondary.OrientationEnabled=$false; $config.Secondary.MinResolutionEnabled=$false
Assert (Test-ImageDimensions ([pscustomobject]@{Width=1;Height=1}) $config.Secondary) 'disabled filters accept small square'
Assert ($config.Secondary.MinHeight -eq 2560) 'disabled filter retains parameter'
Assert ((Get-MonitorRole ([pscustomobject]@{Left=0;Top=0;Right=1080;Bottom=1920})) -eq 'Primary') 'portrait primary role'
Assert ((Get-MonitorRole ([pscustomobject]@{Left=-1920;Top=0;Right=0;Bottom=1080})) -eq 'Secondary') 'landscape secondary role'
Assert ($config.Language -eq 'zh-CN') 'legacy language defaults to Chinese'
$config.Language='en-US'
Assert ((Convert-Settings $config).Language -eq 'en-US') 'saved English preference preserved'
$signature=Index-Signature $config
$config.DisplayMode='Fit'
Assert ($signature -eq (Index-Signature $config)) 'display mode does not invalidate index'
$config.Language='zh-CN'
Assert ($signature -eq (Index-Signature $config)) 'language does not invalidate index'
$config.Language='unsupported'
Assert ((Convert-Settings $config).Language -eq 'zh-CN') 'unknown language falls back to Chinese'
$config.IntervalMinutes=7
Assert ($signature -eq (Index-Signature $config)) 'interval does not invalidate index'
$config.Primary.ExcludeFolders=@('D:\excluded')
Assert ($signature -ne (Index-Signature $config)) 'exclusions invalidate index'
Assert ((Index-Signature $old) -ne (Index-Signature $config)) 'legacy index invalidated'
$base=Join-Path $PSScriptRoot 'data'
$fixture=Join-Path $base ('test-'+[Guid]::NewGuid().ToString('N'))
try {
    Add-Type -AssemblyName System.Drawing,PresentationCore,WindowsBase
    Add-Type -Path (Join-Path $PSScriptRoot 'ImageHeader.cs')
    $rootImages=Join-Path $fixture 'images'
    $excluded=Join-Path $rootImages 'private'
    $sibling=Join-Path $rootImages 'private2'
    foreach($folder in @($excluded,$sibling,(Join-Path $excluded 'nested'))){New-Item -ItemType Directory -Path $folder -Force | Out-Null}
    $bitmap=[Drawing.Bitmap]::new(30,20)
    try {foreach($name in @('main.png','private\skip.png','private\nested\skip.png','private2\keep.png')){$bitmap.Save((Join-Path $rootImages $name),[Drawing.Imaging.ImageFormat]::Png)}} finally {$bitmap.Dispose()}
    $config=Convert-Settings (Get-Content (Join-Path $PSScriptRoot 'config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    $config.Primary.Roots=@($rootImages,$sibling)
    $config.Primary.ExcludeFolders=@($excluded.ToUpperInvariant()+'\')
    $config.Secondary.Roots=@($rootImages)
    $config.Secondary.OrientationEnabled=$false; $config.Secondary.MinResolutionEnabled=$false
    $files=@(Get-SourceImages $config.Primary)
    Assert ($files.Count -eq 2) 'excluded descendants omitted, overlapping roots deduplicated, prefix sibling preserved'
    Assert (@(Get-SourceImages $config.Secondary).Count -eq 4) 'secondary exclusion is independent'
    $config.Primary.ExcludeFolders=@($rootImages)
    Assert (@(Get-SourceImages $config.Primary).Count -eq 0) 'excluded root and separately included descendants omitted'
    $config.Primary.ExcludeFolders=@($excluded)
    # Load only index functions: no wallpaper changes, scheduled tasks or live config writes.
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Wallpaper.ps1'),[ref]$tokens,[ref]$errors)
    foreach($name in @('Build-Index')) {
        $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $data=$fixture
    Build-Index
    $index=Get-Content (Join-Path $data 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($index.Images.Primary.Count -eq 2 -and $index.Images.Secondary.Count -eq 4) 'index uses independent monitor profiles'
    $before=Get-Content (Join-Path $data 'index.json') -Raw
    $config.Primary.MinResolutionEnabled=$true
    $failed=$false
    try {Build-Index} catch {$failed=$true}
    Assert $failed 'empty eligible pool rejected'
    Assert ($before -eq (Get-Content (Join-Path $data 'index.json') -Raw)) 'failed rebuild preserves previous index'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowed=[IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output 'PASS: migration, monitor roles, filters, exclusions, index invalidation and real-image indexing.'

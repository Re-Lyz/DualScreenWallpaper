param([string]$NewVersion)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$current=(Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$version=$current
if($NewVersion){
    if($NewVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'){throw 'Version must be MAJOR.MINOR.PATCH.'}
    if([version]$NewVersion -le [version]$current){throw 'New version must be greater than the current version.'}
    $version=$NewVersion
}
$changelog=Get-Content (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
if($changelog -notmatch ('(?m)^## \['+[regex]::Escape($version)+'\]')){throw "Add a CHANGELOG.md entry for [$version] before packaging."}
# Explicit allowlist: never package local config, logs, image paths or wallpaper caches.
$files=@('00-settings.cmd','01-install.cmd','02-refresh-index.cmd','03-change-now.cmd','04-stop-and-restore.cmd','05-show-monitors.cmd','Config.ps1','Desktop.cs','ImageHeader.cs','Initialize-Config.ps1','Launch-Settings.ps1','Open-Settings.vbs','Run-Wallpaper.vbs','Settings.ps1','Wallpaper.ps1','config.example.json','README.md','CHANGELOG.md','VERSION','Release.ps1','Test-Settings.ps1')
foreach($name in $files){if(!(Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)){throw "Missing release file: $name"}}
$output=Join-Path $root 'dist'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$archive=Join-Path $output "DualScreenWallpaper-$version.zip"
if(Test-Path -LiteralPath $archive){throw "Release already exists: $archive"}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$temp=Join-Path $output ([Guid]::NewGuid().ToString('N')+'.tmp')
$zip=[IO.Compression.ZipFile]::Open($temp,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($name in $files){
        if($name -eq 'VERSION'){
            $entry=$zip.CreateEntry('VERSION'); $writer=[IO.StreamWriter]::new($entry.Open())
            try {$writer.WriteLine($version)} finally {$writer.Dispose()}
        } else {$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $root $name),$name)}
    }
} finally {$zip.Dispose()}
Move-Item -LiteralPath $temp -Destination $archive
if($NewVersion){Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value $version -Encoding ASCII}
Write-Output "Created $archive"
Write-Output 'Review and commit VERSION / CHANGELOG.md, then create the matching Git tag when ready.'

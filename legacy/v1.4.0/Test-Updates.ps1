param([switch]$LiveCheck)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'Transition.ps1')
function Assert($condition,$message){if(!$condition){throw "FAILED: $message"}}
function Assert-Throws([scriptblock]$action,[string]$message){$failed=$false;try {& $action | Out-Null}catch{$failed=$true};Assert $failed $message}
$fixture=Join-Path $PSScriptRoot ('data\updates-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
function New-TestArchive([string]$path,[hashtable]$entries) {
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {foreach($name in $entries.Keys){$writer=[IO.StreamWriter]::new($zip.CreateEntry($name).Open());try {$writer.Write($entries[$name])}finally{$writer.Dispose()}}}finally{$zip.Dispose()}
}
try {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $release=[pscustomobject]@{draft=$false;prerelease=$false;tag_name='v2.0.0';body='Test release';assets=@()}
    foreach($suffix in '.zip','-Setup.exe'){
        $name="DualScreenWallpaper-2.0.0$suffix"
        $release.assets+=@([pscustomobject]@{name=$name;browser_download_url="https://github.com/Re-Lyz/DualScreenWallpaper/releases/download/v2.0.0/$name";size=1;digest=('sha256:'+('a'*64))})
    }
    Assert ((Convert-ReleaseInfo $release '1.0.0' 'Portable').Available) 'new version detected'
    Assert (!(Convert-ReleaseInfo $release '2.0.0' 'Portable').Available) 'same version not offered'
    Assert (!(Convert-ReleaseInfo $release '3.0.0' 'Installed').Available) 'no downgrade offered'
    Assert ((Convert-ReleaseInfo $release '1.0.0' 'Installed').Name -like '*-Setup.exe') 'installed distribution selects EXE'
    $release.prerelease=$true;Assert-Throws {Convert-ReleaseInfo $release '1.0.0' 'Portable'} 'prerelease rejected';$release.prerelease=$false
    $originalUrl=$release.assets[0].browser_download_url;$release.assets[0].browser_download_url='https://example.com/evil.zip'
    Assert-Throws {Convert-ReleaseInfo $release '1.0.0' 'Portable'} 'foreign release URL rejected';$release.assets[0].browser_download_url=$originalUrl
    $valid=Join-Path $fixture 'release.zip'
    New-TestArchive $valid @{VERSION='2.0.0';'Settings.ps1'='# new settings';'Config.ps1'='# new config';'Package.ps1'='# package';'NewModule.ps1'='# new module'}
    $info=Convert-ReleaseInfo $release '1.0.0' 'Portable';$info.Size=(Get-Item $valid).Length;$info.Sha256=(Get-FileHash $valid).Hash
    Assert-UpdatePackage $info $valid
    $bad=Join-Path $fixture 'bad.zip';[IO.File]::WriteAllText($bad,'corrupt')
    Assert-Throws {Assert-UpdatePackage $info $bad} 'corrupt download rejected'
    $stage=Join-Path $fixture 'stage';Expand-UpdatePackage $valid $stage '2.0.0'
    Assert-Throws {Expand-UpdatePackage $valid (Join-Path $fixture 'wrong-version') '3.0.0'} 'package version mismatch rejected'
    foreach($name in @('../escape.ps1','C:\escape.ps1','config.json','data/state.json','nested/Settings.ps1')) {
        $path=Join-Path $fixture ([Guid]::NewGuid().ToString('N')+'.zip')
        New-TestArchive $path @{$name='bad';VERSION='2.0.0'}
        Assert-Throws {Expand-UpdatePackage $path (Join-Path $fixture ([Guid]::NewGuid().ToString('N'))) '2.0.0'} 'unsafe archive path rejected'
    }
    $root=Join-Path $fixture 'portable app';New-Item -ItemType Directory -Path $root | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'1.0.0');[IO.File]::WriteAllText((Join-Path $root 'Settings.ps1'),'# old settings')
    [IO.File]::WriteAllText((Join-Path $root 'config.json'),'{"personal":"preserve exactly"}')
    $job=Join-Path $root 'data\updates\success';New-Item -ItemType Directory -Path $job -Force | Out-Null
    $configHash=(Get-FileHash (Join-Path $root 'config.json')).Hash
    Install-PortableUpdate $root $stage $job
    Assert ([IO.File]::ReadAllText((Join-Path $root 'VERSION')) -eq '2.0.0') 'portable update applied'
    Assert ((Get-FileHash (Join-Path $root 'config.json')).Hash -eq $configHash) 'personal configuration retained'
    Restore-UpdateBackup $job
    Assert ([IO.File]::ReadAllText((Join-Path $root 'VERSION')) -eq '1.0.0' -and !(Test-Path (Join-Path $root 'NewModule.ps1'))) 'manual restore removes newly introduced files'
    # Inject one copy failure after some staged files have changed, then exercise the real rollback.
    $script:failOnce=$true;$script:failureStage=$stage
    function Copy-Item {param($LiteralPath,$Destination,[switch]$Force,$ErrorAction)
        if($script:failOnce -and $LiteralPath -eq (Join-Path $script:failureStage 'Settings.ps1')){$script:failOnce=$false;throw 'Injected copy failure'}
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction Stop
    }
    $failedJob=Join-Path $root 'data\updates\failure';New-Item -ItemType Directory -Path $failedJob -Force | Out-Null
    try {Assert-Throws {Install-PortableUpdate $root $stage $failedJob} 'copy failure reported'} finally {Remove-Item Function:\Copy-Item}
    Assert ([IO.File]::ReadAllText((Join-Path $root 'VERSION')) -eq '1.0.0' -and [IO.File]::ReadAllText((Join-Path $root 'Settings.ps1')) -eq '# old settings') 'failed update rolled back program files'
    Assert ((Get-FileHash (Join-Path $root 'config.json')).Hash -eq $configHash) 'failed update retained settings'
    # Launch the actual detached updater against an isolated portable installation.
    $applyJob=Join-Path $root 'data\updates\apply';New-Item -ItemType Directory -Path $applyJob -Force | Out-Null
    Copy-Item $valid (Join-Path $applyJob $info.Name)
    $info | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $applyJob 'release-info.json') -Encoding UTF8
    @{Root=$root} | ConvertTo-Json | Set-Content (Join-Path $applyJob 'request.json') -Encoding UTF8
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'UpdateApply.ps1') -Job $applyJob -NonInteractive
    Assert ($LASTEXITCODE -eq 0) 'detached updater completed'
    Assert ((Get-Content (Join-Path $applyJob 'apply-result.json') -Raw | ConvertFrom-Json).Success) 'updater recorded success'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'UpdateApply.ps1') -Job $applyJob -Restore -NonInteractive
    Assert ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText((Join-Path $root 'VERSION')) -eq '1.0.0') 'detached recovery restored previous version'
    # Test crossfade pixels, real intermediate JPEGs and direct fallback using an in-memory desktop boundary.
    $red=[Drawing.Bitmap]::new(40,30);$blue=[Drawing.Bitmap]::new(40,30)
    $g=[Drawing.Graphics]::FromImage($red);$g.Clear([Drawing.Color]::Red);$g.Dispose()
    $g=[Drawing.Graphics]::FromImage($blue);$g.Clear([Drawing.Color]::Blue);$g.Dispose()
    try {
        $blend=New-BlendFrame $red $blue 0.5
        try {$pixel=$blend.GetPixel(10,10);Assert ($pixel.R -gt 110 -and $pixel.R -lt 145 -and $pixel.B -gt 110 -and $pixel.B -lt 145) 'crossfade alpha blends old and new image'}finally{$blend.Dispose()}
        $old=Join-Path $fixture 'old.jpg';$new=Join-Path $fixture 'new.jpg';$red.Save($old,[Drawing.Imaging.ImageFormat]::Jpeg);$blue.Save($new,[Drawing.Imaging.ImageFormat]::Jpeg)
    }finally{$red.Dispose();$blue.Dispose()}
    $desktop=[pscustomobject]@{Current=$old;Calls=[Collections.Generic.List[string]]::new()}
    $desktop | Add-Member ScriptMethod GetWallpaper {param($id) return $this.Current}
    $desktop | Add-Member ScriptMethod GetBackgroundColor {return 0}
    $desktop | Add-Member ScriptMethod SetWallpaper {param($id,$path) $this.Calls.Add($path);$this.Current=$path}
    $monitor=[pscustomobject]@{Id='sample';Width=40;Height=30}
    Set-WallpaperWithTransition $desktop $monitor $new 'Fill' 'CrossFade' 4 (Join-Path $fixture 'sample')
    Assert ($desktop.Calls.Count -eq 9 -and $desktop.Current -eq $new) 'crossfade ends on final cache after eight frames'
    $desktop.Calls.Clear();$desktop.Current='missing.jpg'
    Set-WallpaperWithTransition $desktop $monitor $new 'Fill' 'CrossFade' 4 (Join-Path $fixture 'sample')
    Assert ($desktop.Calls.Count -eq 1 -and $desktop.Current -eq $new) 'missing old wallpaper falls back to direct switching'
    $desktop.Calls.Clear();Set-WallpaperWithTransition $desktop $monitor $old 'Fill' 'Instant' 4 (Join-Path $fixture 'sample')
    Assert ($desktop.Calls.Count -eq 1) 'instant mode avoids intermediate frames'
    $configuration=Convert-Settings ([pscustomobject]@{SchemaVersion=2})
    Assert ($configuration.TransitionEffect -eq 'Instant') 'old settings default to instant'
    $signature=Index-Signature $configuration;$configuration.TransitionEffect='CrossFade'
    Assert ((Index-Signature $configuration) -eq $signature) 'effect does not invalidate image index'
    if($LiveCheck) {
        $metadata=Join-Path $fixture 'github.json'
        Save-UpdateHttpFile 'https://api.github.com/repos/Re-Lyz/DualScreenWallpaper/releases/latest' $metadata 2MB
        $live=Convert-ReleaseInfo (Get-Content $metadata -Raw -Encoding UTF8 | ConvertFrom-Json) '0.0.0' 'Portable'
        $download=Join-Path $fixture $live.Name;Save-UpdateHttpFile $live.Url $download $live.Size;Assert-UpdatePackage $live $download
        Write-Output "PASS: live GitHub release v$($live.Version) and SHA-256 verified download."
    }
    Write-Output 'PASS: release validation, package safety, portable update/rollback/recovery, crossfade and fallback. No real wallpaper changes.'
}finally {
    $resolved=[IO.Path]::GetFullPath($fixture);$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'data')).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe update test cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

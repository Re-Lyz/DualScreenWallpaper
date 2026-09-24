# No network call runs when this file is loaded. All checks are user initiated.
function Get-DistributionKind([string]$root) {
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1'
    $registration=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if($registration.InstallLocation -and [IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\') -eq [IO.Path]::GetFullPath($root).TrimEnd('\')){return 'Installed'}
    return 'Portable'
}
function Convert-ReleaseInfo($release,[string]$current,[ValidateSet('Installed','Portable')][string]$kind) {
    if($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'){throw 'No supported stable release was returned.'}
    $version=$release.tag_name.Substring(1)
    $suffix=if($kind -eq 'Installed'){'-Setup.exe'}else{'.zip'}
    $name="DualScreenWallpaper-$version$suffix"
    $asset=@($release.assets | Where-Object name -CEQ $name)
    if($asset.Count -ne 1){throw "Release package is missing: $name"}
    $url="https://github.com/Re-Lyz/DualScreenWallpaper/releases/download/v$version/$name"
    if($asset[0].browser_download_url -cne $url -or $asset[0].digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or $asset[0].size -le 0 -or $asset[0].size -gt 100MB){throw 'Release asset metadata is invalid or has no SHA-256 digest.'}
    [pscustomobject]@{CurrentVersion=$current;Version=$version;Available=([version]$version -gt [version]$current);Kind=$kind;Notes=[string]$release.body;ReleaseUrl="https://github.com/Re-Lyz/DualScreenWallpaper/releases/tag/v$version";Name=$name;Url=$url;Size=[long]$asset[0].size;Sha256=$asset[0].digest.Substring(7)}
}
function Save-UpdateHttpFile([string]$url,[string]$destination,[long]$limit) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    for($redirect=0;$redirect -lt 6;$redirect++) {
        $uri=[uri]$url
        if($uri.Scheme -ne 'https' -or $uri.Host -notin 'api.github.com','github.com','release-assets.githubusercontent.com','objects.githubusercontent.com'){throw 'Untrusted update download destination.'}
        $request=[Net.HttpWebRequest]::Create($uri); $request.UserAgent='DualScreenWallpaper-Updater'; $request.Accept='application/vnd.github+json'
        $request.AllowAutoRedirect=$false; $request.Timeout=15000; $request.ReadWriteTimeout=30000
        $response=$null
        try {
            $response=$request.GetResponse()
            if([int]$response.StatusCode -in 301,302,303,307,308){$url=[uri]::new($uri,$response.Headers['Location']).AbsoluteUri; continue}
            if($response.ContentLength -gt $limit){throw 'Update response exceeds the size limit.'}
            $inputStream=$response.GetResponseStream(); $outputStream=[IO.File]::Create($destination)
            try {
                $buffer=New-Object byte[] 65536; $total=0L
                while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){$total+=$count; if($total -gt $limit){throw 'Update response exceeds the size limit.'}; $outputStream.Write($buffer,0,$count)}
            } finally {$inputStream.Dispose();$outputStream.Dispose()}
            return
        } finally {if($response){$response.Dispose()}}
    }
    throw 'Too many update redirects.'
}
function Assert-UpdatePackage($info,[string]$path) {
    if($info.Version -notmatch '^\d+\.\d+\.\d+$' -or $info.Kind -notin 'Installed','Portable' -or $info.Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid update request.'}
    $name='DualScreenWallpaper-'+$info.Version+$(if($info.Kind -eq 'Installed'){'-Setup.exe'}else{'.zip'})
    if($info.Name -cne $name -or $info.Url -cne "https://github.com/Re-Lyz/DualScreenWallpaper/releases/download/v$($info.Version)/$name"){throw 'Invalid package source.'}
    if((Get-Item -LiteralPath $path).Length -ne $info.Size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $info.Sha256){throw 'Downloaded package failed SHA-256 or size verification.'}
}
function Test-UpdateProgramName([string]$name) {
    # Packages may add new root-level modules, but cannot replace personal data or escape the installation.
    return ($name -ceq 'VERSION' -or $name -ceq 'config.example.json' -or $name -match '^[A-Za-z0-9][A-Za-z0-9._-]*\.(ps1|cs|vbs|cmd|md|iss)$')
}
function Expand-UpdatePackage([string]$path,[string]$stage,[string]$version) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    if(Test-Path -LiteralPath $stage){throw 'Update staging directory already exists.'}
    $archive=[IO.Compression.ZipFile]::OpenRead($path)
    try {
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $total=0L
        if($archive.Entries.Count -gt 500){throw 'Too many package entries.'}
        foreach($entry in $archive.Entries){
            if(!(Test-UpdateProgramName $entry.FullName) -or !$names.Add($entry.FullName)){throw "Unsafe or duplicate package entry: $($entry.FullName)"}
            $total+=$entry.Length; if($total -gt 100MB){throw 'Unpacked update exceeds the size limit.'}
        }
        foreach($required in 'VERSION','Settings.ps1','Config.ps1','Package.ps1'){if(!$names.Contains($required)){throw "Incomplete package: $required"}}
        $reader=[IO.StreamReader]::new($archive.GetEntry('VERSION').Open())
        try {if($reader.ReadToEnd().Trim() -cne $version){throw 'Package version does not match the release.'}} finally {$reader.Dispose()}
        New-Item -ItemType Directory -Path $stage | Out-Null
        foreach($entry in $archive.Entries){[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $stage $entry.FullName))}
    } finally {$archive.Dispose()}
}
function Assert-UpdateRoot([string]$root) {
    $full=[IO.Path]::GetFullPath($root).TrimEnd('\')
    if($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\') -or !(Test-Path -LiteralPath (Join-Path $full 'Settings.ps1'))){throw 'Invalid application directory.'}
    if((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Updates through a junction or symlink are not supported.'}
    return $full
}
function New-UpdateBackup([string]$root,[string]$job,[string[]]$newNames) {
    $backup=Join-Path $job 'backup'; New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    $files=@(Get-ChildItem -LiteralPath $root -File | Where-Object {Test-UpdateProgramName $_.Name} | ForEach-Object {$_.Name})
    $files+=@('config.json','data\original.json','data\state.json') | Where-Object {Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf}
    foreach($name in $files){
        $source=Join-Path $root $name
        if((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Cannot back up linked application files.'}
        $destination=Join-Path $backup $name; New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
    $manifest=[ordered]@{Root=$root;Files=$files;Added=@($newNames | Where-Object {$_ -notin $files});Created=(Get-Date).ToString('o')}
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $job 'backup.json') -Encoding UTF8
    return $manifest
}
function Restore-UpdateBackup([string]$job) {
    $manifest=Get-Content -LiteralPath (Join-Path $job 'backup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $root=Assert-UpdateRoot $manifest.Root
    foreach($name in $manifest.Files){if(!(Test-UpdateProgramName $name) -and $name -notin 'config.json','data\original.json','data\state.json'){throw 'Invalid backup manifest.'}}
    foreach($name in $manifest.Added){if(!(Test-UpdateProgramName $name)){throw 'Invalid backup manifest.'}}
    foreach($name in $manifest.Files){if(!(Test-Path -LiteralPath (Join-Path (Join-Path $job 'backup') $name) -PathType Leaf)){throw 'Backup is incomplete; restore cancelled before changing files.'}}
    foreach($name in $manifest.Files){Copy-Item -LiteralPath (Join-Path (Join-Path $job 'backup') $name) -Destination (Join-Path $root $name) -Force}
    foreach($name in $manifest.Added){$path=Join-Path $root $name; if(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force}}
}
function Install-PortableUpdate([string]$root,[string]$stage,[string]$job) {
    $root=Assert-UpdateRoot $root
    $files=@(Get-ChildItem -LiteralPath $stage -File)
    foreach($file in $files){
        if(!(Test-UpdateProgramName $file.Name)){throw 'Unsafe staged file.'}
        $target=Join-Path $root $file.Name
        if((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).PSIsContainer -or ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint))){throw 'Update target is a directory or link.'}
    }
    $null=New-UpdateBackup $root $job @($files.Name)
    try {
        foreach($file in $files){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $root $file.Name) -Force -ErrorAction Stop}
    } catch {
        $failure=$_
        Restore-UpdateBackup $job
        throw "Update failed; previous program files and settings were restored. $failure"
    }
}

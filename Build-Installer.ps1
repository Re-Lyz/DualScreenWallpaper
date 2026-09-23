param([string]$CompilerPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Package.ps1')
$version=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION.'}
if(!$CompilerPath) {
    $candidates=@((Join-Path $PSScriptRoot 'data\build-tools\inno\ISCC.exe'),"${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe","$env:ProgramFiles\Inno Setup 7\ISCC.exe")
    $command=Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if($command){$candidates=@($command.Source)+$candidates}
    $CompilerPath=$candidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
}
if(!$CompilerPath -or !(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Install Inno Setup 6.7+ or pass -CompilerPath to ISCC.exe.'}
$output=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$target=Join-Path $output "DualScreenWallpaper-$version-Setup.exe"
if(Test-Path -LiteralPath $target){throw "Installer already exists: $target"}
$stage=Join-Path $output ('installer-stage-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    foreach($name in Get-PackageFiles) {
        $source=Join-Path $PSScriptRoot $name
        if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing package file: $name"}
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name)
    }
    & $CompilerPath "/DStageDir=$stage" "/DAppVersion=$version" "/DOutputDir=$output" (Join-Path $PSScriptRoot 'Installer.iss')
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $target)){throw 'Installer compilation failed.'}
    Get-FileHash -LiteralPath $target -Algorithm SHA256 | Format-List
    Write-Output "Created $target"
} finally {
    $allowed=[IO.Path]::GetFullPath($output).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($stage)
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe staging cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

param([string]$DotnetPath,[switch]$FrameworkDependent,[switch]$Installer,[switch]$TestInstaller)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$DotnetPath){$local=Join-Path $repo 'data\build-tools\dotnet10\dotnet.exe';$DotnetPath=if(Test-Path $local){$local}else{'dotnet'}}
$env:DOTNET_CLI_HOME=Join-Path $repo 'data\dotnet-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$version=(Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if($version -ne '2.0.0'){throw 'Synchronize the project, updater and installer versions before changing VERSION.'}
$flavor=if($FrameworkDependent){'framework'}else{'standalone'}
$stage=Join-Path $repo ('dist\csharp-v2-'+$flavor)
Push-Location $PSScriptRoot
try {
    $selfContained=if($FrameworkDependent){'false'}else{'true'}
    & $DotnetPath publish DualScreenWallpaper.App -c Release -r win-x64 --self-contained $selfContained -p:SatelliteResourceLanguages=en -p:DebugType=None -p:DebugSymbols=false --source https://api.nuget.org/v3/index.json -o $stage
    if($LASTEXITCODE -ne 0){throw 'Publish failed.'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Destination $stage -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $stage -Force
    Copy-Item -LiteralPath (Join-Path $repo 'config.example.json') -Destination $stage -Force
    if(!$FrameworkDependent){
        $sdkRoot=Split-Path (Get-Command $DotnetPath).Source
        foreach($legal in @('LICENSE.txt','ThirdPartyNotices.txt')){Copy-Item -LiteralPath (Join-Path $sdkRoot $legal) -Destination $stage -Force}
    }
    $launchers=@{'00-settings.cmd'='';'01-install.cmd'='--apply';'02-refresh-index.cmd'='--index';'03-change-now.cmd'='--run';'04-stop-and-restore.cmd'='--stop';'05-show-monitors.cmd'=''}
    foreach($name in $launchers.Keys){
        $content='@echo off'+"`r`n"+'start "" "%~dp0DualScreenWallpaper.exe" '+$launchers[$name]+"`r`n"
        [IO.File]::WriteAllText((Join-Path $stage $name),$content,[Text.Encoding]::ASCII)
    }
    if(Get-ChildItem -LiteralPath $stage -Directory){throw 'The updater currently requires root-level package files.'}
    foreach($file in Get-ChildItem -LiteralPath $stage -File){
        $allowed=$file.Name -match '^(DualScreenWallpaper\.exe|createdump\.exe|.+\.dll|DualScreenWallpaper\.deps\.json|DualScreenWallpaper\.runtimeconfig\.json|VERSION|README\.md|config\.example\.json|LICENSE\.txt|ThirdPartyNotices\.txt)$' -or $launchers.ContainsKey($file.Name)
        if(!$allowed){throw "Unexpected publish file; use a clean staging directory: $($file.Name)"}
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Linked publish file: $($file.Name)"}
    }
    $suffix=if($FrameworkDependent){'-FrameworkDependent'}else{''}
    $zip=Join-Path $repo "dist\DualScreenWallpaper-$version$suffix.zip"
    if(Test-Path -LiteralPath $zip){throw "Archive exists: $zip"}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
    Get-FileHash -LiteralPath $zip
    if($Installer -or $TestInstaller){
        if($FrameworkDependent){throw 'The installer must include its runtime.'}
        $compiler=Join-Path $repo 'data\build-tools\inno\ISCC.exe'
        if(!(Test-Path $compiler)){throw 'Inno Setup compiler not found.'}
        $defines=@("/DStageDir=$stage",('/DOutputDir='+(Join-Path $repo 'dist')))
        if($TestInstaller){$defines+=@('/DAppGuid={B695E6E3-CEAA-4D45-B76D-C329785803A8}','/DOutputName=DualScreenWallpaper-2.0.0-TestSetup')}
        & $compiler @defines (Join-Path $PSScriptRoot 'Installer.iss')
        if($LASTEXITCODE -ne 0){throw 'Installer compilation failed.'}
    }
    Write-Output "Published $stage"
}finally{Pop-Location}

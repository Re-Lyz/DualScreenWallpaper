param([string]$DotnetPath,[string]$CompilerPath,[string]$OutputDirectory,[switch]$FrameworkDependent,[switch]$Installer,[switch]$TestInstaller)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$DotnetPath){$local=Join-Path $repo 'data\build-tools\dotnet10\dotnet.exe';$DotnetPath=if(Test-Path $local){$local}else{'dotnet'}}
$env:DOTNET_CLI_HOME=Join-Path $repo 'data\dotnet-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$version=(Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'){throw 'VERSION must be MAJOR.MINOR.PATCH.'}
if($FrameworkDependent -and ($Installer -or $TestInstaller)){throw 'The installer must include its runtime.'}
if($Installer -and $TestInstaller){throw 'Choose either Installer or TestInstaller.'}
$output=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $repo 'dist'}
$flavor=if($FrameworkDependent){'framework'}else{'standalone'}
$suffix=if($FrameworkDependent){'-FrameworkDependent'}else{''}
if($TestInstaller){$suffix='-Test'}
$zip=Join-Path $output "DualScreenWallpaper-$version$suffix.zip"
$setupName="DualScreenWallpaper-$version-"+$(if($TestInstaller){'TestSetup'}else{'Setup'})
# Check destinations before building, so a rejected repeat build never changes previous output.
foreach($target in @($zip,$zip+'.sha256')){if(Test-Path -LiteralPath $target){throw "Output already exists: $target. Choose a different OutputDirectory."}}
if($Installer -or $TestInstaller){
    if(Test-Path -LiteralPath (Join-Path $output ($setupName+'.exe'))){throw 'Installer output already exists.'}
    if(!$CompilerPath){$local=Join-Path $repo 'data\build-tools\inno\ISCC.exe';$CompilerPath=if(Test-Path $local){$local}else{(Get-Command ISCC.exe -ErrorAction Stop).Source}}
    if(!(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Inno Setup compiler not found.'}
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage=Join-Path $output ('staging\'+$version+'-'+$flavor+'-'+[Guid]::NewGuid().ToString('N'))
Push-Location $PSScriptRoot
try {
    $selfContained=if($FrameworkDependent){'false'}else{'true'}
    & $DotnetPath publish DualScreenWallpaper.App -c Release -r win-x64 --self-contained $selfContained -p:SatelliteResourceLanguages=en -p:DebugType=None -p:DebugSymbols=false --source https://api.nuget.org/v3/index.json -o $stage
    if($LASTEXITCODE -ne 0){throw 'Publish failed.'}
    $actual=[Reflection.AssemblyName]::GetAssemblyName((Join-Path $stage 'DualScreenWallpaper.dll')).Version.ToString(3)
    if($actual -ne $version){throw 'Compiled version does not match VERSION.'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $repo 'config.example.json') -Destination $stage
    if(!$FrameworkDependent){
        $sdkRoot=Split-Path (Get-Command $DotnetPath).Source
        foreach($legal in @('LICENSE.txt','ThirdPartyNotices.txt')){Copy-Item -LiteralPath (Join-Path $sdkRoot $legal) -Destination $stage -Force}
    }
    $launchers=@{'00-settings.cmd'='';'01-install.cmd'='--apply';'02-refresh-index.cmd'='--index';'03-change-now.cmd'='--run';'04-stop-and-restore.cmd'='--stop';'05-show-monitors.cmd'=''}
    foreach($name in $launchers.Keys){
        $content='@echo off'+"`r`n"+'start "" "%~dp0DualScreenWallpaper.exe" '+$launchers[$name]+"`r`n"
        [IO.File]::WriteAllText((Join-Path $stage $name),$content,[Text.Encoding]::ASCII)
    }
    if(Get-ChildItem -LiteralPath $stage -Directory){throw 'The updater requires root-level package files.'}
    foreach($file in Get-ChildItem -LiteralPath $stage -File){
        $allowed=$file.Name -match '^(DualScreenWallpaper\.exe|createdump\.exe|.+\.dll|DualScreenWallpaper\.deps\.json|DualScreenWallpaper\.runtimeconfig\.json|VERSION|README\.md|config\.example\.json|LICENSE\.txt|ThirdPartyNotices\.txt)$' -or $launchers.ContainsKey($file.Name)
        if(!$allowed){throw "Unexpected publish file: $($file.Name)"}
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Linked publish file: $($file.Name)"}
    }
    if($Installer -or $TestInstaller){
        $defines=@("/DStageDir=$stage","/DOutputDir=$output","/DAppVersion=$version","/DOutputName=$setupName")
        if($TestInstaller){$defines+='/DAppGuid={B695E6E3-CEAA-4D45-B76D-C329785803A8}'}
        & $CompilerPath @defines (Join-Path $PSScriptRoot 'Installer.iss')
        if($LASTEXITCODE -ne 0){throw 'Installer compilation failed.'}
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
    $artifacts=@($zip)
    if($Installer -or $TestInstaller){$artifacts+=Join-Path $output ($setupName+'.exe')}
    foreach($artifact in $artifacts){$hash=(Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant();[IO.File]::WriteAllText($artifact+'.sha256',$hash+'  '+[IO.Path]::GetFileName($artifact)+"`n",[Text.Encoding]::ASCII)}
    Write-Output "Published $stage"
    Write-Output "Archive $zip"
}finally{Pop-Location}

param([string]$DotnetPath,[switch]$SkipUi)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$DotnetPath){$local=Join-Path $repo 'data\build-tools\dotnet10\dotnet.exe';$DotnetPath=if(Test-Path $local){$local}else{'dotnet'}}
$env:DOTNET_CLI_HOME=Join-Path $repo 'data\dotnet-home'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$job=Join-Path $repo ('data\regression-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $job | Out-Null
Push-Location $PSScriptRoot
try {
    & $DotnetPath run --project DualScreenWallpaper.Tests -c Release
    if($LASTEXITCODE -ne 0){throw 'Configuration regression tests failed.'}
    $app=Join-Path $job 'app'
    & $DotnetPath publish DualScreenWallpaper.App -c Release -r win-x64 --self-contained false --source https://api.nuget.org/v3/index.json -o $app
    if($LASTEXITCODE -ne 0){throw 'Publish failed.'}
    $report=Join-Path $job 'integration.json'
    $exe=Join-Path $app 'DualScreenWallpaper.exe'
    $start=[Diagnostics.ProcessStartInfo]::new($exe,('--self-test --report "'+$report+'"'))
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($start)
    $errors=$process.StandardError.ReadToEndAsync()
    try {
        if(!$process.WaitForExit(60000)){$process.Kill();throw 'Integration tests timed out.'}
        [IO.File]::WriteAllText((Join-Path $job 'errors.txt'),$errors.GetAwaiter().GetResult())
        if($process.ExitCode -ne 0){throw ('Integration failed: '+[IO.File]::ReadAllText((Join-Path $job 'errors.txt')))}
    }finally{$process.Dispose()}
    Get-Content -LiteralPath $report
    if(!$SkipUi){& (Join-Path $PSScriptRoot 'Test-Preview.ps1') -ApplicationPath $exe}
    Write-Output "PASS. Reports: $job"
}finally{Pop-Location}

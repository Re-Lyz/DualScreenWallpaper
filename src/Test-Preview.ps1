param([string]$ConfigPath,[string]$ApplicationPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$ConfigPath){$ConfigPath=Join-Path $repo 'config.example.json'}
if(!$ApplicationPath){$ApplicationPath=Join-Path $repo 'dist\csharp-v2\DualScreenWallpaper.exe'}
$ConfigPath=[IO.Path]::GetFullPath($ConfigPath)
$ApplicationPath=[IO.Path]::GetFullPath($ApplicationPath)
$job=Join-Path $repo ('data\csharp-validation-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $job -Force | Out-Null
function Invoke-Preview([string]$config,[string]$report) {
    $args=@('--config',('"'+$config+'"'),'--smoke','--report',('"'+$report+'"'))
    $process=Start-Process -FilePath $ApplicationPath -ArgumentList $args -PassThru -WindowStyle Hidden
    try {
        if(!$process.WaitForExit(20000)){$process.Kill();throw 'Preview timed out.'}
        return $process.ExitCode
    } finally {$process.Dispose()}
}
$hash=(Get-FileHash -LiteralPath $ConfigPath).Hash
$results=@()
foreach($i in 1..5){
    $report=Join-Path $job "run-$i.json"
    if((Invoke-Preview $ConfigPath $report) -ne 0){throw "UI launch $i failed."}
    $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if(!$result.Success -or !$result.LoadedConfiguration){throw 'UI did not load configuration.'}
    if(!(Test-Path -LiteralPath ($report+'.png'))){throw 'Missing screenshot.'}
    $results+=$result
}
$report=Join-Path $job 'run-1.json'
$reportHash=(Get-FileHash -LiteralPath $report).Hash
if((Invoke-Preview $ConfigPath $report) -eq 0 -or (Get-FileHash -LiteralPath $report).Hash -ne $reportHash){throw 'Existing report protection failed.'}
$bad=Join-Path $job 'invalid.json'
Set-Content -LiteralPath $bad -Value '{"SchemaVersion":99}' -Encoding UTF8
if((Invoke-Preview $bad (Join-Path $job 'invalid-report.json')) -eq 0){throw 'Invalid configuration was accepted.'}
if((Get-FileHash -LiteralPath $ConfigPath).Hash -ne $hash){throw 'Configuration was modified.'}
$results | Select-Object StartupMilliseconds,WorkingSetBytes,MonitorCount,RemoteSession | Format-Table
Write-Output "PASS: five UI launches, invalid configuration rejection, existing report protection, unchanged input. Reports: $job"

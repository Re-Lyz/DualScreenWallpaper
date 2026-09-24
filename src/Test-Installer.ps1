# Uses a separate AppId and disposable directory; does not replace the user's installation.
param([string]$InstallerPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
if(!$InstallerPath){$InstallerPath=Join-Path $repo 'data\csharp-installer-validation\DualScreenWallpaper-2.0.0-TestSetup.exe'}
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B695E6E3-CEAA-4D45-B76D-C329785803A8}_is1'
if(Test-Path $key){throw 'A test installation already exists; inspect it before running again.'}
$job=Join-Path $repo ('data\csharp-install-test-'+[Guid]::NewGuid().ToString('N'))
$root=Join-Path $job 'application';New-Item -ItemType Directory -Path $root -Force | Out-Null
$config=Get-Content (Join-Path $repo 'config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$config.AutoStart=$false;$config.SetupCompleted=$true
$config | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'config.json') -Encoding UTF8
$hash=(Get-FileHash (Join-Path $root 'config.json')).Hash
Set-Content (Join-Path $root 'VERSION') '1.4.0' -Encoding ASCII
$taskBefore=Get-ScheduledTask -TaskName 'DualScreenWallpaper-1Minute' -ErrorAction SilentlyContinue
$taskXml=if($taskBefore){Export-ScheduledTask -TaskName $taskBefore.TaskName}else{$null}
$group='DualScreenWallpaper Test '+[Guid]::NewGuid().ToString('N')
$arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="'+$root+'"'),('/GROUP="'+$group+'"'),('/LOG="'+(Join-Path $job 'install.log')+'"'))
try {
    foreach($attempt in 1..2){
        $p=Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
        if($p.ExitCode -ne 0){throw "Install/reinstall failed: $($p.ExitCode)"}
        if((Get-Content (Join-Path $root 'VERSION') -Raw).Trim() -ne '2.0.0'){throw 'Wrong installed version.'}
        if((Get-FileHash (Join-Path $root 'config.json')).Hash -ne $hash){throw 'Installer changed configuration.'}
    }
    if(!(Test-Path $key)){throw 'Missing test uninstall registration.'}
    $report=Join-Path $job 'ui.json'
    $p=Start-Process -FilePath (Join-Path $root 'DualScreenWallpaper.exe') -ArgumentList @('--smoke','--report',('"'+$report+'"')) -PassThru -Wait -WindowStyle Hidden
    if($p.ExitCode -ne 0){throw 'Installed UI smoke failed.'}
    Set-Content (Join-Path $root 'VERSION') '9.0.0' -Encoding ASCII
    $p=Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
    if($p.ExitCode -eq 0){throw 'Installer allowed a downgrade.'}
    Set-Content (Join-Path $root 'VERSION') '2.0.0' -Encoding ASCII
}finally{
    $uninstaller=Join-Path $root 'unins000.exe'
    if(Test-Path $uninstaller){$p=Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru -Wait -WindowStyle Hidden;if($p.ExitCode -ne 0){throw 'Test uninstall failed.'}}
}
if(Test-Path $key){throw 'Test registration remains.'}
if((Get-FileHash (Join-Path $root 'config.json')).Hash -ne $hash){throw 'Uninstall changed retained configuration.'}
$taskAfter=Get-ScheduledTask -TaskName 'DualScreenWallpaper-1Minute' -ErrorAction SilentlyContinue
if([bool]$taskBefore -ne [bool]$taskAfter){throw 'User slideshow task changed.'}
if($taskAfter -and (Export-ScheduledTask -TaskName $taskAfter.TaskName) -ne $taskXml){throw 'User slideshow task definition changed.'}
Write-Output "PASS: isolated upgrade/reinstall, configuration preservation, UI startup, downgrade rejection, uninstall. User task unchanged. Logs: $job"

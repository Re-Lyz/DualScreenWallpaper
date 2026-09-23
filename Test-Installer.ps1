# Real installer integration test. Uses a fresh workspace directory and temporary Start Menu group.
# Refuses to run if an installed copy already owns the application's uninstall registration.
param([string]$InstallerPath)
$ErrorActionPreference='Stop'
function Assert($condition,$message){if(!$condition){throw "FAILED: $message"}}
$version=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if(!$InstallerPath){$InstallerPath=Join-Path $PSScriptRoot "dist\DualScreenWallpaper-$version-Setup.exe"}
$InstallerPath=[IO.Path]::GetFullPath($InstallerPath)
if(!(Test-Path -LiteralPath $InstallerPath -PathType Leaf)){throw 'Build the installer first.'}
$regKeys=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1','HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1')
foreach($key in $regKeys){if(Test-Path -LiteralPath $key){throw 'An installed copy already exists; use a separate test account or VM.'}}
$tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object {$_.TaskName -eq 'DualScreenWallpaper-1Minute' -and $_.TaskPath -eq '\'})
$taskBefore=if($tasks.Count){Export-ScheduledTask -TaskName 'DualScreenWallpaper-1Minute' -TaskPath '\'}else{''}
$tag=[Guid]::NewGuid().ToString('N')
$fixture=Join-Path $PSScriptRoot ('data\installer-test-'+$tag)
$install=Join-Path $fixture 'installed app'
$group='DualScreenWallpaper Test '+$tag
$shortcut=Join-Path ([Environment]::GetFolderPath('Programs')) ($group+'\Settings.lnk')
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
function Invoke-TestProcess([string]$exe,[string[]]$arguments) {
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if(!$process.WaitForExit(45000)){$process.Kill(); throw 'Test process timed out.'}
    $process.Refresh(); return $process.ExitCode
}
$baseArgs=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="'+$install+'"'),('/GROUP="'+$group+'"'),'/TASKS=')
$uninstalled=$false
try {
    Assert ((Invoke-TestProcess $InstallerPath ($baseArgs+('/LOG="'+(Join-Path $fixture 'fresh.log')+'"'))) -eq 0) 'fresh installation'
    Assert (Test-Path -LiteralPath (Join-Path $install 'Settings.ps1')) 'program files installed'
    Assert (!(Test-Path -LiteralPath (Join-Path $install 'config.json'))) 'installer contains no personal configuration'
    Assert (Test-Path -LiteralPath $shortcut) 'Start Menu shortcut created'
    $shell=New-Object -ComObject WScript.Shell
    try {$link=$shell.CreateShortcut($shortcut); Assert ($link.Arguments -eq ('"'+(Join-Path $install 'Open-Settings.vbs')+'"')) 'shortcut points to test installation'} finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    $ps="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Assert ((Invoke-TestProcess $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $install 'Settings.ps1')+'"'),'-SmokeTest')) -eq 0) 'installed settings smoke test'
    $configPath=Join-Path $install 'config.json'
    $before=(Get-FileHash -LiteralPath $configPath).Hash
    $sentinel=Join-Path $install 'data\keep.txt'; [IO.File]::WriteAllText($sentinel,'retained user data')
    Set-Content -LiteralPath (Join-Path $install 'VERSION') -Value '1.2.9' -Encoding ASCII
    Assert ((Invoke-TestProcess $InstallerPath ($baseArgs+('/LOG="'+(Join-Path $fixture 'upgrade.log')+'"'))) -eq 0) 'in-place upgrade'
    Assert ((Get-FileHash -LiteralPath $configPath).Hash -eq $before) 'upgrade preserves configuration exactly'
    Assert ([IO.File]::ReadAllText($sentinel) -eq 'retained user data') 'upgrade preserves data'
    Set-Content -LiteralPath (Join-Path $install 'VERSION') -Value '9.9.9' -Encoding ASCII
    Assert ((Invoke-TestProcess $InstallerPath ($baseArgs+('/LOG="'+(Join-Path $fixture 'downgrade.log')+'"'))) -ne 0) 'downgrade rejected'
    Assert ((Get-FileHash -LiteralPath $configPath).Hash -eq $before) 'rejected downgrade preserves configuration'
    Set-Content -LiteralPath (Join-Path $install 'VERSION') -Value $version -Encoding ASCII
    Assert ((Invoke-TestProcess (Join-Path $install 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $fixture 'uninstall.log')+'"'))) -eq 0) 'uninstall'
    $uninstalled=$true
    Assert (!(Test-Path -LiteralPath (Join-Path $install 'Settings.ps1'))) 'uninstall removes program files'
    Assert (!(Test-Path -LiteralPath $shortcut)) 'uninstall removes shortcut'
    Assert ((Get-FileHash -LiteralPath $configPath).Hash -eq $before) 'uninstall retains configuration'
    Assert (Test-Path -LiteralPath $sentinel) 'uninstall retains user data'
    foreach($key in $regKeys){Assert (!(Test-Path -LiteralPath $key)) 'uninstall removes registration'}
    $tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object {$_.TaskName -eq 'DualScreenWallpaper-1Minute' -and $_.TaskPath -eq '\'})
    $taskAfter=if($tasks.Count){Export-ScheduledTask -TaskName 'DualScreenWallpaper-1Minute' -TaskPath '\'}else{''}
    Assert ($taskBefore -eq $taskAfter) 'existing slideshow task left unchanged'
    Write-Output "PASS: actual install, shortcut, installed UI, upgrade, downgrade rejection and uninstall. Logs: $fixture"
} finally {
    if(!$uninstalled -and (Test-Path -LiteralPath (Join-Path $install 'unins000.exe'))){
        $code=Invoke-TestProcess (Join-Path $install 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
        if($code -ne 0){Write-Warning "Test installation retained for diagnosis: $install"}
    }
}

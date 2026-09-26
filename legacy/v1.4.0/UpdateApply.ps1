# Copied to data/updates/<job>/runner before launch, so replacing program files cannot replace this process's code.
param([Parameter(Mandatory=$true)][string]$Job,[int]$ParentProcessId=0,[switch]$Restore,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
$maintenance=$null; $worker=$null; $updater=$null; $workerHeld=$false; $updateHeld=$false; $root=$null; $success=$false
function Enter-UpdateMaintenance {
    $created=$false
    $script:maintenance=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperMaintenance',[ref]$created)
    if(!$created){throw 'Another installation or update is running.'}
    $settingsHandle=$null
    if([Threading.Mutex]::TryOpenExisting('Local\DualScreenWallpaperSettings',[ref]$settingsHandle)){$settingsHandle.Dispose();throw 'Close all Settings windows before updating.'}
    $script:worker=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker')
    try {$script:workerHeld=$script:worker.WaitOne(30000)} catch [Threading.AbandonedMutexException] {$script:workerHeld=$true}
    if(!$script:workerHeld){throw 'A wallpaper operation is still running.'}
}
function Exit-UpdateMaintenance {
    if($script:workerHeld){$script:worker.ReleaseMutex();$script:workerHeld=$false}
    if($script:worker){$script:worker.Dispose();$script:worker=$null}
    if($script:maintenance){$script:maintenance.Dispose();$script:maintenance=$null}
}
try {
    if($ParentProcessId -gt 0){
        $parent=Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
        if($parent){try {if(!$parent.WaitForExit(60000)){throw 'Settings did not close. Update cancelled.'}}finally{$parent.Dispose()}}
    }
    $updater=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperUpdate')
    try {$updateHeld=$updater.WaitOne(0)} catch [Threading.AbandonedMutexException] {$updateHeld=$true}
    if(!$updateHeld){throw 'Another updater is running.'}
    $request=Get-Content -LiteralPath (Join-Path $Job 'request.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $root=Assert-UpdateRoot $request.Root
    $expectedParent=[IO.Path]::GetFullPath((Join-Path $root 'data\updates')).TrimEnd('\')+'\'
    if(![IO.Path]::GetFullPath($Job).StartsWith($expectedParent,[StringComparison]::OrdinalIgnoreCase)){throw 'Update job is outside the application update directory.'}
    Enter-UpdateMaintenance
    if($Restore) {
        Restore-UpdateBackup $Job
    } else {
        $info=Get-Content -LiteralPath (Join-Path $Job 'release-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $current=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
        if([version]$info.Version -le [version]$current){throw 'The downloaded release is not newer than this installation.'}
        if((Get-DistributionKind $root) -ne $info.Kind){throw 'Installation type changed. Check for updates again.'}
        $package=Join-Path $Job $info.Name
        Assert-UpdatePackage $info $package
        if($info.Kind -eq 'Portable') {
            $stage=Join-Path $Job ('stage-'+[Guid]::NewGuid().ToString('N'))
            Expand-UpdatePackage $package $stage $info.Version
            Install-PortableUpdate $root $stage $Job
        } else {
            $null=New-UpdateBackup $root $Job @()
            # Inno Setup takes its own maintenance lock, so release ours before starting it.
            Exit-UpdateMaintenance
            try {
                $process=Start-Process -FilePath $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="'+$root+'"'),('/LOG="'+(Join-Path $Job 'installer.log')+'"')) -WindowStyle Hidden -PassThru
                try {$process.WaitForExit(); if($process.ExitCode -ne 0){throw "Installer failed with exit code $($process.ExitCode)."}} finally {$process.Dispose()}
                Enter-UpdateMaintenance
                if((Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim() -ne $info.Version){throw 'The installed version does not match the download.'}
            } catch {
                $failure=$_
                if(!$workerHeld){Exit-UpdateMaintenance; Enter-UpdateMaintenance}
                Restore-UpdateBackup $Job
                throw "Installation failed; program files and settings were restored. $failure"
            }
        }
    }
    $success=$true
    @{Success=$true;Restored=[bool]$Restore;Time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Job 'apply-result.json') -Encoding UTF8
} catch {
    $failure=[string]$_
    @{Success=$false;Error=$failure;Time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Job 'apply-result.json') -Encoding UTF8
    if(!$NonInteractive){
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("$failure`r`n`r`nDetails and recovery files: $Job",'DualScreenWallpaper update','OK','Warning')
    }
} finally {
    Exit-UpdateMaintenance
    if($updateHeld){$updater.ReleaseMutex()}; if($updater){$updater.Dispose()}
}
if(!$NonInteractive -and $root -and (Test-Path -LiteralPath (Join-Path $root 'Launch-Settings.ps1'))){
    $null=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $root 'Launch-Settings.ps1')+'"')) -WindowStyle Hidden
}
if(!$success){exit 1}

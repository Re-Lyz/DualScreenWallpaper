$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'Language.ps1')
. (Join-Path $PSScriptRoot 'Preview.ps1')
. (Join-Path $PSScriptRoot 'Settings.Controls.ps1')
. (Join-Path $PSScriptRoot 'Settings.Persistence.ps1')
. (Join-Path $PSScriptRoot 'SetupWizard.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
function Assert($condition,$message){if(!$condition){throw "FAILED: $message"}}
function Show-Failure($text){throw $text}
$script:buttons=@(); $script:root=$PSScriptRoot; $script:uiLanguage='en-US'
$settings=Read-SettingsFile (Join-Path $PSScriptRoot 'config.example.json')
Assert (!$settings.SetupCompleted) 'new configuration requires setup'
$legacy=[pscustomobject]@{LandscapeRoots=@('D:\a');PortraitRoots=@('D:\b');OnlyPortrait=$false;PortraitMinWidth=0;PortraitMinHeight=0;IntervalMinutes=1}
Assert ((Convert-Settings $legacy).SetupCompleted) 'existing configured legacy install skips automatic setup'
$noFlag=$settings | ConvertTo-Json -Depth 6 | ConvertFrom-Json
$noFlag.PSObject.Properties.Remove('SetupCompleted'); $noFlag.Primary.Roots=@($PSScriptRoot); $noFlag.Secondary.Roots=@($PSScriptRoot)
Assert ((Convert-Settings $noFlag).SetupCompleted) 'configured v2 without flag skips setup'
$task=[pscustomobject]@{TaskName='DualScreenWallpaper-1Minute';TaskPath='\';Actions=@([pscustomobject]@{Arguments=('//B //NoLogo "'+(Join-Path $PSScriptRoot 'Run-Wallpaper.vbs')+'"')})}
Assert (Test-TaskOwnedByRoot $task $PSScriptRoot) 'owned task recognized'
Assert (!(Test-TaskOwnedByRoot $task ($PSScriptRoot+'-other'))) 'other installation not owned'
$script:mockTasks=@($task); $script:stopped=0; $script:removed=0
function Get-ScheduledTask {param($ErrorAction) $script:mockTasks}
function Stop-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:stopped++}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,$Confirm,$ErrorAction) $script:removed++}
Stop-OwnedWallpaper ($PSScriptRoot+'-other')
Assert ($script:removed -eq 0) 'foreign task left untouched'
Stop-OwnedWallpaper $PSScriptRoot
Assert ($script:removed -eq 1 -and $script:stopped -eq 1) 'owned task stopped and removed'
$script:mockTasks=@()
Stop-OwnedWallpaper $PSScriptRoot
Assert ($script:removed -eq 1) 'no task is a no-op'
$gate=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperMaintenance')
try {Assert (Test-MaintenanceActive) 'maintenance gate detected'} finally {$gate.Dispose()}
$fixture=Join-Path $PSScriptRoot ('data\setup-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$owner=[Windows.Forms.Form]::new(); $owner.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
try {
    $settings.Primary.Roots=@($fixture); $settings.Secondary.Roots=@()
    $environment=[pscustomobject]@{Checks=@('Windows PowerShell 5.1: OK','Windows Script Host: OK','Task Scheduler: OK');Failures=@();Monitors=@([pscustomobject]@{Id='main';Kind='Primary';Left=0;Top=0;Width=1920;Height=1080})}
    $before=$settings | ConvertTo-Json -Depth 6 -Compress
    foreach($lang in 'zh-CN','en-US') {
        $script:uiLanguage=$lang
        $result=Show-SetupWizard $owner $settings (Join-Path $PSScriptRoot 'data') $environment
        Assert ($result.SetupCompleted -and $result.Primary.Roots[0] -eq $fixture -and $result.Secondary.Roots[0] -eq $fixture) 'wizard returns valid staged configuration'
        Assert (!$result.Secondary.OrientationEnabled -and !$result.Secondary.MinResolutionEnabled) 'single monitor default secondary filters disabled'
        Assert (($settings | ConvertTo-Json -Depth 6 -Compress) -eq $before) 'wizard did not mutate original configuration'
        Assert ($script:buttons.Count -eq 0) 'wizard disposed controls do not leak into settings button list'
    }
    $result=Show-SetupWizard $owner $settings (Join-Path $PSScriptRoot 'data') $environment -TestAction Cancel
    Assert (!$result -and ($settings | ConvertTo-Json -Depth 6 -Compress) -eq $before) 'cancel discards staged edits'
    $environment.Failures=@('Task Scheduler')
    $result=Show-SetupWizard $owner $settings (Join-Path $PSScriptRoot 'data') $environment -TestAction Blocked
    Assert (!$result) 'prerequisite failure blocks completion even when jumping to last tab'
    Write-Output 'PASS: first-run migration, task ownership/cleanup, maintenance gate and bilingual four-step wizard.'
} finally {
    $owner.Dispose()
    $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'data')).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($fixture)
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe setup test cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

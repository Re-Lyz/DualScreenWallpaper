param([ValidateSet('Index','Run','Inspect','Install','Apply','Uninstall')][string]$Mode = 'Run', [switch]$UiLog)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
if(Test-MaintenanceActive){if($Mode -eq 'Run'){exit 0}; throw 'Installation or removal is in progress.'}
$taskName = $script:WallpaperTaskName
. (Join-Path $PSScriptRoot 'Initialize-Config.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
$config = Convert-Settings (Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$data = Join-Path $root 'data'
New-Item -ItemType Directory -Path $data -Force | Out-Null
if ($UiLog) { Start-Transcript -LiteralPath (Join-Path $data 'ui-output.log') -Force | Out-Null }
Add-Type -Path (Join-Path $root 'Desktop.cs')
. (Join-Path $PSScriptRoot 'ImageProcessing.ps1')
. (Join-Path $PSScriptRoot 'Transition.ps1')
Add-Type -AssemblyName PresentationCore,WindowsBase

function Build-Index {
    $sets = @{}; $stats = @{}; $dimensions = @{}
    foreach ($kind in 'Primary','Secondary') {
        $profile=$config.$kind
        $accepted=[Collections.Generic.List[string]]::new()
        $bad=0; $small=0; $count=0
        Get-SourceImages $profile | ForEach-Object {
            $file=$_; $count++
            if ($count % 1000 -eq 0) { Write-Host "$kind : scanned $count images..." }
            try {
                if (!$dimensions.ContainsKey($file.FullName)) { $dimensions[$file.FullName]=Get-Frame $file.FullName }
                if (!(Test-ImageDimensions $dimensions[$file.FullName] $profile)) { $small++; return }
                $accepted.Add($file.FullName)
            } catch { $bad++ }
        }
        $sets[$kind]=$accepted.ToArray()
        $stats[$kind]=@{ Scanned=$count; Eligible=$accepted.Count; Filtered=$small; Unreadable=$bad }
        Write-Host "$kind : eligible=$($accepted.Count), filtered=$small, unreadable=$bad"
        if (!$accepted.Count) { throw "No eligible images for $kind. Check folders, exclusions and filters in Settings." }
    }
    $index=@{ Created=(Get-Date).ToString('o'); Config=($config | ConvertTo-Json -Depth 6 -Compress); Images=$sets; Stats=$stats }
    $index | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Join-Path $data 'index.tmp') -Encoding UTF8
    Move-Item -LiteralPath (Join-Path $data 'index.tmp') -Destination (Join-Path $data 'index.json') -Force
}

function Run-Wallpaper {
    $indexPath = Join-Path $data 'index.json'
    if (!(Test-Path -LiteralPath $indexPath)) { throw 'Run 02-refresh-index.cmd first.' }
    $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((Index-Signature ($index.Config | ConvertFrom-Json)) -ne (Index-Signature $config)) { throw 'Configuration changed. Refresh index first.' }
    $desktop = [Wallpaper.Desktop]::Open()
    try {
        $monitors = @(Get-Monitors $desktop)
        $backup = Join-Path $data 'original.json'
        if (!(Test-Path -LiteralPath $backup)) {
            @{ Position=$desktop.GetPosition(); Monitors=@($monitors | ForEach-Object { @{Id=$_.Id; Path=$desktop.GetWallpaper($_.Id)} }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backup -Encoding UTF8
        }
        $statePath = Join-Path $data 'state.json'
        $previous = @{}
        if (Test-Path -LiteralPath $statePath) { (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $previous[$_.Name]=$_.Value } }
        $oldPosition=$desktop.GetPosition()
        $desktop.SetPosition((Get-WallpaperPosition $config.DisplayMode))
        foreach ($monitor in $monitors) {
            $pool = @(Get-PlaybackCandidates @($index.Images.($monitor.Kind)) $previous[$monitor.Id].Source $config.PlaybackOrder)
            $done = $false
            foreach ($source in $pool) {
                try {
                    $slot = 1
                    if ($previous.ContainsKey($monitor.Id)) { $slot = 1-[int]$previous[$monitor.Id].Slot }
                    $bytes = [Text.Encoding]::UTF8.GetBytes($monitor.Id)
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try { $key = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,16) } finally { $sha.Dispose() }
                    $output = Join-Path $data "$key-$slot.jpg"
                    Convert-Wallpaper $source $output
                    Set-WallpaperWithTransition $desktop $monitor $output $config.DisplayMode $config.TransitionEffect $oldPosition (Join-Path $data $key)
                    $previous[$monitor.Id] = @{Source=$source; Slot=$slot}
                    $previous | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($statePath+'.tmp') -Encoding UTF8
                    Move-Item -LiteralPath ($statePath+'.tmp') -Destination $statePath -Force
                    Write-Host "$($monitor.Kind) $($monitor.Width)x$($monitor.Height): $source"
                    $done = $true; break
                } catch { Write-Warning "$source : $_" }
            }
            if (!$done) { throw "Unable to set wallpaper for $($monitor.Kind)" }
        }
    } finally { $desktop.Dispose() }
}

$mutex = [Threading.Mutex]::new($false, 'Local\DualScreenWallpaperWorker')
$held = $false
try {
    try { $held = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held=$true }
    if (!$held) {
        if ($Mode -eq 'Run') { exit 0 }
        throw 'Another wallpaper operation is running. Try again later.'
    }
    if(Test-MaintenanceActive){if($Mode -eq 'Run'){exit 0}; throw 'Installation or removal is in progress.'}
    switch ($Mode) {
        'Index' { Build-Index }
        'Inspect' {
            $desktop = [Wallpaper.Desktop]::Open()
            try { Get-Monitors $desktop | Format-List } finally { $desktop.Dispose() }
        }
        'Run' { Run-Wallpaper }
        { $_ -in 'Install','Apply' } {
            $indexPath = Join-Path $data 'index.json'
            $rebuild = !(Test-Path -LiteralPath $indexPath)
            if (!$rebuild) {
                $old = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $rebuild = (Index-Signature ($old.Config | ConvertFrom-Json)) -ne (Index-Signature $config)
            }
            if ($rebuild) { Build-Index }
            if ($config.AutoStart -eq $false) {
                Stop-OwnedWallpaper $root
                Run-Wallpaper
                Write-Host 'Applied once. Automatic slideshow is disabled.'
                break
            }
            $exe = "$env:SystemRoot\System32\wscript.exe"
            $argument = '//B //NoLogo "' + (Join-Path $root 'Run-Wallpaper.vbs') + '"'
            $action = New-ScheduledTaskAction -Execute $exe -Argument $argument -WorkingDirectory $root
            $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
            $triggers = @((New-ScheduledTaskTrigger -AtLogOn -User $user), (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $config.IntervalMinutes)))
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
            Run-Wallpaper
            Write-Host "Installed. Interval: $($config.IntervalMinutes) minute(s). Starts automatically at logon."
        }
        'Uninstall' { Stop-OwnedWallpaper $root -Restore; Write-Host 'Stopped owned slideshow; previous static wallpaper restored where available.' }
    }
} catch {
    $log = Join-Path $data 'errors.log'
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) { Move-Item -LiteralPath $log -Destination "$log.old" -Force }
    "$(Get-Date -Format o) [$Mode] $_" | Add-Content -LiteralPath $log -Encoding UTF8
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose(); if ($UiLog) { Stop-Transcript | Out-Null } }

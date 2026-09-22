param([ValidateSet('Index','Run','Inspect','Install','Apply','Uninstall')][string]$Mode = 'Run', [switch]$UiLog)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = $PSScriptRoot
$taskName = 'DualScreenWallpaper-1Minute'
. (Join-Path $PSScriptRoot 'Initialize-Config.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
$config = Convert-Settings (Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$data = Join-Path $root 'data'
New-Item -ItemType Directory -Path $data -Force | Out-Null
if ($UiLog) { Start-Transcript -LiteralPath (Join-Path $data 'ui-output.log') -Force | Out-Null }
Add-Type -Path (Join-Path $root 'Desktop.cs')
Add-Type -Path (Join-Path $root 'ImageHeader.cs')
Add-Type -AssemblyName PresentationCore,WindowsBase

function Get-Frame($path) {
    $header = [Wallpaper.ImageHeader]::Read($path)
    if ($header) { return [pscustomobject]@{ Width=$header[0]; Height=$header[1]; Orientation=$header[2] } }
    $stream = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation, [Windows.Media.Imaging.BitmapCacheOption]::None)
        $frame = $decoder.Frames[0]
        $rotation = 0
        try {
            $orientation = $frame.Metadata.GetQuery('/app1/ifd/{ushort=274}')
            if ($orientation) { $rotation = [int]$orientation }
        } catch {}
        $w = $frame.PixelWidth; $h = $frame.PixelHeight
        if ($rotation -in 5,6,7,8) { $w = $frame.PixelHeight; $h = $frame.PixelWidth }
        [pscustomobject]@{ Width=$w; Height=$h; Orientation=$rotation }
    } finally { $stream.Dispose() }
}

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
function Get-Monitors($desktop) {
    for ($i=0; $i -lt $desktop.GetMonitorDevicePathCount(); $i++) {
        $id = $desktop.GetMonitorDevicePathAt($i)
        try { $rect = $desktop.GetMonitorRECT($id) } catch { continue } # Disconnected display
        $w = $rect.Right-$rect.Left; $h = $rect.Bottom-$rect.Top
        if ($w -gt 0 -and $h -gt 0) {
            [pscustomobject]@{ Id=$id; Width=$w; Height=$h; Kind=(Get-MonitorRole $rect) }
        }
    }
}

function Convert-Wallpaper($source, $destination) {
    $info = Get-Frame $source
    $stream = [IO.File]::Open($source, 'Open', 'Read', 'ReadWrite')
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        $frame = $decoder.Frames[0]
    } finally { $stream.Dispose() }
    $matrix = [Windows.Media.Matrix]::Identity
    switch ($info.Orientation) {
        2 { $matrix.Scale(-1,1) }
        3 { $matrix.Rotate(180) }
        4 { $matrix.Scale(1,-1) }
        5 { $matrix = [Windows.Media.Matrix]::new(0,1,1,0,0,0) }
        6 { $matrix.Rotate(90) }
        7 { $matrix = [Windows.Media.Matrix]::new(0,-1,-1,0,0,0) }
        8 { $matrix.Rotate(270) }
    }
    if (!$matrix.IsIdentity) { $frame = [Windows.Media.Imaging.TransformedBitmap]::new($frame, [Windows.Media.MatrixTransform]::new($matrix)) }
    $encoder = [Windows.Media.Imaging.JpegBitmapEncoder]::new()
    $encoder.QualityLevel = 95
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($frame))
    $out = [IO.File]::Create($destination)
    try { $encoder.Save($out) } finally { $out.Dispose() }
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
        if (Test-Path -LiteralPath $statePath) { (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $previous[$_.Name]=$_.Value } }
        $desktop.SetPosition(4) # DWPOS_FILL
        foreach ($monitor in $monitors) {
            $pool = @($index.Images.($monitor.Kind) | Where-Object { $_ -ne $previous[$monitor.Id].Source })
            if (!$pool.Count) { $pool = @($index.Images.($monitor.Kind)) }
            $done = $false
            for ($attempt=0; $attempt -lt 10 -and $pool.Count; $attempt++) {
                $source = $pool | Get-Random
                try {
                    $slot = 1
                    if ($previous.ContainsKey($monitor.Id)) { $slot = 1-[int]$previous[$monitor.Id].Slot }
                    $bytes = [Text.Encoding]::UTF8.GetBytes($monitor.Id)
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try { $key = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,16) } finally { $sha.Dispose() }
                    $output = Join-Path $data "$key-$slot.jpg"
                    Convert-Wallpaper $source $output
                    $desktop.SetWallpaper($monitor.Id,$output)
                    $previous[$monitor.Id] = @{Source=$source; Slot=$slot}
                    Write-Host "$($monitor.Kind) $($monitor.Width)x$($monitor.Height): $source"
                    $done = $true; break
                } catch { Write-Warning "$source : $_"; $pool = @($pool | Where-Object { $_ -ne $source }) }
            }
            if (!$done) { throw "Unable to set wallpaper for $($monitor.Kind)" }
        }
        $previous | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
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
                $existing = @(Get-ScheduledTask -ErrorAction Stop | Where-Object TaskName -eq $taskName)
                if ($existing.Count) { Stop-ScheduledTask -TaskName $taskName; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
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
        'Uninstall' {
            $task = Get-ScheduledTask -ErrorAction Stop | Where-Object TaskName -eq $taskName
            if ($task) { Stop-ScheduledTask -TaskName $taskName; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
            $backup = Join-Path $data 'original.json'
            if (Test-Path -LiteralPath $backup) {
                $original = Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
                $desktop = [Wallpaper.Desktop]::Open()
                try {
                    $desktop.SetPosition([int]$original.Position)
                    foreach ($m in $original.Monitors) { if ($m.Path -and (Test-Path -LiteralPath $m.Path)) { $desktop.SetWallpaper($m.Id,$m.Path) } }
                } finally { $desktop.Dispose() }
            }
            Write-Host 'Stopped. Previous static wallpaper restored where available.'
        }
    }
} catch {
    $log = Join-Path $data 'errors.log'
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) { Move-Item -LiteralPath $log -Destination "$log.old" -Force }
    "$(Get-Date -Format o) [$Mode] $_" | Add-Content -LiteralPath $log -Encoding UTF8
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose(); if ($UiLog) { Stop-Transcript | Out-Null } }

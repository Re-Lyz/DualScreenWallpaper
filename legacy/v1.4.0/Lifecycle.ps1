# Task ownership and maintenance coordination are shared by the worker and uninstaller.
$script:WallpaperTaskName='DualScreenWallpaper-1Minute'
function Test-MaintenanceActive {
    $handle=$null
    try {if([Threading.Mutex]::TryOpenExisting('Local\DualScreenWallpaperMaintenance',[ref]$handle)){return $true}; return $false}
    finally {if($handle){$handle.Dispose()}}
}
function Test-TaskOwnedByRoot($task,[string]$root) {
    $expected=Join-Path ([IO.Path]::GetFullPath($root)) 'Run-Wallpaper.vbs'
    foreach($action in $task.Actions) {
        if($action.Arguments -and $action.Arguments.IndexOf(('"'+$expected+'"'),[StringComparison]::OrdinalIgnoreCase) -ge 0){return $true}
    }
    return $false
}
function Stop-OwnedWallpaper([string]$root,[switch]$Restore) {
    $tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object {$_.TaskName -eq $script:WallpaperTaskName -and $_.TaskPath -eq '\'})
    if($tasks.Count -and !(Test-TaskOwnedByRoot $tasks[0] $root)) {
        Write-Output 'Another installation owns the slideshow task; leaving its task and wallpaper unchanged.'
        return
    }
    if($tasks.Count) {
        Stop-ScheduledTask -TaskName $script:WallpaperTaskName -TaskPath '\' -ErrorAction Stop
        Unregister-ScheduledTask -TaskName $script:WallpaperTaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    }
    $backup=Join-Path $root 'data\original.json'
    if($Restore -and (Test-Path -LiteralPath $backup)) {
        # A failed restore must not prevent removal of a task whose target will be uninstalled.
        try {
            if(!('Wallpaper.Desktop' -as [type])){Add-Type -Path (Join-Path $root 'Desktop.cs')}
            $original=Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
            $desktop=[Wallpaper.Desktop]::Open()
            try {
                $desktop.SetPosition([int]$original.Position)
                foreach($m in $original.Monitors){if($m.Path -and (Test-Path -LiteralPath $m.Path)){try {$desktop.SetWallpaper($m.Id,$m.Path)} catch {Write-Warning $_}}}
            } finally {$desktop.Dispose()}
        } catch {Write-Warning "Could not fully restore wallpaper: $_"}
    }
}

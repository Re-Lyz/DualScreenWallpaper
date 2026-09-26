# Runs before Inno Setup removes program files. Does not need a valid config.json.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
$lock=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker'); $held=$false
try {
    try {$held=$lock.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
    if(!$held){throw 'A wallpaper operation is running. Close Settings and retry uninstalling.'}
    Stop-OwnedWallpaper $PSScriptRoot -Restore
    exit 0
} catch {
    $data=Join-Path $PSScriptRoot 'data'; New-Item -ItemType Directory -Path $data -Force | Out-Null
    [string]$_ | Set-Content -LiteralPath (Join-Path $data 'uninstall-error.log') -Encoding UTF8
    exit 1
} finally {if($held){$lock.ReleaseMutex()}; $lock.Dispose()}

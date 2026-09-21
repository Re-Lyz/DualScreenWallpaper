$ErrorActionPreference = 'Stop'
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$start.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Settings.ps1') + '"'
$start.WorkingDirectory = $PSScriptRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
$process = [Diagnostics.Process]::Start($start)
$process.Dispose()

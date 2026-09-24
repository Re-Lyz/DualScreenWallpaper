. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
function Show-UpdateDialog($owner,[string]$root,[string]$CapturePath) {
    $window=[Windows.Forms.Form]::new(); $window.Text=Get-UiText '检查更新'; $window.ClientSize=[Drawing.Size]::new(740,460)
    $window.Font=$owner.Font; $window.StartPosition='CenterParent'; $window.FormBorderStyle='FixedDialog';$window.MaximizeBox=$false
    $status=[Windows.Forms.Label]::new();$status.SetBounds(16,16,708,48);$window.Controls.Add($status)
    $notes=[Windows.Forms.TextBox]::new();$notes.Multiline=$true;$notes.ReadOnly=$true;$notes.ScrollBars='Vertical';$notes.SetBounds(16,70,708,280);$window.Controls.Add($notes)
    $hint=[Windows.Forms.Label]::new();$hint.Text=Get-UiText '更新会关闭设置并重启；仅保留已保存的设置，请先保存修改。';$hint.SetBounds(16,360,708,44);$window.Controls.Add($hint)
    $download=[Windows.Forms.Button]::new();$download.Text=Get-UiText '下载更新';$download.SetBounds(16,410,180,32);$download.Enabled=$false;$window.Controls.Add($download)
    $install=[Windows.Forms.Button]::new();$install.Text=Get-UiText '更新并重启';$install.SetBounds(210,410,180,32);$install.Enabled=$false;$window.Controls.Add($install)
    $close=[Windows.Forms.Button]::new();$close.Text=Get-UiText '关闭';$close.SetBounds(574,410,150,32);$close.DialogResult='Cancel';$window.Controls.Add($close)
    $job=Join-Path $root ('data\updates\'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $job -Force | Out-Null
    $state=@{Worker=$null;Mode='';Job=$job;Info=$null}
    $timer=[Windows.Forms.Timer]::new();$timer.Interval=300
    $start={param($operation)
        $state.Mode=$operation
        $result=Join-Path $job 'result.json';if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result -Force}
        $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $root 'UpdateWorker.ps1')+'"'),'-Mode',$operation,'-Job',('"'+$job+'"'),'-Root',('"'+$root+'"'))
        $state.Worker=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
        $download.Enabled=$false;$install.Enabled=$false
        $status.Text=Get-UiText $(if($operation -eq 'Check'){'正在检查 GitHub 最新正式版本…'}else{'正在下载并校验更新，关闭窗口可取消…'})
        $timer.Start()
    }.GetNewClosure()
    $timer.Add_Tick({
        if(!$state.Worker -or !$state.Worker.HasExited){return}
        $timer.Stop()
        try {
            $result=Get-Content -LiteralPath (Join-Path $job 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if(!$result.Success){throw $result.Error}
            $state.Info=Get-Content -LiteralPath (Join-Path $job 'release-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if($state.Mode -eq 'Check') {
                $notes.Text=[regex]::Replace([string]$state.Info.Notes,'\r?\n',"`r`n")
                $type=Get-UiText $(if($state.Info.Kind -eq 'Installed'){'安装版'}else{'便携版'})
                $status.Text=Get-UiText $(if($state.Info.Available){'发现新版本：{0} → {1}（{2}）'}else{'当前 {0}，最新正式版 {1}（{2}），无需更新。'}) @($state.Info.CurrentVersion,$state.Info.Version,$type)
                $download.Enabled=$state.Info.Available
            } else {$status.Text=Get-UiText '下载与 SHA-256 校验完成，可以更新。';$install.Enabled=$true}
        } catch {$status.Text=Get-UiText '更新操作失败：{0}' @([string]$_)}
        finally {$state.Worker.Dispose();$state.Worker=$null}
    }.GetNewClosure())
    $download.Add_Click({try {& $start 'Download'} catch {$status.Text=[string]$_}}.GetNewClosure())
    $install.Add_Click({
        try {
            Assert-UpdatePackage $state.Info (Join-Path $job $state.Info.Name)
            $runner=Join-Path $job 'runner';New-Item -ItemType Directory -Path $runner -Force | Out-Null
            foreach($name in 'UpdateApply.ps1','UpdateCore.ps1','Lifecycle.ps1'){Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $runner $name) -Force}
            @{Root=$root} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $job 'request.json') -Encoding UTF8
            # Relative batch paths also work when the install folder contains spaces or non-ASCII characters.
            '@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runner\UpdateApply.ps1" -Job "%~dp0." -Restore' | Set-Content -LiteralPath (Join-Path $job 'Restore.cmd') -Encoding ASCII
            $args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $runner 'UpdateApply.ps1')+'"'),'-Job',('"'+$job+'"'),'-ParentProcessId',[string]$PID)
            $null=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -WindowStyle Hidden
            $window.DialogResult='OK';$window.Close()
        } catch {$status.Text=[string]$_}
    }.GetNewClosure())
    try {
        & $start 'Check'
        if($CapturePath) {
            $window.StartPosition='Manual';$window.Location=[Drawing.Point]::new(-10000,-10000);$window.ShowInTaskbar=$false;$window.Show()
            $deadline=(Get-Date).AddSeconds(45)
            while($state.Worker -and (Get-Date) -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 80}
            if($state.Worker){throw 'Update UI check timed out.'}
            $bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height)
            try {$window.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$window.Width,$window.Height));$bitmap.Save($CapturePath)}finally{$bitmap.Dispose()}
            return $status.Text
        }
        if($window.ShowDialog($owner) -eq 'OK'){return $true}
        return $false
    } finally {
        $timer.Stop();$timer.Dispose()
        if($state.Worker){if(!$state.Worker.HasExited){$state.Worker.Kill();$state.Worker.WaitForExit()};$state.Worker.Dispose()}
        $window.Dispose()
    }
}

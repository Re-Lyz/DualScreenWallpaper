function Get-SetupEnvironment([string]$root) {
    $checks=[Collections.Generic.List[string]]::new(); $failures=[Collections.Generic.List[string]]::new()
    if([Environment]::OSVersion.Version.Build -lt 22000){$failures.Add('Windows 11')}else{$checks.Add('Windows 11: OK')}
    if($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSEdition -ne 'Desktop'){$failures.Add('Windows PowerShell 5.1')}
    else {$checks.Add('Windows PowerShell 5.1: OK')}
    if(!(Test-Path -LiteralPath "$env:SystemRoot\System32\wscript.exe")){$failures.Add('Windows Script Host')}
    else {
        $disabled=$false
        foreach($key in 'HKCU:\Software\Microsoft\Windows Script Host\Settings','HKLM:\Software\Microsoft\Windows Script Host\Settings') {
            $setting=Get-ItemProperty -LiteralPath $key -Name Enabled -ErrorAction SilentlyContinue
            if($setting -and $setting.Enabled -eq 0){$disabled=$true}
        }
        if($disabled){$failures.Add('Windows Script Host: disabled')}
        elseif($null -eq [type]::GetTypeFromProgID('VBScript')){$failures.Add('VBScript runtime')}
        else {$checks.Add('Windows Script Host / VBScript: OK')}
    }
    try {
        $service=Get-Service -Name Schedule -ErrorAction Stop
        if($service.Status -ne 'Running'){throw 'Task Scheduler is not running.'}
        $null=Get-Command Register-ScheduledTask -ErrorAction Stop
        $checks.Add('Task Scheduler: OK')
    } catch {$failures.Add('Task Scheduler')}
    $probe=Join-Path $root ([Guid]::NewGuid().ToString('N')+'.tmp')
    try {[IO.File]::WriteAllText($probe,''); $checks.Add((Get-UiText '安装目录可写。'))}
    catch {$failures.Add((Get-UiText '安装目录不可写。'))}
    finally {if(Test-Path -LiteralPath $probe){Remove-Item -LiteralPath $probe -Force}}
    $monitors=@()
    try {
        if(!('Wallpaper.Desktop' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Desktop.cs')}
        $desktop=[Wallpaper.Desktop]::Open()
        try {$monitors=@(Get-Monitors $desktop)} finally {$desktop.Dispose()}
        if(!$monitors.Count){throw 'No connected monitors.'}
        $checks.Add('IDesktopWallpaper: OK')
    } catch {$failures.Add('IDesktopWallpaper')}
    [pscustomobject]@{Checks=$checks.ToArray();Failures=$failures.ToArray();Monitors=$monitors}
}
function Show-SetupWizard($owner,$initial,[string]$CaptureDirectory,$EnvironmentOverride,[ValidateSet('Complete','Cancel','Blocked')][string]$TestAction='Complete') {
    $settings=$initial | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $environment=if($EnvironmentOverride){$EnvironmentOverride}else{Get-SetupEnvironment $script:root}
    $oldButtons=$script:buttons
    $form=[Windows.Forms.Form]::new(); $form.Text=Get-UiText '首次设置引导'
    $form.ClientSize=[Drawing.Size]::new(790,560); $form.StartPosition='CenterParent'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false; $form.MinimizeBox=$false; $form.Font=$owner.Font
    $tabs=[Windows.Forms.TabControl]::new(); $tabs.SetBounds(16,16,756,420); $form.Controls.Add($tabs)
    $welcome=[Windows.Forms.TabPage]::new(); $welcome.Text=Get-UiText '1. 环境与屏幕'; $tabs.TabPages.Add($welcome)
    $info=[Windows.Forms.TextBox]::new(); $info.Multiline=$true; $info.ReadOnly=$true; $info.ScrollBars='Vertical'; $info.SetBounds(12,12,720,235); $welcome.Controls.Add($info)
    $lines=@($environment.Checks)
    if($environment.Failures.Count){$lines+=Get-UiText '请先解决以下环境问题：'; $lines+=@($environment.Failures)}
    foreach($monitor in $environment.Monitors){
        $role=Get-UiText $(if($monitor.Kind -eq 'Primary'){'主屏'}else{'副屏'})
        $lines+="$role : $($monitor.Width) × $($monitor.Height)  ($($monitor.Left), $($monitor.Top))"
    }
    $info.Text=$lines -join "`r`n"
    Label (Get-UiText '主屏以 Windows 设置为准；其他屏幕共用副屏规则。') 12 260 720 $welcome
    Label (Get-UiText '只有一块屏幕也可使用；副屏目录默认沿用主屏，可稍后修改。') 12 291 720 $welcome
    $confirm=[Windows.Forms.CheckBox]::new(); $confirm.Text=Get-UiText '我已确认主副屏分组'; $confirm.SetBounds(12,330,720,28); $welcome.Controls.Add($confirm)
    $primary=Profile-Tab (Get-UiText '2. 主屏图库') $settings.Primary
    $secondary=Profile-Tab (Get-UiText '3. 副屏图库') $settings.Secondary
    # Reuse the same folder/filter controls as Settings; translate their static text locally.
    $translate={param($parent)
        foreach($control in $parent.Controls){
            if($control -isnot [Windows.Forms.TextBox] -and $control -isnot [Windows.Forms.ComboBox]){$control.Text=Get-UiText $control.Text}
            & $translate $control
        }
    }
    & $translate $tabs
    foreach($profile in @($primary,$secondary)) {
        $selected=$profile.Orientation.SelectedIndex
        $profile.Orientation.Items.Clear(); $profile.Orientation.Items.AddRange(@((Get-UiText '仅横图（宽 > 高）'),(Get-UiText '仅竖图（高 > 宽）'))); $profile.Orientation.SelectedIndex=$selected
        $profile.Preset.Items[0]=Get-UiText '自定义'
    }
    $finish=[Windows.Forms.TabPage]::new(); $finish.Text=Get-UiText '4. 轮播与完成'; $tabs.TabPages.Add($finish)
    Label (Get-UiText '切换间隔') 16 20 130 $finish
    $interval=[Windows.Forms.NumericUpDown]::new(); $interval.Minimum=1; $interval.Maximum=1440; $interval.Value=$settings.IntervalMinutes; $interval.SetBounds(180,18,120,28); $finish.Controls.Add($interval)
    Label (Get-UiText '分钟') 320 20 150 $finish
    $auto=[Windows.Forms.CheckBox]::new(); $auto.Text=Get-UiText '启用自动轮播，并在 Windows 登录后自动启动'; $auto.Checked=$settings.AutoStart; $auto.SetBounds(16,62,710,30); $finish.Controls.Add($auto)
    Label (Get-UiText '播放顺序') 16 111 130 $finish
    $order=[Windows.Forms.ComboBox]::new(); $order.DropDownStyle='DropDownList'; $order.SetBounds(180,108,545,28); $order.Items.AddRange(@((Get-UiText '随机（尽量不连续重复）'),(Get-UiText '顺序（按文件名排序，循环播放）'))); $order.SelectedIndex=$(if($settings.PlaybackOrder -eq 'Sequential'){1}else{0}); $finish.Controls.Add($order)
    Label (Get-UiText '显示方式') 16 157 130 $finish
    $displayModes=@('Fill','Fit','Stretch','Center','Tile')
    $display=[Windows.Forms.ComboBox]::new(); $display.DropDownStyle='DropDownList'; $display.SetBounds(180,154,545,28)
    foreach($key in @('填充（等比铺满，裁剪边缘）','适应（完整显示，可能留边）','拉伸（铺满，可能变形）','居中（原始尺寸，可能裁剪）','平铺（原始尺寸，重复排列）')){[void]$display.Items.Add((Get-UiText $key))}
    $display.SelectedIndex=[Array]::IndexOf($displayModes,$settings.DisplayMode); $finish.Controls.Add($display)
    Label (Get-UiText '切换效果') 16 199 130 $finish
    $transition=[Windows.Forms.ComboBox]::new();$transition.DropDownStyle='DropDownList';$transition.SetBounds(180,196,545,28)
    $transition.Items.AddRange(@((Get-UiText '直接切换'),(Get-UiText '淡入淡出')));$transition.SelectedIndex=$(if($settings.TransitionEffect -eq 'CrossFade'){1}else{0});$finish.Controls.Add($transition)
    $preview=Button (Get-UiText '壁纸预览…') 16 238 180 {
        try {$chosen=Show-WallpaperPreview $form $displayModes[$display.SelectedIndex]; if($chosen){$display.SelectedIndex=[Array]::IndexOf($displayModes,$chosen)}} catch {$errorLabel.Text=[string]$_}
    } $finish
    Label (Get-UiText '完成后保存设置、扫描图库并应用；大图库扫描可能需要几分钟。') 16 284 710 $finish
    Label (Get-UiText '取消引导不会保存修改，也不会改变壁纸或轮播任务。') 16 322 710 $finish
    $errorLabel=[Windows.Forms.Label]::new(); $errorLabel.ForeColor=[Drawing.Color]::DarkRed; $errorLabel.SetBounds(16,443,756,53); $form.Controls.Add($errorLabel)
    $back=Button (Get-UiText '上一步') 16 509 145 {$tabs.SelectedIndex=[Math]::Max(0,$tabs.SelectedIndex-1)}
    $next=Button (Get-UiText '下一步') 455 509 150 {
        try {
            $errorLabel.Text=''
            if($environment.Failures.Count){throw (Get-UiText '请先解决环境问题，然后重新打开引导。')}
            if(!$confirm.Checked){throw (Get-UiText '请先确认主副屏分组。')}
            if($tabs.SelectedIndex -eq 1){
                $null=Read-Profile $primary
                if([string]::IsNullOrWhiteSpace($secondary.Roots.Text)){
                    $secondary.Roots.Text=$primary.Roots.Text
                    if(@($environment.Monitors | Where-Object Kind -eq 'Secondary').Count -eq 0){$secondary.OrientationEnabled.Checked=$false; $secondary.MinResolutionEnabled.Checked=$false}
                }
            }
            if($tabs.SelectedIndex -eq 2){$null=Read-Profile $secondary}
            if($tabs.SelectedIndex -lt 3){$tabs.SelectedIndex++; return}
            $result=Read-UiSettings
            $form.Tag=$result | ConvertTo-Json -Depth 6 | ConvertFrom-Json
            $form.DialogResult='OK'; $form.Close()
        } catch {$errorLabel.Text=[string]$_}
    }
    $cancel=Button (Get-UiText '取消') 620 509 150 {$form.DialogResult='Cancel'; $form.Close()}
    $form.CancelButton=$cancel
    $tabs.Add_SelectedIndexChanged({$back.Enabled=$tabs.SelectedIndex -gt 0; $next.Text=Get-UiText $(if($tabs.SelectedIndex -eq 3){'完成并应用'}else{'下一步'})})
    $back.Enabled=$false
    try {
        if($CaptureDirectory) {
            $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-10000,-10000); $form.ShowInTaskbar=$false; $form.Show()
            if($TestAction -eq 'Cancel') {
                $primary.Roots.Text='D:\unsaved-wizard-edit'
                $cancel.PerformClick()
                if($form.DialogResult -ne 'Cancel' -or $form.Tag){throw 'Cancel did not discard wizard edits.'}
                return
            }
            if($TestAction -eq 'Blocked') {
                $confirm.Checked=$true; $tabs.SelectedIndex=3; $next.PerformClick()
                if($form.DialogResult -eq 'OK' -or !$errorLabel.Text){throw 'Failed prerequisites did not block completion.'}
                $cancel.PerformClick(); return
            }
            $next.PerformClick()
            if($tabs.SelectedIndex -ne 0 -or !$errorLabel.Text){throw 'Wizard did not require monitor confirmation.'}
            $confirm.Checked=$true; $errorLabel.Text=''
            for($i=0;$i -lt 4;$i++) {
                $tabs.SelectedIndex=$i; [Windows.Forms.Application]::DoEvents()
                $capture=[Drawing.Bitmap]::new($form.Width,$form.Height)
                try {$form.DrawToBitmap($capture,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $capture.Save((Join-Path $CaptureDirectory "setup-$script:uiLanguage-$i.png"))} finally {$capture.Dispose()}
                if($i -lt 3){$next.PerformClick(); if($errorLabel.Text){throw $errorLabel.Text}}
            }
            $next.PerformClick()
            if($form.DialogResult -ne 'OK'){throw "Wizard completion failed: $($errorLabel.Text)"}
            return $form.Tag
        }
        if($form.ShowDialog($owner) -eq 'OK'){return $form.Tag}
    } finally {$script:buttons=$oldButtons; $form.Dispose()}
}

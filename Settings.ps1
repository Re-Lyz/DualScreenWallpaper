param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
if(Test-MaintenanceActive){throw 'Installation or removal is in progress. Please reopen Settings when it finishes.'}
$script:settingsMutex=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperSettings')
if(Test-MaintenanceActive){$script:settingsMutex.Dispose(); throw 'Installation or removal is in progress.'}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:root=$PSScriptRoot; $script:worker=$null; $script:buttons=@()
$script:configPath=Join-Path $PSScriptRoot 'config.json'
. (Join-Path $PSScriptRoot 'Initialize-Config.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
. (Join-Path $PSScriptRoot 'Language.ps1')
. (Join-Path $PSScriptRoot 'Preview.ps1')
. (Join-Path $PSScriptRoot 'Settings.Controls.ps1')
. (Join-Path $PSScriptRoot 'Settings.Persistence.ps1')
. (Join-Path $PSScriptRoot 'SetupWizard.ps1')
$script:importPending=$false
$rawConfig=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$c=Convert-Settings $rawConfig
$script:uiLanguage=$c.Language
$version=(Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$form=[Windows.Forms.Form]::new()
$form.Text="双屏壁纸 v$version · 设置"
$form.ClientSize=[Drawing.Size]::new(780,730)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10); $form.AutoScaleMode='Dpi'

Label '主屏以 Windows“主显示器”为准；其他显示器使用副屏设置，不随横竖方向切换。' 20 15 750
$tabs=[Windows.Forms.TabControl]::new(); $tabs.SetBounds(20,48,740,385); $form.Controls.Add($tabs)
$primary=Profile-Tab '主屏' $c.Primary
$secondary=Profile-Tab '副屏' $c.Secondary
Label '切换间隔' 20 422 100
$interval=[Windows.Forms.NumericUpDown]::new(); $interval.Minimum=1; $interval.Maximum=1440; $interval.Value=$c.IntervalMinutes; $interval.SetBounds(122,419,90,28); $form.Controls.Add($interval)
Label '分钟' 220 422 60
Label '显示方式' 285 422 95
$displayModes=@('Fill','Fit','Stretch','Center','Tile')
$displayKeys=@('填充（等比铺满，裁剪边缘）','适应（完整显示，可能留边）','拉伸（铺满，可能变形）','居中（原始尺寸，可能裁剪）','平铺（原始尺寸，重复排列）')
$display=[Windows.Forms.ComboBox]::new(); $display.DropDownStyle='DropDownList'; $display.SetBounds(385,419,375,28); $form.Controls.Add($display)
$display.Items.AddRange($displayKeys); $display.SelectedIndex=[Array]::IndexOf($displayModes,$c.DisplayMode)
Label '播放顺序' 20 460 100
$order=[Windows.Forms.ComboBox]::new(); $order.DropDownStyle='DropDownList'; $order.SetBounds(122,457,638,28); $form.Controls.Add($order)
$order.Items.AddRange(@('随机（尽量不连续重复）','顺序（按文件名排序，循环播放）'))
$order.SelectedIndex=$(if($c.PlaybackOrder -eq 'Sequential'){1}else{0})
$auto=[Windows.Forms.CheckBox]::new(); $auto.Text='启用自动轮播，并在 Windows 登录后自动启动'; $auto.Checked=$c.AutoStart; $auto.SetBounds(20,498,730,28); $form.Controls.Add($auto)
Label $(if($rawConfig.SchemaVersion -ne 2){'旧配置已载入：横屏 → 主屏，竖屏 → 副屏。请核对后保存；旧配置将备份。'}else{'取消自动轮播后，“保存并应用”仅换图一次，同时关闭自动轮播。'}) 20 531 750
$status=[Windows.Forms.Label]::new(); $status.SetBounds(20,650,740,28); $status.Text='就绪。首次扫描大量图片可能需要几分钟。'; $form.Controls.Add($status)
$log=[Windows.Forms.TextBox]::new(); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.SetBounds(20,681,740,110); $form.Controls.Add($log)

function Start-Worker($mode) {
    if($script:worker -and !$script:worker.HasExited){throw (Get-UiText '请等待当前操作完成。')}
    $data=Join-Path $script:root 'data'; New-Item -ItemType Directory -Path $data -Force | Out-Null
    $script:stdout=Join-Path $data 'ui-output.log'; $script:stderr=Join-Path $data 'ui-error.log'
    [IO.File]::WriteAllText($script:stdout,''); [IO.File]::WriteAllText($script:stderr,'')
    $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $script:root 'Wallpaper.ps1')+'" -Mode '+$mode+' -UiLog'
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $start.Arguments=$args; $start.WorkingDirectory=$script:root
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WindowStyle='Hidden'
    $script:worker=[Diagnostics.Process]::Start($start)
    $null=$script:worker.Handle
    foreach($button in $script:buttons){$button.Enabled=$false}
    Set-Status '正在处理… 扫描完成后会显示结果。'; $log.Clear(); $timer.Start()
}
function Show-Failure($errorText){if($SmokeTest){throw $errorText};[void][Windows.Forms.MessageBox]::Show($form,[string]$errorText,(Get-UiText '操作未完成'),'OK','Warning')}
function Start-SetupWizard {
    try {
        $initial=Read-UiSettings -AllowMissing | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $result=Show-SetupWizard $form $initial
        if($result){Load-UiSettings $result; Save-Settings; Start-Worker 'Apply'}
    } catch {Show-Failure $_}
}
$null=Button '保存并应用' 20 570 150 {try {Save-Settings; Start-Worker 'Apply'} catch {Show-Failure $_}}
$null=Button '刷新图片索引' 185 570 150 {try {Save-Settings; Start-Worker 'Index'} catch {Show-Failure $_}}
$null=Button '立即换图' 350 570 130 {try {Start-Worker 'Run'} catch {Show-Failure $_}}
$null=Button '停止并恢复壁纸' 495 570 175 {try {Start-Worker 'Uninstall'} catch {Show-Failure $_}}
$null=Button '导入配置…' 20 610 150 {
    $dialog=[Windows.Forms.OpenFileDialog]::new(); $dialog.Filter='JSON (*.json)|*.json'
    try {if($dialog.ShowDialog($form) -eq 'OK'){Import-Settings $dialog.FileName}} catch {Show-Failure $_} finally {$dialog.Dispose()}
}
$null=Button '导出配置…' 185 610 150 {
    $dialog=[Windows.Forms.SaveFileDialog]::new(); $dialog.Filter='JSON (*.json)|*.json'; $dialog.FileName='wallpaper-settings.json'
    try {if($dialog.ShowDialog($form) -eq 'OK'){Export-Settings $dialog.FileName; Set-Status '配置已导出。'}} catch {Show-Failure $_} finally {$dialog.Dispose()}
}
$null=Button '壁纸预览…' 350 610 150 {try {$chosen=Show-WallpaperPreview $form $displayModes[$display.SelectedIndex]; if($chosen){$display.SelectedIndex=[Array]::IndexOf($displayModes,$chosen)}} catch {Show-Failure $_}}
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=800
$timer.Add_Tick({
    try {
        $out='';$err=''
        if(Test-Path -LiteralPath $script:stdout){$out=Get-Content -LiteralPath $script:stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue}
        if(Test-Path -LiteralPath $script:stderr){$err=Get-Content -LiteralPath $script:stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue}
        $log.Text=([string]$out+[string]$err); $log.SelectionStart=$log.TextLength; $log.ScrollToCaret()
        if($script:worker.HasExited){
            $timer.Stop(); $script:worker.WaitForExit()
            if($script:worker.ExitCode -eq 0){
                Set-Status '操作完成。'
                $indexPath=Join-Path $script:root 'data\index.json'
                if(Test-Path -LiteralPath $indexPath){
                    $idx=Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    Set-Status '操作完成。合格图片：主屏 {0} 张，副屏 {1} 张。' @($idx.Stats.Primary.Eligible,$idx.Stats.Secondary.Eligible)
                }
            } else {Set-Status '操作失败，请查看下方详情；配置仍可修改后重试。'}
            foreach($button in $script:buttons){$button.Enabled=$true}
            $script:worker.Dispose();$script:worker=$null
        }
    } catch {Set-Status '读取进度失败：{0}' @([string]$_)}
})
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if($script:worker -and !$script:worker.HasExited){$eventArgs.Cancel=$true; Set-Status '当前操作尚未完成，请稍候再关闭窗口。'}
})
# Translate existing controls in place so switching language preserves unsaved edits.
$script:localizedControls=[Collections.Generic.List[object]]::new()
function Register-LocalizedControls($parent) {
    foreach($control in $parent.Controls){
        if($control -isnot [Windows.Forms.TextBox] -and $control -isnot [Windows.Forms.ComboBox] -and $script:EnglishText.ContainsKey($control.Text)){
            $script:localizedControls.Add(@{Control=$control;Key=$control.Text})
        }
        Register-LocalizedControls $control
    }
}
Register-LocalizedControls $form
function Set-Status([string]$key,[object[]]$values=@()) {
    $script:statusKey=$key; $script:statusValues=$values
    $status.Text=Get-UiText $key $values
}
function Set-UiLanguage([string]$selectedLanguage) {
    $script:uiLanguage=$selectedLanguage
    $wasChanging=$script:changingLanguage; $script:changingLanguage=$true
    try {$script:language.SelectedIndex=$(if($selectedLanguage -eq 'en-US'){1}else{0})} finally {$script:changingLanguage=$wasChanging}
    $form.Text=Get-UiText '双屏壁纸 v{0} · 设置' @($version)
    foreach($entry in $script:localizedControls){$entry.Control.Text=Get-UiText $entry.Key}
    foreach($profile in @($primary,$secondary)){
        $selected=$profile.Orientation.SelectedIndex
        $profile.Orientation.Items.Clear()
        $profile.Orientation.Items.AddRange(@((Get-UiText '仅横图（宽 > 高）'),(Get-UiText '仅竖图（高 > 宽）')))
        $profile.Orientation.SelectedIndex=$selected
        $profile.Preset.Items[0]=Get-UiText '自定义'
    }
    $selected=$display.SelectedIndex
    $display.Items.Clear()
    foreach($key in $displayKeys){[void]$display.Items.Add((Get-UiText $key))}
    $display.SelectedIndex=$selected
    $selected=$order.SelectedIndex
    $order.Items.Clear()
    $order.Items.AddRange(@((Get-UiText '随机（尽量不连续重复）'),(Get-UiText '顺序（按文件名排序，循环播放）')))
    $order.SelectedIndex=$selected
    Set-Status $script:statusKey $script:statusValues
}
foreach($control in $form.Controls){if($control.Top -ge 419){$control.Top+=20}; $control.Top+=40}
$form.ClientSize=[Drawing.Size]::new(780,870)
$form.AutoScroll=$true
Label '语言 / Language' 20 15 155
$language=[Windows.Forms.ComboBox]::new(); $language.DropDownStyle='DropDownList'; $language.Items.AddRange(@('简体中文','English')); $language.SetBounds(180,12,180,28); $form.Controls.Add($language)
$language.SelectedIndex=$(if($script:uiLanguage -eq 'en-US'){1}else{0})
$wizardButton=Button '首次设置引导…' 500 10 260 {Start-SetupWizard}
$script:localizedControls.Add(@{Control=$wizardButton;Key='首次设置引导…'})
Set-Status '就绪。首次扫描大量图片可能需要几分钟。'
Set-UiLanguage $script:uiLanguage
$script:changingLanguage=$false
$language.Add_SelectedIndexChanged({
    if($script:changingLanguage){return}
    $previous=$script:uiLanguage
    $chosen=if($language.SelectedIndex -eq 1){'en-US'}else{'zh-CN'}
    try {if(!$script:importPending){Save-UiLanguage $script:configPath $chosen}; Set-UiLanguage $chosen}
    catch {
        $script:changingLanguage=$true
        try {$language.SelectedIndex=$(if($previous -eq 'en-US'){1}else{0})} finally {$script:changingLanguage=$false}
        Show-Failure $_
    }
})
if($SmokeTest){. (Join-Path $PSScriptRoot 'Test-SettingsUI.ps1'); exit 0}
$form.Add_Shown({if(!$c.SetupCompleted){Start-SetupWizard}})
$form.Height=[Math]::Min($form.Height,[Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height)
try{[void]$form.ShowDialog()} finally {$timer.Dispose();$form.Dispose();$script:settingsMutex.Dispose()}

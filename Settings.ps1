param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:root = $PSScriptRoot
$script:worker = $null
$script:buttons = @()
$script:configPath = Join-Path $PSScriptRoot 'config.json'
. (Join-Path $PSScriptRoot 'Initialize-Config.ps1')
$c = Get-Content -LiteralPath $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$form = [Windows.Forms.Form]::new()
$form.Text = '双屏壁纸 · 设置'
$form.ClientSize = [Drawing.Size]::new(780,730)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI',10)
$form.AutoScaleMode = 'Dpi'

function Label($text,$x,$y,$width=700) {
    $v=[Windows.Forms.Label]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,25); $form.Controls.Add($v)
}
function Button($text,$x,$y,$width,$handler) {
    $v=[Windows.Forms.Button]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,32); $v.Add_Click($handler); $form.Controls.Add($v)
    $script:buttons += $v
    return $v
}
function Folder-Box($title,$y,$paths) {
    Label $title 20 $y
    $box=[Windows.Forms.TextBox]::new(); $box.Multiline=$true; $box.ScrollBars='Vertical'; $box.SetBounds(20,($y+28),625,88)
    $box.Text=(@($paths) -join "`r`n"); $form.Controls.Add($box)
    $handler={
        $dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description='选择图片文件夹（自动包含全部子目录）'
        try {
            if($dialog.ShowDialog($form) -eq 'OK') {
                $lines=@($box.Lines | Where-Object { $_.Trim() })
                if($lines -notcontains $dialog.SelectedPath){ $box.Text=(@($lines)+$dialog.SelectedPath) -join "`r`n" }
            }
        } finally { $dialog.Dispose() }
    }.GetNewClosure()
    $null=Button '添加目录…' 655 ($y+28) 105 $handler
    return $box
}
Label '分别为横屏和竖屏选择图片目录；每行一个路径，自动扫描子目录。' 20 15
$landscape=Folder-Box '横屏图片目录' 50 $c.LandscapeRoots
$portrait=Folder-Box '竖屏图片目录' 180 $c.PortraitRoots
Label '可直接编辑路径；删除某一行即可移除目录。不同屏幕各自随机选图。' 20 300
$onlyPortrait=[Windows.Forms.CheckBox]::new(); $onlyPortrait.Text='竖屏仅使用竖图（图片高度大于宽度）'; $onlyPortrait.Checked=($c.OnlyPortrait -ne $false); $onlyPortrait.SetBounds(20,337,700,28); $form.Controls.Add($onlyPortrait)
$filter=[Windows.Forms.CheckBox]::new(); $filter.Text='竖屏最低分辨率'; $filter.Checked=($c.PortraitMinWidth -gt 0 -or $c.PortraitMinHeight -gt 0); $filter.SetBounds(20,375,170,28); $form.Controls.Add($filter)
Label '宽' 200 378 30
$minWidth=[Windows.Forms.NumericUpDown]::new(); $minWidth.Minimum=1; $minWidth.Maximum=100000; $minWidth.Value=[Math]::Max(1,[int]$c.PortraitMinWidth); $minWidth.SetBounds(232,375,100,28); $form.Controls.Add($minWidth)
Label '高' 352 378 30
$minHeight=[Windows.Forms.NumericUpDown]::new(); $minHeight.Minimum=1; $minHeight.Maximum=100000; $minHeight.Value=[Math]::Max(1,[int]$c.PortraitMinHeight); $minHeight.SetBounds(384,375,100,28); $form.Controls.Add($minHeight)
Label '像素（两边均须达标）' 500 378 250
$filter.Add_CheckedChanged({$minWidth.Enabled=$filter.Checked; $minHeight.Enabled=$filter.Checked})
$minWidth.Enabled=$filter.Checked; $minHeight.Enabled=$filter.Checked
Label '切换间隔' 20 422 100
$interval=[Windows.Forms.NumericUpDown]::new(); $interval.Minimum=1; $interval.Maximum=1440; $interval.Value=$c.IntervalMinutes; $interval.SetBounds(122,419,90,28); $form.Controls.Add($interval)
Label '分钟     显示方式：填充（铺满屏幕，允许裁剪）' 225 422 520
$auto=[Windows.Forms.CheckBox]::new(); $auto.Text='启用自动轮播，并在 Windows 登录后自动启动'; $auto.Checked=($c.AutoStart -ne $false); $auto.SetBounds(20,460,730,28); $form.Controls.Add($auto)
Label '取消勾选后，“保存并应用”仅换图一次，同时关闭自动轮播。' 20 491
$status=[Windows.Forms.Label]::new(); $status.SetBounds(20,570,740,28); $status.Text='就绪。首次扫描大量图片可能需要几分钟。'; $form.Controls.Add($status)
$log=[Windows.Forms.TextBox]::new(); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.SetBounds(20,601,740,110); $form.Controls.Add($log)

function Save-Settings {
    $a=@($landscape.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    $b=@($portrait.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    if(!$a.Count -or !$b.Count){throw '横屏和竖屏各至少需要一个目录。'}
    foreach($path in @($a)+@($b)){if(!(Test-Path -LiteralPath $path -PathType Container)){throw "目录不存在：$path"}}
    $lock=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker'); $held=$false
    try {
        try {$held=$lock.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
        if(!$held){throw '正在扫描或换图，请等当前操作完成后再保存。'}
        $settings=[ordered]@{
            LandscapeRoots=$a; PortraitRoots=$b
            PortraitMinWidth=$(if($filter.Checked){[int]$minWidth.Value}else{0})
            PortraitMinHeight=$(if($filter.Checked){[int]$minHeight.Value}else{0})
            OnlyPortrait=$onlyPortrait.Checked; IntervalMinutes=[int]$interval.Value; AutoStart=$auto.Checked
        }
        $settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:configPath -Encoding UTF8
    } finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
}
function Start-Worker($mode) {
    if($script:worker -and !$script:worker.HasExited){throw '请等待当前操作完成。'}
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
    $status.Text='正在处理… 扫描完成后会显示结果。'; $log.Clear(); $timer.Start()
}
function Show-Failure($errorText){[void][Windows.Forms.MessageBox]::Show($form,[string]$errorText,'操作未完成','OK','Warning')}
$null=Button '保存并应用' 20 530 150 {try {Save-Settings; Start-Worker 'Apply'} catch {Show-Failure $_}}
$null=Button '刷新图片索引' 185 530 150 {try {Save-Settings; Start-Worker 'Index'} catch {Show-Failure $_}}
$null=Button '立即换图' 350 530 130 {try {Start-Worker 'Run'} catch {Show-Failure $_}}
$null=Button '停止并恢复壁纸' 495 530 175 {try {Start-Worker 'Uninstall'} catch {Show-Failure $_}}
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
                $status.Text='操作完成。'
                $indexPath=Join-Path $script:root 'data\index.json'
                if(Test-Path -LiteralPath $indexPath){
                    $idx=Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $status.Text="操作完成。合格图片：横屏 $($idx.Stats.Landscape.Eligible) 张，竖屏 $($idx.Stats.Portrait.Eligible) 张。"
                }
            } else {$status.Text='操作失败，请查看下方详情；配置仍可修改后重试。'}
            foreach($button in $script:buttons){$button.Enabled=$true}
            $script:worker.Dispose();$script:worker=$null
        }
    } catch {$status.Text="读取进度失败：$_"}
})
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if($script:worker -and !$script:worker.HasExited){$eventArgs.Cancel=$true; $status.Text='当前操作尚未完成，请稍候再关闭窗口。'}
})
if($SmokeTest){
    if($landscape.Text -ne (@($c.LandscapeRoots) -join "`r`n") -or $portrait.Text -ne (@($c.PortraitRoots) -join "`r`n")){throw 'Folder controls do not match configuration'}
    if($script:buttons.Count -ne 6){throw 'Missing controls'}
    $form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-10000,-10000);$form.ShowInTaskbar=$false
    $form.Show();[Windows.Forms.Application]::DoEvents()
    Write-Output 'GUI smoke test passed: controls, configured paths, dimensions and interval loaded.'
    New-Item -ItemType Directory -Path (Join-Path $script:root 'data') -Force | Out-Null
    $preview=[Drawing.Bitmap]::new($form.Width,$form.Height)
    try {$form.DrawToBitmap($preview,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$preview.Save((Join-Path $script:root 'data\settings-preview.png'))} finally {$preview.Dispose()}
    Start-Worker 'Inspect'
    $deadline=(Get-Date).AddSeconds(15)
    while($script:worker -and (Get-Date) -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
    if($script:worker -or $status.Text -notlike '操作完成*'){throw "GUI background worker failed: $($status.Text) $($log.Text)"}
    Write-Output 'GUI background worker passed: hidden process, progress polling and completion.'
    $timer.Dispose();$form.Dispose();exit 0
}
try{[void]$form.ShowDialog()} finally {$timer.Dispose();$form.Dispose()}

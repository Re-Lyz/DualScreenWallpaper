param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:root=$PSScriptRoot; $script:worker=$null; $script:buttons=@()
$script:configPath=Join-Path $PSScriptRoot 'config.json'
. (Join-Path $PSScriptRoot 'Initialize-Config.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')
$rawConfig=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$c=Convert-Settings $rawConfig
$version=(Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$form=[Windows.Forms.Form]::new()
$form.Text="双屏壁纸 v$version · 设置"
$form.ClientSize=[Drawing.Size]::new(780,730)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10); $form.AutoScaleMode='Dpi'
function Label($text,$x,$y,$width=700,$parent=$form) {
    $v=[Windows.Forms.Label]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,25); $parent.Controls.Add($v)
}
function Button($text,$x,$y,$width,$handler,$parent=$form) {
    $v=[Windows.Forms.Button]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,32); $v.Add_Click($handler); $parent.Controls.Add($v)
    $script:buttons += $v
    return $v
}
function Folder-Box($title,$y,$paths,$parent) {
    Label $title 12 $y 700 $parent
    $box=[Windows.Forms.TextBox]::new(); $box.Multiline=$true; $box.ScrollBars='Vertical'; $box.SetBounds(12,($y+26),595,64)
    $box.Text=(@($paths) -join "`r`n"); $parent.Controls.Add($box)
    $handler={
        $dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description='选择目录（包含其全部子目录）'
        try {
            if($dialog.ShowDialog($form) -eq 'OK') {
                $lines=@($box.Lines | Where-Object { $_.Trim() })
                if($lines -notcontains $dialog.SelectedPath){$box.Text=(@($lines)+$dialog.SelectedPath) -join "`r`n"}
            }
        } finally {$dialog.Dispose()}
    }.GetNewClosure()
    $null=Button '添加目录…' 617 ($y+26) 105 $handler $parent
    return $box
}
function Profile-Tab($title,$profile) {
    $page=[Windows.Forms.TabPage]::new(); $page.Text=$title; $tabs.TabPages.Add($page)
    $roots=Folder-Box '图片目录（每行一个绝对路径，递归扫描）' 10 $profile.Roots $page
    $excluded=Folder-Box '排除目录 / Exclude（可留空，该目录及全部子目录都不扫描）' 109 $profile.ExcludeFolders $page
    $orientation=[Windows.Forms.CheckBox]::new(); $orientation.Text='启用方向过滤'; $orientation.Checked=$profile.OrientationEnabled; $orientation.SetBounds(12,214,180,28); $page.Controls.Add($orientation)
    $direction=[Windows.Forms.ComboBox]::new(); $direction.DropDownStyle='DropDownList'; $direction.Items.AddRange(@('仅横图（宽 > 高）','仅竖图（高 > 宽）')); $direction.SelectedIndex=$(if($profile.Orientation -eq 'Portrait'){1}else{0}); $direction.SetBounds(210,214,250,28); $page.Controls.Add($direction)
    $direction.Enabled=$orientation.Checked
    $orientation.Add_CheckedChanged({$direction.Enabled=$orientation.Checked}.GetNewClosure())
    $filter=[Windows.Forms.CheckBox]::new(); $filter.Text='启用最低分辨率'; $filter.Checked=$profile.MinResolutionEnabled; $filter.SetBounds(12,254,180,28); $page.Controls.Add($filter)
    Label '宽' 200 257 30 $page
    $width=[Windows.Forms.NumericUpDown]::new(); $width.Minimum=0; $width.Maximum=100000; $width.Value=$profile.MinWidth; $width.SetBounds(232,254,100,28); $page.Controls.Add($width)
    Label '高' 350 257 30 $page
    $height=[Windows.Forms.NumericUpDown]::new(); $height.Minimum=0; $height.Maximum=100000; $height.Value=$profile.MinHeight; $height.SetBounds(382,254,100,28); $page.Controls.Add($height)
    Label '像素；0 表示不限该边' 500 257 225 $page
    $width.Enabled=$filter.Checked; $height.Enabled=$filter.Checked
    $filter.Add_CheckedChanged({$width.Enabled=$filter.Checked; $height.Enabled=$filter.Checked}.GetNewClosure())
    Label '关闭过滤会保留参数；删除目录所在行即可移除。' 12 300 700 $page
    return @{Roots=$roots; ExcludeFolders=$excluded; OrientationEnabled=$orientation; Orientation=$direction; MinResolutionEnabled=$filter; MinWidth=$width; MinHeight=$height}
}
Label '主屏以 Windows“主显示器”为准；其他显示器使用副屏设置，不随横竖方向切换。' 20 15 750
$tabs=[Windows.Forms.TabControl]::new(); $tabs.SetBounds(20,48,740,365); $form.Controls.Add($tabs)
$primary=Profile-Tab '主屏' $c.Primary
$secondary=Profile-Tab '副屏' $c.Secondary
Label '切换间隔' 20 422 100
$interval=[Windows.Forms.NumericUpDown]::new(); $interval.Minimum=1; $interval.Maximum=1440; $interval.Value=$c.IntervalMinutes; $interval.SetBounds(122,419,90,28); $form.Controls.Add($interval)
Label '分钟     显示方式：填充（铺满屏幕，允许裁剪）' 225 422 520
$auto=[Windows.Forms.CheckBox]::new(); $auto.Text='启用自动轮播，并在 Windows 登录后自动启动'; $auto.Checked=$c.AutoStart; $auto.SetBounds(20,460,730,28); $form.Controls.Add($auto)
Label $(if($rawConfig.SchemaVersion -ne 2){'旧配置已载入：横屏 → 主屏，竖屏 → 副屏。请核对后保存；旧配置将备份。'}else{'取消自动轮播后，“保存并应用”仅换图一次，同时关闭自动轮播。'}) 20 491 750
$status=[Windows.Forms.Label]::new(); $status.SetBounds(20,570,740,28); $status.Text='就绪。首次扫描大量图片可能需要几分钟。'; $form.Controls.Add($status)
$log=[Windows.Forms.TextBox]::new(); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.SetBounds(20,601,740,110); $form.Controls.Add($log)
function Read-Profile($controls) {
    $roots=@($controls.Roots.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    $excluded=@($controls.ExcludeFolders.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    if (!$roots.Count) {throw '主屏和副屏各至少需要一个图片目录。'}
    foreach($path in $roots){$null=Get-NormalizedFolder $path; if(!(Test-Path -LiteralPath $path -PathType Container)){throw "图片目录不存在：$path"}}
    foreach($path in $excluded){$null=Get-NormalizedFolder $path}
    [ordered]@{Roots=$roots; ExcludeFolders=$excluded; OrientationEnabled=$controls.OrientationEnabled.Checked; Orientation=$(if($controls.Orientation.SelectedIndex -eq 1){'Portrait'}else{'Landscape'}); MinResolutionEnabled=$controls.MinResolutionEnabled.Checked; MinWidth=[int]$controls.MinWidth.Value; MinHeight=[int]$controls.MinHeight.Value}
}
function Save-Settings {
    $settings=[ordered]@{SchemaVersion=2; Primary=(Read-Profile $primary); Secondary=(Read-Profile $secondary); IntervalMinutes=[int]$interval.Value; AutoStart=$auto.Checked}
    $lock=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker'); $held=$false
    try {
        try {$held=$lock.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
        if(!$held){throw '正在扫描或换图，请等当前操作完成后再保存。'}
        $existing=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($existing.SchemaVersion -ne 2){
            $backup=Join-Path $script:root ('data\config-v1-'+[Guid]::NewGuid().ToString('N')+'.json')
            New-Item -ItemType Directory -Path (Split-Path $backup) -Force | Out-Null
            Copy-Item -LiteralPath $script:configPath -Destination $backup
        }
        $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($script:configPath+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($script:configPath+'.tmp') -Destination $script:configPath -Force
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
                    $status.Text="操作完成。合格图片：主屏 $($idx.Stats.Primary.Eligible) 张，副屏 $($idx.Stats.Secondary.Eligible) 张。"
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
    if($primary.Roots.Text -ne (@($c.Primary.Roots) -join "`r`n") -or $secondary.Roots.Text -ne (@($c.Secondary.Roots) -join "`r`n")){throw 'Folder controls do not match configuration'}
    if($script:buttons.Count -ne 8){throw 'Missing controls'}
    # Exercise independent controls and persistence without touching the user's config.
    $originalRoot=$script:root; $originalConfigPath=$script:configPath
    $testRoot=Join-Path $originalRoot ('data\ui-test-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    try {
        $script:root=$testRoot; $script:configPath=Join-Path $testRoot 'config.json'
        Copy-Item -LiteralPath $originalConfigPath -Destination $script:configPath
        $primary.Roots.Text=$originalRoot; $secondary.Roots.Text=$originalRoot
        $primary.ExcludeFolders.Text=Join-Path $originalRoot 'data'
        $secondary.ExcludeFolders.Text=''
        $primary.MinResolutionEnabled.Checked=$true
        $secondary.MinResolutionEnabled.Checked=$false
        if(!$primary.MinWidth.Enabled -or $secondary.MinWidth.Enabled){throw 'Filter controls are not independent'}
        $primary.MinWidth.Value=1234
        $primary.MinResolutionEnabled.Checked=$false
        $primary.OrientationEnabled.Checked=$true
        $secondary.OrientationEnabled.Checked=$false
        if(!$primary.Orientation.Enabled -or $secondary.Orientation.Enabled){throw 'Orientation controls are not independent'}
        Save-Settings
        $saved=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($saved.SchemaVersion -ne 2 -or $saved.Primary.MinWidth -ne 1234 -or $saved.Primary.MinResolutionEnabled -or $saved.Primary.ExcludeFolders.Count -ne 1 -or $saved.Secondary.ExcludeFolders.Count -ne 0){throw 'Settings did not round-trip'}
        if($rawConfig.SchemaVersion -ne 2 -and !(Get-ChildItem -LiteralPath (Join-Path $testRoot 'data') -Filter 'config-v1-*.json')){throw 'Legacy backup missing'}
        Write-Output 'GUI persistence passed: independent toggles, retained values, exclusions and migration backup.'
    } finally {
        $script:root=$originalRoot; $script:configPath=$originalConfigPath
        $allowed=[IO.Path]::GetFullPath((Join-Path $originalRoot 'data')).TrimEnd('\')+'\'
        $resolved=[IO.Path]::GetFullPath($testRoot)
        if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe GUI test cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
        $primary.Roots.Text=@($c.Primary.Roots) -join "`r`n"; $secondary.Roots.Text=@($c.Secondary.Roots) -join "`r`n"
        $primary.ExcludeFolders.Text=@($c.Primary.ExcludeFolders) -join "`r`n"
        $secondary.ExcludeFolders.Text=@($c.Secondary.ExcludeFolders) -join "`r`n"
        $primary.MinWidth.Value=$c.Primary.MinWidth
        $primary.MinResolutionEnabled.Checked=$c.Primary.MinResolutionEnabled; $secondary.MinResolutionEnabled.Checked=$c.Secondary.MinResolutionEnabled
        $primary.OrientationEnabled.Checked=$c.Primary.OrientationEnabled; $secondary.OrientationEnabled.Checked=$c.Secondary.OrientationEnabled
    }
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

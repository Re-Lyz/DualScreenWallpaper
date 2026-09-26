# Shared settings UI helpers, dot-sourced by Settings.ps1.

function Read-Profile($controls, [switch]$AllowMissing) {
    $roots=@($controls.Roots.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    $excluded=@($controls.ExcludeFolders.Lines | ForEach-Object {$_.Trim().Trim('"')} | Where-Object {$_} | Select-Object -Unique)
    if (!$AllowMissing -and !$roots.Count) {throw (Get-UiText '主屏和副屏各至少需要一个图片目录。')}
    foreach($path in $roots){$null=Get-NormalizedFolder $path; if(!$AllowMissing -and !(Test-Path -LiteralPath $path -PathType Container)){throw (Get-UiText '图片目录不存在：{0}' @($path))}}
    foreach($path in $excluded){$null=Get-NormalizedFolder $path}
    [ordered]@{Roots=$roots; ExcludeFolders=$excluded; OrientationEnabled=$controls.OrientationEnabled.Checked; Orientation=$(if($controls.Orientation.SelectedIndex -eq 1){'Portrait'}else{'Landscape'}); MinResolutionEnabled=$controls.MinResolutionEnabled.Checked; MinWidth=[int]$controls.MinWidth.Value; MinHeight=[int]$controls.MinHeight.Value}
}

function Read-UiSettings([switch]$AllowMissing) {
    [ordered]@{SchemaVersion=2; SetupCompleted=$true; Language=$script:uiLanguage; DisplayMode=$displayModes[$display.SelectedIndex]; PlaybackOrder=$(if($order.SelectedIndex -eq 1){'Sequential'}else{'Random'}); TransitionEffect=$(if($transition.SelectedIndex -eq 1){'CrossFade'}else{'Instant'}); Primary=(Read-Profile $primary -AllowMissing:$AllowMissing); Secondary=(Read-Profile $secondary -AllowMissing:$AllowMissing); IntervalMinutes=[int]$interval.Value; AutoStart=$auto.Checked}
}

function Load-UiSettings($settings) {
    foreach($pair in @(@($primary,$settings.Primary),@($secondary,$settings.Secondary))) {
        $controls=$pair[0]; $profile=$pair[1]
        $controls.Roots.Text=@($profile.Roots) -join "`r`n"; $controls.ExcludeFolders.Text=@($profile.ExcludeFolders) -join "`r`n"
        $controls.OrientationEnabled.Checked=$profile.OrientationEnabled
        $controls.Orientation.SelectedIndex=$(if($profile.Orientation -eq 'Portrait'){1}else{0})
        $controls.MinResolutionEnabled.Checked=$profile.MinResolutionEnabled
        $controls.MinWidth.Value=$profile.MinWidth; $controls.MinHeight.Value=$profile.MinHeight
    }
    $interval.Value=$settings.IntervalMinutes; $auto.Checked=$settings.AutoStart
    $display.SelectedIndex=[Array]::IndexOf($displayModes,$settings.DisplayMode)
    $order.SelectedIndex=$(if($settings.PlaybackOrder -eq 'Sequential'){1}else{0})
    $transition.SelectedIndex=$(if($settings.TransitionEffect -eq 'CrossFade'){1}else{0})
    Set-UiLanguage $settings.Language
}

function Import-Settings([string]$path) {
    $settings=Read-SettingsFile $path
    $missing=@(foreach($kind in 'Primary','Secondary') {
        foreach($folder in @($settings.$kind.Roots)+@($settings.$kind.ExcludeFolders)) {
            if(!(Test-Path -LiteralPath $folder -PathType Container)){$folder}
        }
    })
    Load-UiSettings $settings
    $script:importPending=$true
    Set-Status '配置已载入，尚未保存；请检查后保存并应用。'
    $log.Text=$(if($missing.Count){Get-UiText '以下目录不存在，请检查：{0}' @(($missing -join "`r`n"))}else{''})
}

function Export-Settings([string]$path) {
    if([IO.Path]::GetFullPath($path) -eq [IO.Path]::GetFullPath($script:configPath)){throw (Get-UiText '请选择其他文件，不能覆盖当前配置。')}
    $json=Read-UiSettings -AllowMissing | ConvertTo-Json -Depth 6
    Assert-SettingsFormat ($json | ConvertFrom-Json)
    [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($true))
}

function Save-Settings {
    $settings=Read-UiSettings
    $lock=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker'); $held=$false
    try {
        try {$held=$lock.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
        if(!$held){throw (Get-UiText '正在扫描或换图，请等当前操作完成后再保存。')}
        $existing=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($existing.SchemaVersion -ne 2 -or $script:importPending){
            $prefix=if($script:importPending){'config-before-import-'}else{'config-v1-'}
            $backup=Join-Path $script:root ('data\'+$prefix+[Guid]::NewGuid().ToString('N')+'.json')
            New-Item -ItemType Directory -Path (Split-Path $backup) -Force | Out-Null
            Copy-Item -LiteralPath $script:configPath -Destination $backup
        }
        $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($script:configPath+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($script:configPath+'.tmp') -Destination $script:configPath -Force
        $script:importPending=$false
    } finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
}

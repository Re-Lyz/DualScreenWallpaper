# Invoked by Settings.ps1 -SmokeTest in its isolated test scope.

    if($primary.Roots.Text -ne (@($c.Primary.Roots) -join "`r`n") -or $secondary.Roots.Text -ne (@($c.Secondary.Roots) -join "`r`n")){throw 'Folder controls do not match configuration'}
    if($script:buttons.Count -ne 13){throw 'Missing controls'}
    # Exercise independent controls and persistence without touching the user's config.
    $originalRoot=$script:root; $originalConfigPath=$script:configPath
    $testRoot=Join-Path $originalRoot ('data\ui-test-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    try {
        $script:root=$testRoot; $script:configPath=Join-Path $testRoot 'config.json'
        Copy-Item -LiteralPath $originalConfigPath -Destination $script:configPath
        $primary.Roots.Text=$originalRoot; $secondary.Roots.Text=$originalRoot
        Add-FolderPaths $primary.Roots @(($originalRoot.ToUpperInvariant()+'\'),(Join-Path $originalRoot 'data'))
        if($primary.Roots.Lines.Count -ne 2){throw 'Dropped folders were not normalized and deduplicated'}
        $beforeDrop=$primary.Roots.Text
        $invalidDrop=$false
        try {Add-FolderPaths $primary.Roots @((Join-Path $originalRoot 'VERSION'))} catch {$invalidDrop=$true}
        if(!$invalidDrop -or $primary.Roots.Text -ne $beforeDrop){throw 'Invalid dropped file was not rejected'}
        $primary.Roots.Text=$originalRoot
        $primary.MinResolutionEnabled.Checked=$false
        $primary.Preset.SelectedIndex=5
        if($primary.MinWidth.Value -ne 1440 -or $primary.MinHeight.Value -ne 2560 -or $primary.MinResolutionEnabled.Checked){throw 'Resolution preset changed filter state or failed to set dimensions'}
        $primary.MinWidth.Value=1234
        if($primary.Preset.SelectedIndex -ne 0){throw 'Custom dimensions did not reset preset'}
        $display.SelectedIndex=1
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
        $language.SelectedIndex=1
        if($displayModes[$display.SelectedIndex] -ne 'Fit' -or $primary.Preset.Items[0] -ne 'Custom'){throw 'Language switching lost display mode or preset translation'}
        if($script:uiLanguage -ne 'en-US' -or $tabs.TabPages[0].Text -ne 'Primary' -or $primary.MinWidth.Value -ne 1234 -or $primary.Roots.Text -ne $originalRoot){throw 'English switching lost control values'}
        if((Convert-Settings (Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json)).Language -ne 'en-US'){throw 'Language preference was not saved'}
        Set-Status '操作完成。合格图片：主屏 {0} 张，副屏 {1} 张。' @(12,34)
        $language.SelectedIndex=0
        if($script:uiLanguage -ne 'zh-CN' -or $tabs.TabPages[0].Text -ne '主屏' -or $status.Text -notmatch '12.*34'){throw 'Chinese switching failed'}
        $language.SelectedIndex=1
        Save-Settings
        $saved=Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($saved.DisplayMode -ne 'Fit'){throw 'Display mode did not round-trip'}
        if($saved.Language -ne 'en-US' -or $saved.SchemaVersion -ne 2 -or $saved.Primary.MinWidth -ne 1234 -or $saved.Primary.MinResolutionEnabled -or $saved.Primary.ExcludeFolders.Count -ne 1 -or $saved.Secondary.ExcludeFolders.Count -ne 0){throw 'Settings did not round-trip'}
        if($rawConfig.SchemaVersion -ne 2 -and !(Get-ChildItem -LiteralPath (Join-Path $testRoot 'data') -Filter 'config-v1-*.json')){throw 'Legacy backup missing'}
        $order.SelectedIndex=1
        $transition.SelectedIndex=1
        $exportPath=Join-Path $testRoot 'export.json'
        Export-Settings $exportPath
        $exported=Read-SettingsFile $exportPath
        if($exported.TransitionEffect -ne 'CrossFade'){throw 'Transition effect did not export'}
        if($exported.PlaybackOrder -ne 'Sequential' -or $exported.Primary.MinWidth -ne 1234){throw 'Export did not include unsaved edits'}
        $beforeImport=[IO.File]::ReadAllText($script:configPath)
        $order.SelectedIndex=0; $primary.MinWidth.Value=777
        Import-Settings $exportPath
        if($transition.SelectedIndex -ne 1){throw 'Transition effect did not import'}
        if($order.SelectedIndex -ne 1 -or $primary.MinWidth.Value -ne 1234 -or [IO.File]::ReadAllText($script:configPath) -ne $beforeImport){throw 'Import failed to stage edits without persisting'}
        $language.SelectedIndex=0
        if([IO.File]::ReadAllText($script:configPath) -ne $beforeImport){throw 'Staged language change overwrote active configuration'}
        $badPath=Join-Path $testRoot 'bad.json'
        '{"SchemaVersion":2,"Primary":{}}' | Set-Content -LiteralPath $badPath -Encoding UTF8
        $rejected=$false
        try {Import-Settings $badPath} catch {$rejected=$true}
        if(!$rejected -or $primary.MinWidth.Value -ne 1234 -or !$script:importPending){throw 'Invalid import changed staged configuration'}
        Save-Settings
        $backupFile=Get-ChildItem -LiteralPath (Join-Path $testRoot 'data') -Filter 'config-before-import-*.json' | Select-Object -First 1
        if(!$backupFile -or [IO.File]::ReadAllText($backupFile.FullName) -ne $beforeImport){throw 'Import backup is not an exact copy'}
        if((Read-SettingsFile $script:configPath).PlaybackOrder -ne 'Sequential'){throw 'Playback order was not persisted'}
        $exported.Primary.Roots=@((Join-Path $testRoot 'missing'))
        $exported | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $exportPath -Encoding UTF8
        Import-Settings $exportPath
        if($log.Text -notlike '*missing*'){throw 'Missing import paths were not reported'}
        Load-UiSettings $saved; $script:importPending=$false
        $log.Clear()
        Write-Output 'Import/export passed: staged edits, validation, missing folders, language isolation and exact backup.'
        Write-Output 'GUI persistence passed: independent toggles, retained values, exclusions and migration backup.'
    } finally {
        $script:changingLanguage=$true
        $language.SelectedIndex=$(if($c.Language -eq 'en-US'){1}else{0})
        Set-UiLanguage $c.Language
        $script:changingLanguage=$false
        $script:root=$originalRoot; $script:configPath=$originalConfigPath
        $script:importPending=$false
        $allowed=[IO.Path]::GetFullPath((Join-Path $originalRoot 'data')).TrimEnd('\')+'\'
        $resolved=[IO.Path]::GetFullPath($testRoot)
        if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe GUI test cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
        $primary.Roots.Text=@($c.Primary.Roots) -join "`r`n"; $secondary.Roots.Text=@($c.Secondary.Roots) -join "`r`n"
        $primary.ExcludeFolders.Text=@($c.Primary.ExcludeFolders) -join "`r`n"
        $secondary.ExcludeFolders.Text=@($c.Secondary.ExcludeFolders) -join "`r`n"
        $primary.MinWidth.Value=$c.Primary.MinWidth
        $primary.MinHeight.Value=$c.Primary.MinHeight
        $display.SelectedIndex=[Array]::IndexOf($displayModes,$c.DisplayMode)
        $order.SelectedIndex=$(if($c.PlaybackOrder -eq 'Sequential'){1}else{0})
        $transition.SelectedIndex=$(if($c.TransitionEffect -eq 'CrossFade'){1}else{0})
        $primary.MinResolutionEnabled.Checked=$c.Primary.MinResolutionEnabled; $secondary.MinResolutionEnabled.Checked=$c.Secondary.MinResolutionEnabled
        $primary.OrientationEnabled.Checked=$c.Primary.OrientationEnabled; $secondary.OrientationEnabled.Checked=$c.Secondary.OrientationEnabled
    }
    $form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-10000,-10000);$form.ShowInTaskbar=$false
    $form.Show();[Windows.Forms.Application]::DoEvents()
    Write-Output 'GUI smoke test passed: controls, configured paths, dimensions and interval loaded.'
    New-Item -ItemType Directory -Path (Join-Path $script:root 'data') -Force | Out-Null
    $preview=[Drawing.Bitmap]::new($form.Width,$form.Height)
    try {$form.DrawToBitmap($preview,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$preview.Save((Join-Path $script:root 'data\settings-preview.png'))} finally {$preview.Dispose()}
    Set-Status '就绪。首次扫描大量图片可能需要几分钟。'
    foreach($previewLanguage in @('zh-CN','en-US')){
        Set-UiLanguage $previewLanguage
        foreach($tabIndex in @(0,1)){
            $tabs.SelectedIndex=$tabIndex
            [Windows.Forms.Application]::DoEvents()
            $preview=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try {$form.DrawToBitmap($preview,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$preview.Save((Join-Path $script:root "data\settings-$previewLanguage-$tabIndex.png"))} finally {$preview.Dispose()}
        }
    }
    $tabs.SelectedIndex=0
    # Verify completion messages in English as well as translated static controls.
    Set-UiLanguage 'en-US'
    Write-Output 'Language tests passed: live switching, saved preference, unsaved edits and bilingual previews.'
    Start-Worker 'Inspect'
    $deadline=(Get-Date).AddSeconds(15)
    while($script:worker -and (Get-Date) -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
    if($script:worker -or $script:statusKey -notlike '操作完成*'){throw "GUI background worker failed: $($status.Text) $($log.Text)"}
    Write-Output 'GUI background worker passed: hidden process, progress polling and completion.'
    $timer.Dispose();$form.Dispose();$script:settingsMutex.Dispose();exit 0

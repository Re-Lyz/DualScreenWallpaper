# Shared configuration and image-selection rules (Windows PowerShell 5.1).
function Convert-Settings($value) {
    if ($value.SchemaVersion -and $value.SchemaVersion -ne 2) { throw 'Unsupported configuration version.' }
    if ($value.Language -notin 'zh-CN','en-US') { $value | Add-Member -NotePropertyName Language -NotePropertyValue 'zh-CN' -Force }
    if (!$value.PSObject.Properties['DisplayMode']) { $value | Add-Member -NotePropertyName DisplayMode -NotePropertyValue 'Fill' }
    $null=Get-WallpaperPosition $value.DisplayMode
    if (!$value.PSObject.Properties['PlaybackOrder']) { $value | Add-Member -NotePropertyName PlaybackOrder -NotePropertyValue 'Random' }
    if ($value.PlaybackOrder -cnotin 'Random','Sequential') { throw 'Unsupported playback order.' }
    if(!$value.PSObject.Properties['TransitionEffect']){$value | Add-Member -NotePropertyName TransitionEffect -NotePropertyValue 'Instant'}
    if($value.TransitionEffect -cnotin 'Instant','CrossFade'){throw 'Unsupported transition effect.'}
    if (!$value.PSObject.Properties['SetupCompleted']) {
        $configured=if($value.SchemaVersion -eq 2){@($value.Primary.Roots).Count -gt 0 -and @($value.Secondary.Roots).Count -gt 0}else{@($value.LandscapeRoots).Count -gt 0 -and @($value.PortraitRoots).Count -gt 0}
        $value | Add-Member -NotePropertyName SetupCompleted -NotePropertyValue ([bool]$configured)
    }
    if ($value.SchemaVersion -eq 2) { return $value }
    # Preserve the old filters; the user can review the new monitor roles in Settings.
    [pscustomobject]@{
        SchemaVersion=2; Language=$value.Language; DisplayMode=$value.DisplayMode; PlaybackOrder=$value.PlaybackOrder; SetupCompleted=$value.SetupCompleted; TransitionEffect=$value.TransitionEffect
        Primary=[pscustomobject]@{ Roots=@($value.LandscapeRoots); ExcludeFolders=@(); OrientationEnabled=$false; Orientation='Landscape'; MinResolutionEnabled=$false; MinWidth=1920; MinHeight=1080 }
        Secondary=[pscustomobject]@{ Roots=@($value.PortraitRoots); ExcludeFolders=@(); OrientationEnabled=($value.OnlyPortrait -ne $false); Orientation='Portrait'; MinResolutionEnabled=($value.PortraitMinWidth -gt 0 -or $value.PortraitMinHeight -gt 0); MinWidth=[int]$value.PortraitMinWidth; MinHeight=[int]$value.PortraitMinHeight }
        IntervalMinutes=$value.IntervalMinutes
        AutoStart=($value.AutoStart -ne $false)
    }
}
function Get-PlaybackCandidates([string[]]$paths, [string]$previous, [string]$order) {
    if (!$paths.Count) { return }
    if ($order -eq 'Sequential') {
        $sorted=@($paths | Sort-Object @{Expression={[IO.Path]::GetFileName($_)}}, @{Expression={$_}})
        $start=0
        for($i=0; $i -lt $sorted.Count; $i++){if($sorted[$i] -eq $previous){$start=($i+1)%$sorted.Count; break}}
        for($i=0; $i -lt $sorted.Count; $i++){$sorted[($start+$i)%$sorted.Count]}
    } else {
        $pool=@($paths | Where-Object {$_ -ne $previous})
        if(!$pool.Count){$pool=$paths}
        $pool | Get-Random -Count ([Math]::Min(10,$pool.Count))
    }
}
function Assert-SettingsFormat($value) {
    if($value -isnot [pscustomobject]){throw 'Configuration must be a JSON object.'}
    if($value.SchemaVersion -ne 2){throw 'Unsupported configuration version.'}
    foreach($name in 'IntervalMinutes') {
        if($value.$name -isnot [int] -and $value.$name -isnot [long]){throw "Invalid integer: $name"}
        if($value.$name -lt 1 -or $value.$name -gt 1440){throw "Out of range: $name"}
    }
    if($value.AutoStart -isnot [bool]){throw 'AutoStart must be a boolean.'}
    if($value.PSObject.Properties['SetupCompleted'] -and $value.SetupCompleted -isnot [bool]){throw 'SetupCompleted must be a boolean.'}
    if($value.Language -cnotin 'zh-CN','en-US'){throw 'Unsupported language.'}
    $null=Get-WallpaperPosition $value.DisplayMode
    if($value.PlaybackOrder -cnotin 'Random','Sequential'){throw 'Unsupported playback order.'}
    if($value.TransitionEffect -cnotin 'Instant','CrossFade'){throw 'Unsupported transition effect.'}
    foreach($kind in 'Primary','Secondary') {
        $profile=$value.$kind
        if($profile -isnot [pscustomobject]){throw "Missing profile: $kind"}
        foreach($name in 'Roots','ExcludeFolders') {
            if($profile.$name -isnot [array]){throw "$kind.$name must be an array."}
            foreach($path in $profile.$name){
                if($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path)){throw "Invalid path in $kind.$name"}
                $null=Get-NormalizedFolder $path
            }
        }
        foreach($name in 'OrientationEnabled','MinResolutionEnabled') {
            if($profile.$name -isnot [bool]){throw "$kind.$name must be a boolean."}
        }
        if($profile.Orientation -cnotin 'Landscape','Portrait'){throw "Invalid orientation: $kind"}
        foreach($name in 'MinWidth','MinHeight') {
            if(($profile.$name -isnot [int] -and $profile.$name -isnot [long]) -or $profile.$name -lt 0 -or $profile.$name -gt 100000){throw "Invalid dimension: $kind.$name"}
        }
    }
}
function Read-SettingsFile([string]$path) {
    $value=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($value -isnot [pscustomobject]){throw 'Configuration must be a JSON object.'}
    if(!$value.PSObject.Properties['SchemaVersion']) {
        foreach($name in 'LandscapeRoots','PortraitRoots','OnlyPortrait','PortraitMinWidth','PortraitMinHeight','IntervalMinutes') {
            if(!$value.PSObject.Properties[$name]){throw "Missing legacy setting: $name"}
        }
        foreach($name in 'LandscapeRoots','PortraitRoots'){if($value.$name -isnot [array]){throw "Invalid legacy setting: $name"}}
        if($value.OnlyPortrait -isnot [bool]){throw 'Invalid legacy orientation switch.'}
        foreach($name in 'PortraitMinWidth','PortraitMinHeight') {
            if(($value.$name -isnot [int] -and $value.$name -isnot [long]) -or $value.$name -lt 0 -or $value.$name -gt 100000){throw "Invalid legacy dimension: $name"}
        }
        if($value.PSObject.Properties['AutoStart'] -and $value.AutoStart -isnot [bool]){throw 'Invalid legacy AutoStart.'}
    } elseif($value.SchemaVersion -isnot [int] -or $value.SchemaVersion -ne 2){throw 'Unsupported configuration version.'}
    if($value.PSObject.Properties['Language'] -and $value.Language -cnotin 'zh-CN','en-US'){throw 'Unsupported language.'}
    $settings=Convert-Settings $value
    Assert-SettingsFormat $settings
    return $settings
}
function Get-WallpaperPosition([string]$mode) {
    switch -CaseSensitive ($mode) {
        'Center' { return 0 }
        'Tile' { return 1 }
        'Stretch' { return 2 }
        'Fit' { return 3 }
        'Fill' { return 4 }
        default { throw "Unsupported display mode: $mode" }
    }
}
function Get-NormalizedFolder([string]$path) {
    if (![IO.Path]::IsPathRooted($path)) { throw "Use an absolute folder path: $path" }
    [IO.Path]::GetFullPath($path).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
}
function Test-ExcludedFolder([string]$path, $excluded) {
    $normalized=Get-NormalizedFolder $path
    foreach ($item in $excluded) {
        if ($normalized.StartsWith($item,[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function Get-SourceImages($profile) {
    $excluded=@($profile.ExcludeFolders | ForEach-Object { Get-NormalizedFolder $_ })
    $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending=[Collections.Generic.Stack[string]]::new()
    foreach ($folder in $profile.Roots) {
        $folder=Get-NormalizedFolder $folder
        if (!(Test-Path -LiteralPath $folder -PathType Container)) { throw "Missing folder: $folder" }
        $pending.Push($folder)
    }
    while ($pending.Count) {
        $folder=Get-NormalizedFolder ($pending.Pop())
        if ((Test-ExcludedFolder $folder $excluded) -or !$visited.Add($folder)) { continue }
        # Do not follow junctions/symlinks: avoid cycles and escaping excluded trees.
        if ((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        Get-ChildItem -LiteralPath $folder -ErrorAction Continue | ForEach-Object {
            if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
            if ($_.PSIsContainer) { $pending.Push($_.FullName); return }
            if ($_.Extension.ToLowerInvariant() -in '.jpg','.jpeg','.jfif','.png','.bmp','.gif','.tif','.tiff','.ico','.wdp','.jxr','.webp','.heic','.heif','.avif') { $_ }
        }
    }
}
function Test-ImageDimensions($dimensions, $profile) {
    if ($profile.OrientationEnabled) {
        if ($profile.Orientation -notin 'Landscape','Portrait') { throw 'Unknown image orientation.' }
        if ($profile.Orientation -eq 'Landscape' -and $dimensions.Width -le $dimensions.Height) { return $false }
        if ($profile.Orientation -eq 'Portrait' -and $dimensions.Height -le $dimensions.Width) { return $false }
    }
    if ($profile.MinResolutionEnabled -and ($dimensions.Width -lt $profile.MinWidth -or $dimensions.Height -lt $profile.MinHeight)) { return $false }
    return $true
}
function Index-Signature($settings) {
    # Keep legacy indexes different so Apply rebuilds them automatically.
    if ($settings.SchemaVersion -ne 2) { return 'legacy-index' }
    [ordered]@{ SchemaVersion=2; Primary=$settings.Primary; Secondary=$settings.Secondary } | ConvertTo-Json -Depth 6 -Compress
}
function Get-MonitorRole($rect) {
    if ($rect.Left -eq 0 -and $rect.Top -eq 0) { 'Primary' } else { 'Secondary' }
}

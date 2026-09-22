# Shared configuration and image-selection rules (Windows PowerShell 5.1).
function Convert-Settings($value) {
    if ($value.SchemaVersion -and $value.SchemaVersion -ne 2) { throw 'Unsupported configuration version.' }
    if ($value.SchemaVersion -eq 2) { return $value }
    # Preserve the old filters; the user can review the new monitor roles in Settings.
    [pscustomobject]@{
        SchemaVersion=2
        Primary=[pscustomobject]@{ Roots=@($value.LandscapeRoots); ExcludeFolders=@(); OrientationEnabled=$false; Orientation='Landscape'; MinResolutionEnabled=$false; MinWidth=1920; MinHeight=1080 }
        Secondary=[pscustomobject]@{ Roots=@($value.PortraitRoots); ExcludeFolders=@(); OrientationEnabled=($value.OnlyPortrait -ne $false); Orientation='Portrait'; MinResolutionEnabled=($value.PortraitMinWidth -gt 0 -or $value.PortraitMinHeight -gt 0); MinWidth=[int]$value.PortraitMinWidth; MinHeight=[int]$value.PortraitMinHeight }
        IntervalMinutes=$value.IntervalMinutes
        AutoStart=($value.AutoStart -ne $false)
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

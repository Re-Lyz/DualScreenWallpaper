# Shared settings UI helpers, dot-sourced by Settings.ps1.

function Label($text,$x,$y,$width=700,$parent=$form) {
    $v=[Windows.Forms.Label]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,25); $parent.Controls.Add($v)
}

function Button($text,$x,$y,$width,$handler,$parent=$form) {
    $v=[Windows.Forms.Button]::new(); $v.Text=$text; $v.SetBounds($x,$y,$width,32); $v.Add_Click($handler); $parent.Controls.Add($v)
    $script:buttons += $v
    return $v
}

function Add-FolderPaths($box, [string[]]$paths) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in $box.Lines) {
        $clean=$line.Trim().Trim('"')
        if(!$clean){continue}
        try {$key=Get-NormalizedFolder $clean} catch {$key=$clean}
        if($seen.Add($key)){$lines.Add($clean)}
    }
    $invalid=[Collections.Generic.List[string]]::new()
    foreach($path in $paths) {
        try {
            $key=Get-NormalizedFolder $path
            if(!(Test-Path -LiteralPath $path -PathType Container)){throw 'Not a folder'}
            if($seen.Add($key)){$lines.Add($path)}
        } catch {$invalid.Add($path)}
    }
    $box.Text=$lines -join "`r`n"
    if($invalid.Count){Show-Failure (Get-UiText '以下项目不是有效目录：{0}' @(($invalid -join "`r`n")))}
}

function Folder-Box($title,$y,$paths,$parent) {
    Label $title 12 $y 700 $parent
    $box=[Windows.Forms.TextBox]::new(); $box.Multiline=$true; $box.ScrollBars='Vertical'; $box.SetBounds(12,($y+26),595,64)
    $box.Text=(@($paths) -join "`r`n"); $parent.Controls.Add($box)
    $box.AllowDrop=$true
    $box.Add_DragEnter({
        param($sender,$eventArgs)
        $eventArgs.Effect=[Windows.Forms.DragDropEffects]::None
        if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect=[Windows.Forms.DragDropEffects]::Copy}
    })
    $box.Add_DragDrop({
        param($sender,$eventArgs)
        try {
            if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
                Add-FolderPaths $sender ($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
            }
        } catch {Show-Failure $_}
    })
    $handler={
        $dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description=(Get-UiText '选择目录（包含其全部子目录）')
        try {
            if($dialog.ShowDialog($form) -eq 'OK') {
                Add-FolderPaths $box @($dialog.SelectedPath)
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
    Label '分辨率预设' 12 292 180 $page
    $preset=[Windows.Forms.ComboBox]::new(); $preset.DropDownStyle='DropDownList'; $preset.SetBounds(210,289,272,28); $page.Controls.Add($preset)
    $preset.Items.AddRange(@('自定义','1920 × 1080','2560 × 1440','3840 × 2160','1080 × 1920','1440 × 2560','2160 × 3840'))
    $syncPreset={
        $index=$preset.Items.IndexOf("$([int]$width.Value) × $([int]$height.Value)")
        $preset.SelectedIndex=[Math]::Max(0,$index)
    }.GetNewClosure()
    & $syncPreset
    $preset.Add_SelectedIndexChanged({
        if($preset.SelectedIndex -le 0){return}
        $parts=([string]$preset.SelectedItem) -split ' × '
        $width.Value=[int]$parts[0]; $height.Value=[int]$parts[1]
        & $syncPreset
    }.GetNewClosure())
    $width.Add_ValueChanged($syncPreset); $height.Add_ValueChanged($syncPreset)
    Label '可拖入目录；关闭过滤保留参数；删除整行可移除目录。' 12 323 710 $page
    return @{Roots=$roots; ExcludeFolders=$excluded; OrientationEnabled=$orientation; Orientation=$direction; MinResolutionEnabled=$filter; MinWidth=$width; MinHeight=$height; Preset=$preset}
}

# Translation keys use the original Chinese UI text; keep all translations here.
$script:EnglishText=@{
    '双屏壁纸 v{0} · 设置'='DualScreenWallpaper v{0} - Settings'
    '语言 / Language'='语言 / Language'
    '选择目录（包含其全部子目录）'='Select a folder (including all subfolders)'
    '添加目录…'='Add folder…'
    '图片目录（每行一个绝对路径，递归扫描）'='Image folders (one absolute path per line; includes subfolders)'
    '排除目录 / Exclude（可留空，该目录及全部子目录都不扫描）'='Excluded folders (optional; skips each folder and all its subfolders)'
    '启用方向过滤'='Filter by orientation'
    '仅横图（宽 > 高）'='Landscape only (width > height)'
    '仅竖图（高 > 宽）'='Portrait only (height > width)'
    '启用最低分辨率'='Minimum resolution'
    '宽'='W'
    '高'='H'
    '像素；0 表示不限该边'='Pixels; 0 means no limit'
    '关闭过滤会保留参数；删除目录所在行即可移除。'='Disabled filters keep their values. Delete a line to remove a folder.'
    '主屏以 Windows“主显示器”为准；其他显示器使用副屏设置，不随横竖方向切换。'='Windows primary display uses Primary; all others use Secondary, regardless of rotation.'
    '主屏'='Primary'
    '副屏'='Secondary'
    '切换间隔'='Interval'
    '分钟     显示方式：填充（铺满屏幕，允许裁剪）'='minutes     Display mode: Fill (covers the screen; may crop edges)'
    '启用自动轮播，并在 Windows 登录后自动启动'='Enable automatic slideshow and start when signing in to Windows'
    '旧配置已载入：横屏 → 主屏，竖屏 → 副屏。请核对后保存；旧配置将备份。'='Legacy settings: Landscape → Primary, Portrait → Secondary. Review and save; backup is automatic.'
    '取消自动轮播后，“保存并应用”仅换图一次，同时关闭自动轮播。'='With slideshow disabled, Save and apply changes wallpapers once and stops automatic changes.'
    '就绪。首次扫描大量图片可能需要几分钟。'='Ready. The first scan of a large library may take several minutes.'
    '主屏和副屏各至少需要一个图片目录。'='Primary and Secondary each need at least one image folder.'
    '图片目录不存在：{0}'='Image folder does not exist: {0}'
    '正在扫描或换图，请等当前操作完成后再保存。'='A scan or wallpaper change is running. Wait before saving.'
    '请等待当前操作完成。'='Please wait for the current operation to finish.'
    '正在处理… 扫描完成后会显示结果。'='Working… Results will appear when the operation finishes.'
    '操作未完成'='Operation could not be completed'
    '保存并应用'='Save and apply'
    '刷新图片索引'='Refresh index'
    '立即换图'='Change now'
    '停止并恢复壁纸'='Stop and restore'
    '操作完成。'='Operation completed.'
    '操作完成。合格图片：主屏 {0} 张，副屏 {1} 张。'='Completed. Eligible images: Primary {0}, Secondary {1}.'
    '操作失败，请查看下方详情；配置仍可修改后重试。'='Operation failed. See the details below; edit your settings and try again.'
    '读取进度失败：{0}'='Could not read progress: {0}'
    '当前操作尚未完成，请稍候再关闭窗口。'='An operation is still running. Please wait before closing.'
}
function Get-UiText([string]$key, [object[]]$values=@()) {
    $text=$key
    if($script:uiLanguage -eq 'en-US' -and $script:EnglishText.ContainsKey($key)){$text=$script:EnglishText[$key]}
    if($values.Count){return ($text -f $values)}
    return $text
}
function Save-UiLanguage([string]$path,[string]$language) {
    if($language -notin 'zh-CN','en-US'){throw 'Unsupported language'}
    $lock=[Threading.Mutex]::new($false,'Local\DualScreenWallpaperWorker'); $held=$false
    try {
        try {$held=$lock.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
        if(!$held){throw (Get-UiText '正在扫描或换图，请等当前操作完成后再保存。')}
        # Save only the preference: do not overwrite unsaved controls or migrate legacy settings.
        $settings=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $settings | Add-Member -NotePropertyName Language -NotePropertyValue $language -Force
        $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($path+'.tmp') -Encoding UTF8
        Move-Item -LiteralPath ($path+'.tmp') -Destination $path -Force
    } finally {if($held){$lock.ReleaseMutex()}; $lock.Dispose()}
}

# DualScreenWallpaper

简体中文 | [English](README.en.md) | [后续计划 / TODO](TODO.md)

Windows 双屏独立静态壁纸轮播：主屏和副屏分别绑定图片目录，支持递归扫描、独立过滤、子目录排除和图形设置界面。当前版本见 `VERSION`，更新内容见 `CHANGELOG.md`。

## 语言切换

设置窗口顶部可选择“简体中文 / English”，即时切换并自动记住语言；未保存的目录、过滤参数不会丢失，也不会触发换图或重建索引。旧配置缺少语言字段时默认使用中文。系统目录选择窗口及系统错误遵循 Windows 语言，诊断日志保留原始语言。两种语言共用同一套功能，翻译集中维护在 `Language.ps1`。

## 功能

- 主屏和副屏分别配置一个或多个目录，递归扫描并去重；可各自排除指定目录及全部子目录。
- 两边均可独立启用方向过滤（仅横图或仅竖图）和最低宽高过滤；关闭开关保留参数。启用方向过滤时不包含正方形图片。最低宽高为 0 表示不限该边。
- 可配置切换间隔，默认每分钟随机切换；可选择随机或按文件名顺序循环播放。
- 支持五种全局显示方式，按 Windows 主显示器选择主屏图片池，其余屏幕使用副屏图片池；旋转屏幕不改变分组。
- 当前用户登录后自动运行；关闭设置窗口不影响轮播。
- 通过 Windows 计划任务和隐藏启动器运行，不需要常驻脚本进程。

## 环境

Windows 11，内置 Windows PowerShell 5.1、Windows Script Host 和任务计划程序。核心多屏功能使用 Windows `IDesktopWallpaper` 接口。当前实现依赖 VBScript；禁用了 Windows Script Host 的环境需要先允许该组件运行。无需下载 PowerShell 模块。

## 开始使用

1. 运行发布包中的 `DualScreenWallpaper-1.3.0-Setup.exe` 安装；也可解压 ZIP 或克隆仓库到可写、固定的本地目录。
2. 从开始菜单打开 Settings，或双击 `00-settings.cmd` / `Open-Settings.vbs`。新配置首次打开会进入设置引导，已有图库配置不自动重复引导。
3. 在“主屏”和“副屏”标签页分别添加图片目录，每行一个绝对路径；需要跳过的子目录填入对应的“排除目录 / Exclude”。
4. 设置过滤规则、切换间隔，勾选自动轮播，点击“保存并应用”。

首次启动自动从 `config.example.json` 创建本地 `config.json`。仓库不附带图片或个人目录配置。第一次扫描大型图库可能需要数分钟；界面显示扫描进度。新增、移动或删除图片后，点击“刷新图片索引”。仅修改间隔、显示方式或播放顺序时会复用索引。

取消勾选自动轮播并保存，会关闭定时任务并只换图一次。“停止并恢复壁纸”会移除任务，并尝试恢复首次运行前的静态壁纸。无法还原其他软件的动态壁纸、Windows Spotlight 或幻灯片配置。

## 入口

| 文件 | 用途 |
| --- | --- |
| `00-settings.cmd` | 图形设置 |
| `01-install.cmd` | 应用当前配置并安装轮播任务 |
| `02-refresh-index.cmd` | 重新扫描图片 |
| `03-change-now.cmd` | 立即换图 |
| `04-stop-and-restore.cmd` | 停止并恢复静态壁纸 |
| `05-show-monitors.cmd` | 显示连接的屏幕 |

任务名为 `DualScreenWallpaper-1Minute`，名称固定，实际间隔取决于配置。多个安装副本会共用并更新同一个任务，不支持同时作为独立实例运行。移动项目时，先停止轮播，整体移动目录，再从新位置保存并应用。

## 图片处理

最低尺寸按宽、高分别判断，并考虑 JPEG EXIF 方向；不是按文件大小或总像素数判断。常见 JPG、JPEG、PNG 可直接使用；也尝试 BMP、GIF、TIFF、ICO、WDP、JXR、WebP、HEIC、HEIF、AVIF。部分格式依赖额外的 Windows 解码器。多帧图片使用首帧，无法读取或转换的文件会跳过。

JPG 和 PNG 索引优先读取文件头；实际换图时通过 Windows 图像解码器转换成 JPEG 缓存。源文件保持原样。显示方式对所有屏幕生效：填充等比铺满并裁剪边缘；适应等比完整显示，可能留边；拉伸铺满但可能变形；居中按原始尺寸显示，大图可能裁剪；平铺按原始尺寸重复排列。旧配置默认填充。每块屏幕交替使用两张缓存，图片缓存不会持续增长。

电脑休眠时不会唤醒，系统忙碌时不保证精确到秒。其他壁纸软件或 Windows 幻灯片可能覆盖这里设置的壁纸。

## 隐私

本工具不包含联网请求、遥测或上传图片的代码。以下本地文件默认被 Git 忽略，不应上传：

- `config.json`：个人图片目录及设置。
- `data/`：图片索引、当前图片路径、屏幕标识、原壁纸备份信息、日志、界面预览和壁纸缓存。

提交问题反馈时也请检查日志、截图和路径。`.gitignore` 无法阻止手动强制添加或上传附件。

## 检查

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Settings.ps1 -SmokeTest
```

该检查验证界面及后台读取屏幕信息，不安装计划任务或更换壁纸。生成的本地配置和测试输出位于忽略列表中。

接口参考：[Microsoft IDesktopWallpaper::SetWallpaper](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-setwallpaper)。

## 排除目录与旧版升级

排除目录使用绝对路径，可通过“添加目录”选择，也可手动输入尚不存在的目录。不支持通配符。排除 `D:\Pictures\Private` 会跳过该目录及后代，但不会误排除 `D:\Pictures\Private2`。排除项只影响所在标签页，即便两个屏幕使用同一图片根目录，也可以有不同排除规则。目录联接和符号链接不参与扫描，以避免循环与绕过排除规则。若没有合格图片，索引操作会报错并保留原索引。

旧配置按“横屏 → 主屏、竖屏 → 副屏”载入；如果原来的主屏是竖屏，请在设置中交换两组目录和规则。旧文件在首次保存前保持不变，保存时备份到 `data/config-v1-*.json`。应用时会自动重建旧索引；直接运行“立即换图”前需先保存并应用或刷新索引。

## 版本维护

应用版本统一由 `VERSION` 管理，设置窗口显示该版本；`SchemaVersion` 是独立的配置结构版本。发布包只包含明确列出的程序文件，不包含 `config.json`、`data/` 或个人图片。

```powershell
# 检查配置迁移、筛选、排除、索引和主副屏分组
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Settings.ps1
# 打包当前版本到 dist/DualScreenWallpaper-1.3.0.zip
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Release.ps1
# 下次发布：先在 CHANGELOG.md 增加 [1.3.1] 条目，再更新版本并打包
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Release.ps1 -NewVersion 1.3.1
```

脚本要求三段式递增版本及对应更新记录，拒绝覆盖已有发布包。打包后可审查并提交代码、`VERSION` 和 `CHANGELOG.md`，再手动创建对应的 Git 标签。升级安装时保留原有 `config.json` 和 `data/`，解压覆盖程序文件后打开设置并保存应用。

## 目录拖放与分辨率预设

图片目录和排除目录区域支持拖入多个文件夹，自动按路径去重并提示无效项目。主副屏均提供常见横屏、竖屏最低分辨率预设，只填写宽高，不会自动启用过滤或改变方向规则，仍可手动输入自定义尺寸。

## 播放顺序、配置迁移与预览

- **播放顺序**：随机模式尽量避免连续重复；顺序模式按文件名排序，同名时按完整路径排序，播完循环。排序为文本排序（不是数字自然排序，建议用 01、02 等前缀）。每块屏幕独立记住最后成功播放的图片，重启后继续；若该图片已从新索引移除，从第一张开始。失效或无法解码的图片会跳过。旧配置默认随机。
- **导出配置**：导出当前界面中的设置，包括未保存的编辑；不包含图片、索引或播放位置。配置内含本地目录路径，分享前请检查。
- **导入配置**：支持当前格式和旧版配置；先校验格式，再载入界面，缺失目录显示在日志中供修正。点击“保存并应用”或“刷新图片索引”才保存，保存前备份原文件至 `data/config-before-import-*.json`。导入不会复制图片，跨电脑使用时需调整目录。导入后的语言切换也暂存到正式保存时生效。导入会替换当前界面的未保存编辑。
- **壁纸预览**：读取连接屏幕的相对位置及当前壁纸，可为每块屏幕选择示例图片，并即时比较填充、适应、拉伸、居中、平铺。使用当前未保存的显示方式；“使用此显示方式”仅回填设置，保存应用后才作用于桌面。示例图不代表下一张轮播图片，也不会添加到图库。平铺为单屏示意，Windows 多屏平铺结果可能不同。

新增功能检查（使用隔离样本及模拟桌面接口，不更换真实壁纸）：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Features.ps1
```
## 安装包与首次引导

安装包默认安装到当前用户的 `%LOCALAPPDATA%\Programs\DualScreenWallpaper`，无需管理员权限，可选择其他可写目录、开始菜单文件夹及桌面快捷方式。安装程序界面目前为英文，应用和首次引导支持中英文。

首次引导依次检查 Windows、PowerShell、Windows Script Host / VBScript、任务计划程序和目录写入权限，展示实际主副屏信息，再引导选择图库、过滤规则、轮播与显示方式。单屏使用时，空的副屏目录沿用主屏并关闭副屏默认过滤。点击“完成并应用”后才保存、扫描并应用；取消不保存，也不改变壁纸和轮播任务。设置窗口顶部可随时重新打开引导。扫描失败时会保留设置供修正，不会隐藏错误。

升级前关闭设置窗口，在原安装目录覆盖安装；程序保留 `config.json` 和 `data/`，阻止降级或在已安装时换目录升级。通过 Windows“已安装的应用”或开始菜单 Uninstall 卸载：清理指向本安装目录的轮播任务，并尝试恢复原静态壁纸。属于另一个副本的任务保持不变。卸载保留配置、索引、缓存和备份，确认不再需要后可自行删除遗留目录。

构建安装包需要 [Inno Setup 6.7 或更新版本](https://jrsoftware.org/isdl.php)，应用运行不需要该工具。发布物尚未进行代码签名。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-Setup.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Installer.ps1
# 若编译器未被自动发现：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Installer.ps1 -CompilerPath 'C:\Tools\Inno Setup 6\ISCC.exe'
```

`Test-Installer.ps1` 会真实创建、升级并卸载一个临时安装，验证快捷方式、配置保留和降级阻止；已有注册安装时拒绝运行，适合测试账户或虚拟机。它不创建轮播任务、不更换桌面壁纸；临时安装的配置与日志保留在忽略的 `data/installer-test-*` 目录。

本次采用局部重构，保留 PowerShell / WinForms 架构。模块分工和后续重构条件见 [ARCHITECTURE.md](ARCHITECTURE.md)。
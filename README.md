# DualScreenWallpaper

Windows 双屏独立静态壁纸轮播：横屏和竖屏分别绑定图片目录，支持递归扫描、分辨率过滤和图形设置界面。

## 功能

- 横屏和竖屏分别配置一个或多个目录，包含所有子目录，按路径去重。
- 竖屏可仅使用竖图，并设置最低宽高，默认 1440×2560 像素。
- 可配置切换间隔，默认每分钟随机切换；尽量避免连续重复。
- 填充显示，按屏幕当前方向自动选择图片池。
- 当前用户登录后自动运行；关闭设置窗口不影响轮播。
- 通过 Windows 计划任务和隐藏启动器运行，不需要常驻脚本进程。

## 环境

Windows 11，内置 Windows PowerShell 5.1、Windows Script Host 和任务计划程序。核心多屏功能使用 Windows `IDesktopWallpaper` 接口。当前实现依赖 VBScript；禁用了 Windows Script Host 的环境需要先允许该组件运行。无需下载 PowerShell 模块。

## 开始使用

1. 下载或克隆本仓库，放在可写、固定的本地目录。
2. 双击 `00-settings.cmd`，或双击 `Open-Settings.vbs`。
3. 添加横屏和竖屏图片目录，每行一个路径。
4. 设置过滤规则、切换间隔，勾选自动轮播，点击“保存并应用”。

首次启动自动从 `config.example.json` 创建本地 `config.json`。仓库不附带图片或个人目录配置。第一次扫描大型图库可能需要数分钟；界面显示扫描进度。新增、移动或删除图片后，点击“刷新图片索引”。仅修改间隔时会复用索引。

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

JPG 和 PNG 索引优先读取文件头；实际换图时通过 Windows 图像解码器转换成 JPEG 缓存。源文件保持原样。图片比例与屏幕不一致时，“填充”会裁剪边缘。每块屏幕交替使用两张缓存，图片缓存不会持续增长。

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

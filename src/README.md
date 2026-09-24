# DualScreenWallpaper 2.0 · C# 候选版

应用的设置界面、图片扫描与解码、壁纸处理、计划任务、配置迁移和在线更新已迁移到 C# / .NET 10。运行应用不再依赖 PowerShell 或 VBScript；构建与测试脚本仍使用 PowerShell。根目录保留 1.4.0 维护代码，`src/VERSION` 管理新实现的版本；2.0 尚未发布 GitHub Release，已完成本机原位升级与安装后界面检查。

**淡入淡出的桌面背景层新实现仍待用户手动验收。** 旧的逐帧 SetWallpaper 方案在实际双屏采样中未能证明可见过渡，不能以接口成功代替视觉验收。用户要求暂停改变真实桌面的测试，因此这一项仍未勾选。

## 使用与界面

运行 `DualScreenWallpaper.exe`。新配置打开设置引导；已有配置直接进入设置。界面按屏幕、图片来源、播放参数分组，高级过滤放在独立标签页。窗口可调整大小、最大化；日志区域可通过分隔条扩大。打开或关闭壁纸预览不应改变设置窗口及字体的尺寸。

左侧“主屏默认 / 副屏默认”定义未单独配置的屏幕。选择具体屏幕并勾选独立配置后，可以分别指定图库、排除与过滤规则；第三块及更多屏幕同样支持。未连接屏幕的设置保留，取消独立配置则重新使用默认配置。RDP 会话只能看到远程会话暴露的显示器。

图片来源每行允许一个绝对文件夹路径或图片文件路径，也支持添加按钮和拖放。文件夹递归扫描，图片文件只加入该文件；相同路径不区分大小写去重。两种来源均遵守过滤及排除规则；排除目录同时排除其后代，但不排除同前缀兄弟目录。失效路径、解码错误和跳过的链接会写入日志。扫描不沿目录链接递归。JPG/JPEG/JFIF/PNG/BMP/GIF/TIFF/ICO/WDP/JXR/WebP/HEIC/HEIF/AVIF 的实际支持取决于 Windows 解码器，保留 EXIF 方向处理，多帧图片取第一帧。

播放顺序与效果分开设置。顺序播放按文件名、完整路径排序并记录成功播放位置；随机播放优先避开上一张。支持填充、适应、拉伸、居中和平铺。预览显示实际屏幕布局，可逐屏选择示例图片，调整显示方式后回填到设置；示例图片不自动加入图库。

“保存并应用”保存配置、按需扫描、换图，并根据自动轮播开关管理计划任务。“刷新索引”保存并扫描；“立即换图”使用已保存配置；“停止并恢复”移除属于本目录的任务并恢复可用的原静态壁纸。日志会说明错误与切换回退原因。关闭设置不会停止自动轮播；没有常驻后台服务。多个副本仍共用 `DualScreenWallpaper-1Minute` 任务，请勿同时让不同副本接管轮播。

## 配置与迁移

读取时支持无 SchemaVersion 的旧格式及 Schema 2；保存为 Schema 3，新增 `MonitorProfiles`。读取旧文件不会改写；保存前会创建 `config.json.backup-*.json`，通过临时文件和原子替换避免半写入。导入先载入界面，保存才应用；导出包含当前编辑，路径属于个人信息。

1.4.0 安装版可在原目录运行新安装程序，保留 `config.json` 和 `data/`。安装后原生 C# 程序根据已保存的 AutoStart 迁移旧任务，不主动换图。Schema 3 保存后，旧版无法读取，需要恢复备份才能退回旧配置。

**1.4.0 便携版首次迁移到 2.0 需手动进行**：旧更新器只接受脚本文件，不能直接应用新的二进制 ZIP。停止轮播、备份目录后，解压新的便携版并复制配置及数据，再保存并应用。新版 ZIP 中的 CMD 入口直接启动 EXE，便于沿用原来的快捷入口。

索引兼容限制：2.0 使用 `data/index-v3.json`，目前不转换旧版 `data/index.json`，首次使用需要重新扫描；成功后缓存复用。仅更改播放顺序、间隔或切换效果不会使索引失效。

## 更新与恢复

“检查更新”仅在点击时访问 GitHub 最新正式 Release；显示更新说明，按安装版/便携版选择 EXE/ZIP，校验文件名、来源、大小和 SHA-256。更新后重启，只保留已保存的配置。遇到 GitHub 限流会提示稍后重试。

下载、运行器和备份位于 `data/updates/<本次目录>/`。独立运行器等待设置退出，协调维护与工作进程互斥锁。便携版失败时恢复旧文件；安装版调用安装程序并检查版本，失败时尝试文件恢复。关闭设置后可运行该更新目录的 `Restore.cmd` 手动恢复；文件恢复不重写安装程序的注册信息。更新备份不自动清理。ZIP 仅接受根目录程序文件，不接受配置、data、路径穿越或重复项。

## 淡入淡出与手动验收

新实现通过 Explorer 的背景层临时绘制约 800 ms 过渡，最后保留正常壁纸并销毁窗口，不使用覆盖普通应用的置顶全屏窗口。依赖 Explorer 的背景窗口结构；若找不到兼容背景层、前一张壁纸不可读、使用平铺或单屏超过 1600 万像素，则直接切换并记录原因。该背景层方式不是 Windows 承诺稳定的桌面扩展 API，必须在目标 Windows 版本实际验证。

目前已验证像素混合与独立绘制，但**尚未在真实桌面运行新背景层实现**。待用户方便时，使用现有图片手动检查：主副屏均能看到平滑过渡；普通窗口不被遮挡、不抢焦点；最终壁纸正确；没有残留窗口；本机和 RDP 回退日志清晰。不要仅凭 `Crossfade rendered` 日志判定视觉效果正常。

## 构建

要求 Windows、.NET 10 SDK；生成安装包另需 Inno Setup 6.7+。业务代码没有第三方 NuGet 包。独立发布需要从官方 NuGet 获取 Microsoft 的运行时包。

```powershell
# 在仓库目录执行，SDK 可由 -DotnetPath 指定
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Build.ps1 -Installer
# 小体积版本，要求用户已安装 .NET Desktop Runtime 10 x64
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Build.ps1 -FrameworkDependent
```

独立安装版/便携版包含运行时，解压约 154 MiB；依赖运行时版程序文件不到 1 MiB，但不含运行时成本，不能把两种体积直接比较。相比继续使用 PowerShell，C# 更便于复用当前 Windows/.NET 逻辑；本次没有实现 Rust 原型，不声称比 Rust 更快或更小。

## 验证

```powershell
# 在 src 目录使用 .NET 10 SDK
dotnet run --project DualScreenWallpaper.Tests -c Release
../dist/csharp-v2-standalone/DualScreenWallpaper.exe --self-test --report ../data/new-integration-report.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Test-Preview.ps1 -ApplicationPath ../dist/csharp-v2-standalone/DualScreenWallpaper.exe
```

`--self-test` 覆盖解码、EXIF、混合来源、独立屏幕配置、排序、备份、更新包防护与恢复，不修改壁纸或任务。`Test-Preview.ps1` 在屏幕外测试多次启动、重复预览、窗口缩放、非法配置、报告覆盖保护；截图可能含个人路径，应留在忽略的 data 目录。`Test-Installer.ps1` 使用独立测试 AppId 测试安装、重装、降级阻止和卸载，不替换现有安装。`Test-Desktop.ps1` 会短暂改变真实壁纸，**当前不再自动执行**。

2026-09-25 本地结果：31 项配置回归、32 项图像/更新集成断言、重复预览与缩放测试、独立进程便携升级/恢复、隔离安装/卸载和原生任务注册/清理通过。初步连续启动样本中，旧版脚本入口至界面就绪约 765–806 ms，新版托管入口至界面就绪约 234–249 ms；初始工作集约 135 MiB 和 57 MiB。这些是缓存已热、入口计时的少量样本，不包含进程/运行时启动全部开销，不是冷启动保证。第三块屏幕用独立配置测试覆盖，真实三屏设备尚未验证；RDP 和淡入淡出新实现的视觉验收仍待补充。

## 代码结构

- Core：配置、原子存储、图片来源扫描、过滤、播放顺序。
- Windows：复用 C# COM 接口与图像头解析，WPF 解码、EXIF、渲染。
- App：可缩放 WinForms 设置、预览和引导、工作进程、原生任务、临时桌面过渡层、更新与恢复。
- Tests：无外部测试框架的配置回归运行器。

`--run`、`--apply`、`--index`、`--stop`、`--migrate-task`、`--uninstall` 为工作模式；`--root` 指定工作目录。默认无参数打开设置。`--config` 仅指定初始载入文件，保存目标仍为工作目录下的 config.json。

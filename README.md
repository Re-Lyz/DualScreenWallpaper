# DualScreenWallpaper

简体中文 | [English](README.en.md) | [后续计划](TODO.md) | [更新记录](CHANGELOG.md)

Windows 多屏独立壁纸轮播工具。每块屏幕可使用不同的图片来源和过滤规则，支持随机或顺序播放、淡入淡出，以及应用前预览。基于 C# / .NET 10，关闭设置窗口后仍可通过计划任务自动轮播，无需常驻后台程序。

## 下载与安装

**当前版本：2.0.1。支持 Windows 11 x64。** 在 [GitHub Releases](https://github.com/Re-Lyz/DualScreenWallpaper/releases/latest) 下载：

| 文件 | 适用情况 |
| --- | --- |
| `DualScreenWallpaper-2.0.1-Setup.exe` | 推荐。自带运行时，提供安装、快捷方式和卸载；升级时保留配置和数据 |
| `DualScreenWallpaper-2.0.1.zip` | 自带运行时的便携版，解压到可写目录即可运行 |
| `DualScreenWallpaper-2.0.1-FrameworkDependent.zip` | 精简便携版，需要已安装 .NET Desktop Runtime 10 x64 |
| `*.sha256` | 对应下载文件的 SHA-256 校验值 |

安装版和完整便携版均包含 .NET 运行时，展开约 154 MiB。运行 `DualScreenWallpaper.exe` 打开设置。

## 开始使用

1. 选择主屏、副屏默认配置，或为具体屏幕启用独立配置。
2. 添加文件夹或单张图片；按需设置排除目录、方向和最低分辨率。
3. 在“播放”页分别选择播放顺序、切换效果和时间间隔。
4. 勾选“自动轮播并在登录后运行”，点击“保存并应用”。之后可以关闭设置窗口，轮播仍会继续。

“保存并应用”会立即换图。“停止并恢复”关闭自动轮播并恢复可用的原静态壁纸。窗口顶部显示实际任务状态、上次结果和下次执行时间。窗口大小和日志区域都可调整。

支持填充、适应、拉伸、居中、平铺；图片来源可拖放，配置可导入导出。更多用法见 [详细说明](src/README.md)。

## 升级与兼容性

- 1.4 安装版可使用安装程序在原目录升级，保留 `config.json` 和 `data/`。
- 1.4 便携版首次升级到 2.x 需手动迁移；旧更新器不接受新版二进制包。请先备份并停止旧轮播，再迁移配置和数据。
- 旧图片索引尚不自动转换，首次使用 2.x 需要重新扫描；之后使用缓存。
- 淡入淡出已于 2026-10-06 获用户实机确认可见。效果依赖 Windows 桌面环境；不支持时直接切换并记录原因。RDP 和更多硬件组合尚未全面验收。

旧 PowerShell/VBScript 应用源码已从当前版本移除，可在 [v1.4.0 历史版本](https://github.com/Re-Lyz/DualScreenWallpaper/tree/v1.4.0) 中查看。构建和测试脚本仍使用 PowerShell。

## 开发

源码位于 `src/`，版本统一维护在 `src/VERSION`。需要 .NET 10 SDK；安装包构建另需 Inno Setup 6.7+。

```powershell
# 配置、隔离集成和屏幕外界面测试，不更改真实壁纸
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Test.ps1
# 构建安装包和完整便携版
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Build.ps1 -Installer
```

构建参数、代码结构和验证范围见 [开发说明](src/README.md) 与 [架构说明](ARCHITECTURE.md)。本地 `data/` 保存工具、测试结果和备份，`dist/` 保存构建产物；两者及个人配置均不提交 Git。

# DualScreenWallpaper

简体中文 | [English](README.en.md) | [TODO](TODO.md) | [更新记录](CHANGELOG.md)

Windows 多屏独立壁纸轮播。当前开发版本为 C# / .NET 10 的 2.0 候选版，支持文件夹与单张图片混合来源、多屏独立配置、可缩放设置界面、预览、安装升级和在线更新。

2.0 已在本机安装验证，尚未发布 GitHub Release。淡入淡出仍待真实桌面验收；旧版索引目前不会自动迁移，首次使用新版需要重新扫描。详见 [使用、构建与验证说明](src/README.md)。

## 项目目录

| 路径 | 用途 |
| --- | --- |
| `src/` | 当前 C# 应用、构建脚本、安装程序定义与测试；版本见 `src/VERSION` |
| `legacy/v1.4.0/` | 旧版 PowerShell / VBScript 工程、旧界面、打包脚本与历史文档 |
| `config.example.json` | 当前构建和测试使用的示例配置 |
| `data/` | 本地构建工具、测试结果与备份，不提交 Git |
| `dist/` | 本地生成的安装包和便携版，不提交 Git |

旧工程仅作维护参考。新版不引用 `legacy/` 中的源文件；不要从旧目录启动脚本接管当前壁纸轮播。

## 构建与运行

需要 Windows 和 .NET 10 SDK；构建安装包还需要 Inno Setup。详细参数见 [构建说明](src/README.md)。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Build.ps1 -Installer
```

构建后运行 `dist/csharp-v2-standalone/DualScreenWallpaper.exe`。自带运行时的安装版和便携版无需另外安装 .NET；精简便携版需要 .NET Desktop Runtime 10 x64。

源码目录中的个人 `config.json`、`data/` 和现有 `dist/` 未随工程归档移动；已安装的应用也不受目录整理影响。

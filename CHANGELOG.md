# 更新记录

## [2.0.0] - Unreleased

- C# / .NET 10 应用迁移：配置、扫描解码、播放、预览、计划任务及更新恢复不再依赖 PowerShell/VBScript 运行链。
- 可缩放设置窗口、可调整日志区域，按屏幕/来源/播放分组，并隔离预览布局。
- 图片来源支持文件夹与单张图片混合；Schema 3 支持每块屏幕独立配置并兼容旧配置读取，保存前备份。
- 新增原生 EXE 安装与便携包、旧任务迁移及独立运行器升级恢复。
- 淡入淡出改为临时桌面背景层绘制；离线渲染已验证，真实桌面与 RDP 视觉验收按用户要求暂缓，尚未发布。

## [1.4.0] - 2026-09-24

- 新增直接切换 / 淡入淡出选项，旧配置默认直接切换；过渡失败、平铺或超大屏时退回直接切换。
- 新增手动检查 GitHub 正式版本、更新说明、后台下载及 SHA-256 校验。
- 安装版调用安装程序升级，便携版原位替换程序文件；更新前备份配置与程序，失败回滚，并保留恢复入口。
- Add optional crossfade transitions and verified, user-initiated updates for installed and portable distributions.

- 安装程序新增已安装版本提示页：区分旧版本升级、同版本重新安装，以及较新版本阻止降级，显示版本号、安装目录和配置保留说明。
- 对所选目录中的便携版也显示提示；注册安装缺少有效 VERSION 文件时回退读取安装注册信息。
- 构建脚本支持独立输出目录，便于测试安装程序而不覆盖已发布文件。

## [1.3.0] - 2026-09-23

- 新增当前用户安装包：安装路径、快捷方式、覆盖升级保留配置，以及按安装目录归属清理轮播任务的卸载流程。
- 新增首次设置引导：环境检查、主副屏确认、图库和筛选规则、轮播与预览；可从设置窗口重新打开。
- 局部拆分设置控件、配置保存、界面测试、安装生命周期与打包清单，保留现有 PowerShell / WinForms 架构。
- Add a per-user installer, a first-run setup wizard, and focused separation of UI, lifecycle and packaging responsibilities.

- 新增随机 / 按文件名顺序轮播，按屏幕记住播放位置，顺序播放跳过失效图片并循环。
- 新增配置导入导出，校验格式、提示缺失目录，导入先载入界面，保存前备份原配置。
- 新增屏幕布局及壁纸预览，可选择示例图片、比较五种显示方式；与实际换图共用 EXIF 旋转逻辑。
- Add playback order, validated settings import/export with backups, and monitor-layout wallpaper previews.

- 新增五种全局显示方式，旧配置默认填充，切换模式复用索引。
- 图片目录和排除目录支持多文件夹拖放、路径去重及无效项目提示。
- 主副屏新增常见横竖屏最低分辨率预设，保留自定义输入，不自动启用过滤。
- Add global display modes, folder drag and drop, and resolution presets with Chinese / English UI.

## [1.2.0] - 2026-09-23

- 设置窗口支持简体中文 / English 即时切换，自动保存语言，保留未保存的配置编辑。
- 兼容无语言字段的旧配置；语言变化不重建图片索引、不触发壁纸切换。
- 集中维护界面翻译，新增英文使用说明和双语 TODO 计划。
- Add live Chinese / English switching, persisted language preferences, an English guide and a bilingual roadmap.

## [1.1.0] - 2026-09-23

- 按 Windows 主显示器区分主屏和副屏；不再根据屏幕横竖方向分配图片池。
- 主副屏均可独立开关图片方向过滤、最低宽高过滤，关闭后保留参数。
- 主副屏独立配置排除目录，排除目录及所有子目录不参与扫描。
- 兼容旧版配置，首次保存时备份到 data/config-v1-*.json；配置结构版本升级到 2。
- 设置窗口显示应用版本；新增版本维护和发布打包脚本。

## [1.0.0] - 2026-09-21

- 横屏、竖屏分别选择图片目录，竖屏支持方向与最低分辨率筛选。
- 图形设置、定时轮播、静态壁纸恢复和图片索引。

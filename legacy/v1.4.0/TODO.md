# TODO / 后续计划

已完成项已勾选；其余为后续计划，暂无确定的发布时间。
Completed features are checked below. Remaining features have no committed release dates.

## 安装版问题与改进 / Installed-version issues and improvements

以下为 2026-09-25 用户反馈，针对当前安装版 v1.4.0；尚未完成复现与修复，不应因 C# 重构而遗漏。Reported on 2026-09-25 for installed v1.4.0; reproduction and fixes are pending and should remain tracked during the C# migration.

处理安排：窗口缩放、日志可读性和预览前后布局稳定性纳入后续 UI 重构的验收标准；淡入淡出问题纳入壁纸切换逻辑迁移及实际桌面回归。即使更换实现语言或界面，也需逐项验证后才能勾选完成。Carry resizing, log readability and preview layout stability into UI redesign acceptance; carry crossfade into wallpaper-engine migration and real-desktop regression. Rewriting alone does not resolve these items.

- [ ] **设置窗口可调整大小，改善日志查看 / Resizable Settings and readable logs**：允许拖动窗口边框调整大小及最大化，让日志区域随窗口扩展；设置合理的最小尺寸，避免控件重叠或被裁切。验收时检查日志滚动、长文本以及不同 DPI 下的布局。Allow resizing and maximizing Settings, expand the log area with the window, and enforce a usable minimum size; verify scrolling, long text and different DPI settings.
- [ ] **打开壁纸预览后设置界面尺寸发生变化 / Settings layout changes after wallpaper preview**：用户反馈选择壁纸预览后，设置界面的整体 UI 尺寸或可用空间发生变化。复现打开、关闭及重复打开预览的过程，排查 DPI 自动缩放、字体和布局状态是否意外影响主窗口；验证往返预览后窗口及控件尺寸保持稳定，并分别检查本机会话与远程桌面。Investigate unexpected Settings size/layout changes after opening wallpaper preview; check repeated open/close cycles, DPI scaling, fonts and layout state in local and remote sessions.
- [ ] **淡入淡出效果不明显或疑似未生效 / Crossfade appears ineffective**：用户反馈选择淡入淡出后似乎没有过渡效果，尚未确认原因。检查选项保存与实际加载、中间帧是否应用，以及是否触发直接切换回退；分别在本机桌面和 RDP 会话下观察手动换图与定时轮播，并记录显示模式、分辨率及回退原因。以实际可见过渡为验收依据，不能仅凭图像混合或模拟接口测试判定正常。Investigate a reported lack of visible crossfade: verify persisted settings, applied frames and direct-switch fallback, then observe manual and scheduled changes locally and over RDP with display mode, resolution and fallback reasons recorded. Require visible desktop validation rather than only blend or mock tests.

## 功能计划 / Feature roadmap

- [ ] **单一语言重构（优先 C#）/ Single-language rewrite (C# preferred)**：以体积小、启动快、低内存占用为目标，将应用界面、壁纸处理、配置与更新逻辑统一为编译后的 C# 程序，替代 PowerShell / VBScript 运行链。优先评估 C# 原生 Windows 界面方案，Rust 作为对比候选；先制作最小原型，测量冷启动到可操作界面的时间、换图进程启动耗时、空闲内存和包含运行时依赖的实际安装体积，再确定最终方案。保留旧配置迁移、安装版/便携版及现有功能；不预设换语言就一定更快、更小。Consolidate application logic into compiled C#, comparing a minimal Rust alternative before final selection. Benchmark cold startup, wallpaper-worker startup, idle memory and total installed size including runtime dependencies; preserve migration and existing features.
- [ ] **更简洁的界面设计 / Simpler UI layout**：重新设计信息层级，按“屏幕选择 → 图片来源 → 播放设置”组织主要操作；高级过滤和维护功能按需展开，减少按钮堆叠。播放顺序与切换效果保持独立，明确显示当前状态、保存与应用结果；先做布局原型，并验证中英文、高 DPI 和小屏幕下的可读性。Prototype a clearer screen/source/playback layout with progressive disclosure of advanced options, separate playback order and transition controls, and clear status/save feedback; verify both languages, high DPI and small screens.
- [ ] **图片来源同时支持目录和单张图片 / Folders and individual image paths**：每块屏幕的图片来源允许混合添加文件夹与具体图片文件，支持选择、拖放和粘贴路径。文件夹递归扫描，文件只加入该图片；统一去重，明确标识来源类型并提示失效路径。明确单张图片与过滤/排除规则的关系，兼容旧目录配置及导入导出，复用现有图片格式、EXIF 和解码支持。Allow mixed folders and individual image files through pickers, drag-and-drop and pasted paths; scan folders recursively, deduplicate images, identify source types and report missing paths. Define filtering/exclusion behavior and preserve legacy settings and import/export compatibility.

重构选型说明：当前项目已有 WinForms、.NET 图像处理及 C# Windows 接口封装，因此优先 C# 是基于迁移与维护成本的判断，不是性能测试结论。Rust 也可通过 [Rust for Windows](https://learn.microsoft.com/en-us/windows/dev-environment/rust/rust-for-windows) 调用 Windows API。C# 发布方式需要实测，不能默认 Native AOT 适配现有界面与 COM 调用；参见 [.NET Native AOT 限制](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)。
Language rationale: C# is preferred for continuity with the existing Windows/.NET implementation, not a measured performance advantage. Compare deployment options and validate UI/COM compatibility before choosing AOT.

重构进度：第一阶段已在本地 `src/` 建立 C# 配置迁移、只读界面及屏幕识别原型，并加入配置回归与启动观测；原型源码尚未推送。换图、调度、完整 UI、安装和更新链路尚未迁移，因此重构条目仍保持未完成。Phase one is an isolated, runnable read-only local prototype whose source has not yet been pushed; full feature migration remains in progress.

- [x] **播放顺序选择 / Playback order selection**：支持选择随机、顺序等图片播放方式。Allow choosing random or sequential image playback.
- [x] **幻灯片切换效果 / Slideshow transition effects**：独立选择直接切换或淡入淡出；不支持过渡的场景自动直接切换。Choose Instant or Crossfade independently of playback order, with direct-switch fallback where needed.
- [x] **更多的显示方式 / More display modes**：在填充之外增加适应、拉伸、居中、平铺等模式，说明缩放与裁剪行为。Add Fit, Stretch, Center and Tile alongside Fill, with clear scaling and cropping behavior.
- [x] **拖动文件夹添加目录 / Drag and drop folders**：允许拖入图片目录和排除目录区域，自动去重并提示无效路径。Drop folders into image or exclusion lists, deduplicate entries and report invalid paths.
- [x] **可视化参照界面 / Visual preview**：展示屏幕布局以及图片缩放、裁剪效果，便于应用前确认。Preview monitor layout, scaling and cropping before applying wallpapers.
- [ ] **更多的屏幕拓展（可选）/ Additional monitors (optional)**：评估为第三块及更多屏幕单独设置目录与规则。Consider individual folders and filters for three or more monitors instead of sharing the Secondary profile.
- [x] **配置文件的一键导出和加载 / One-click configuration export and import**：支持导出、加载及格式校验，提示无效目录，并提供覆盖前备份。Export and load settings, validate their format and paths, and back up settings before replacement.
- [x] **软件安装包 / Software installer**：提供可直接运行的安装包，支持安装位置选择、快捷方式创建及卸载，并在升级时保留用户配置。Provide an installer with installation folder selection, shortcuts and uninstall support, preserving user settings during upgrades.
- [x] **在线版本检测和更新 / Online version checks and updates**：手动检查 GitHub 正式版本、查看更新说明、下载并校验更新；支持安装版和便携版，更新前备份并提供恢复入口。Manually check GitHub releases, read notes, download and verify updates for installed and portable copies, with backups and recovery.
- [x] **安装引导 / Setup wizard**：引导用户完成环境检查、主副屏确认、图片目录选择、过滤规则及自动轮播设置。Guide users through prerequisite checks, monitor assignment, image folders, filters and automatic slideshow settings.
- [x] **常见分辨率下拉选项 / Common resolution presets**：在主副屏最低分辨率设置中提供常见横屏、竖屏分辨率下拉选项（如 1920×1080、2560×1440、3840×2160 及对应竖屏尺寸），选中后填入宽高，同时保留自定义输入。Add common landscape and portrait presets to both profiles' minimum-resolution settings (such as 1920×1080, 2560×1440, 3840×2160 and their portrait equivalents), filling in width and height while retaining custom input.

# TODO / 后续计划

已完成项已勾选；其余为后续计划，暂无确定的发布时间。
Completed features are checked below. Remaining features have no committed release dates.

## 安装版问题与改进 / Installed-version issues and improvements

以下为 2026-09-25 用户反馈，针对安装版 v1.4.0。已勾选项已在本地 C# 2.0 候选版实现并通过相应检查；已在本机原位升级验证，但尚未发布 GitHub Release。Reported for installed v1.4.0; checked fixes are implemented and tested in the local C# 2.0 candidate, installed and checked locally, but not released on GitHub.

处理安排：窗口缩放、日志可读性和预览前后布局稳定性纳入后续 UI 重构的验收标准；淡入淡出问题纳入壁纸切换逻辑迁移及实际桌面回归。即使更换实现语言或界面，也需逐项验证后才能勾选完成。Carry resizing, log readability and preview layout stability into UI redesign acceptance; carry crossfade into wallpaper-engine migration and real-desktop regression. Rewriting alone does not resolve these items.

- [x] **设置窗口可调整大小，改善日志查看 / Resizable Settings and readable logs**：允许拖动窗口边框调整大小及最大化，让日志区域随窗口扩展；设置合理的最小尺寸，避免控件重叠或被裁切。验收时检查日志滚动、长文本以及不同 DPI 下的布局。Allow resizing and maximizing Settings, expand the log area with the window, and enforce a usable minimum size; verify scrolling, long text and different DPI settings.
- [x] **打开壁纸预览后设置界面尺寸发生变化 / Settings layout changes after wallpaper preview**：用户反馈选择壁纸预览后，设置界面的整体 UI 尺寸或可用空间发生变化。复现打开、关闭及重复打开预览的过程，排查 DPI 自动缩放、字体和布局状态是否意外影响主窗口；验证往返预览后窗口及控件尺寸保持稳定，并分别检查本机会话与远程桌面。Investigate unexpected Settings size/layout changes after opening wallpaper preview; check repeated open/close cycles, DPI scaling, fonts and layout state in local and remote sessions.
- [ ] **淡入淡出效果不明显或疑似未生效 / Crossfade appears ineffective**：用户反馈选择淡入淡出后似乎没有过渡效果，尚未确认原因。检查选项保存与实际加载、中间帧是否应用，以及是否触发直接切换回退；分别在本机桌面和 RDP 会话下观察手动换图与定时轮播，并记录显示模式、分辨率及回退原因。以实际可见过渡为验收依据，不能仅凭图像混合或模拟接口测试判定正常。Investigate a reported lack of visible crossfade: verify persisted settings, applied frames and direct-switch fallback, then observe manual and scheduled changes locally and over RDP with display mode, resolution and fallback reasons recorded. Require visible desktop validation rather than only blend or mock tests.

- [ ] **旧索引升级迁移 / Legacy index migration**：目前 2.0 使用 index-v3.json，未转换 1.4 的 index.json，首次使用需重新扫描。为兼容的来源与过滤配置转换旧索引，不兼容时明确说明重扫原因。Migrate compatible legacy image indexes to avoid unnecessary full rescans during upgrades.

## 功能计划 / Feature roadmap

- [x] **单一语言重构（C#）/ Single-language rewrite (C#)**：界面、壁纸处理、配置、任务与更新已统一为编译后的 C# 程序，支持旧配置迁移和安装版/便携版。基于现有 Windows/.NET 代码复用与维护成本选择 C#；已观测本地热启动界面耗时、初始工作集和包含运行时的体积，尚未完成冷启动及换图进程基准，也未制作 Rust 对比原型。完整测试范围与限制见 src/README.md。Application logic has moved to C# with migration and packaging. Warm UI startup, initial working set and package size were measured; cold-start/worker benchmarks and a Rust comparison remain unmeasured.
- [x] **更简洁的界面设计 / Simpler UI layout**：重新设计信息层级，按“屏幕选择 → 图片来源 → 播放设置”组织主要操作；高级过滤和维护功能按需展开，减少按钮堆叠。播放顺序与切换效果保持独立，明确显示当前状态、保存与应用结果；先做布局原型，并验证中英文、高 DPI 和小屏幕下的可读性。Prototype a clearer screen/source/playback layout with progressive disclosure of advanced options, separate playback order and transition controls, and clear status/save feedback; verify both languages, high DPI and small screens.
- [x] **图片来源同时支持目录和单张图片 / Folders and individual image paths**：每块屏幕的图片来源允许混合添加文件夹与具体图片文件，支持选择、拖放和粘贴路径。文件夹递归扫描，文件只加入该图片；统一去重，明确标识来源类型并提示失效路径。明确单张图片与过滤/排除规则的关系，兼容旧目录配置及导入导出，复用现有图片格式、EXIF 和解码支持。Allow mixed folders and individual image files through pickers, drag-and-drop and pasted paths; scan folders recursively, deduplicate images, identify source types and report missing paths. Define filtering/exclusion behavior and preserve legacy settings and import/export compatibility.

重构选型说明：当前项目已有 WinForms、.NET 图像处理及 C# Windows 接口封装，因此优先 C# 是基于迁移与维护成本的判断，不是性能测试结论。Rust 也可通过 [Rust for Windows](https://learn.microsoft.com/en-us/windows/dev-environment/rust/rust-for-windows) 调用 Windows API。C# 发布方式需要实测，不能默认 Native AOT 适配现有界面与 COM 调用；参见 [.NET Native AOT 限制](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)。
Language rationale: C# is preferred for continuity with the existing Windows/.NET implementation, not a measured performance advantage. Compare deployment options and validate UI/COM compatibility before choosing AOT.

重构进度：本地 `src/` 已实现 C# 应用、Schema 3 配置、混合图片来源、独立屏幕、可缩放界面、预览、原生任务、安装与更新恢复。详见 [构建与验证说明](src/README.md)。C# 的选择基于现有 Windows/.NET 代码复用和与旧版的本地启动观测；没有制作 Rust 原型，不作跨语言性能保证。C# migration is implemented locally; see the validation report. No Rust prototype or cross-language performance claim is made.

- [x] **播放顺序选择 / Playback order selection**：支持选择随机、顺序等图片播放方式。Allow choosing random or sequential image playback.
- [x] **幻灯片切换效果 / Slideshow transition effects**：独立选择直接切换或淡入淡出；不支持过渡的场景自动直接切换。Choose Instant or Crossfade independently of playback order, with direct-switch fallback where needed.
- [x] **更多的显示方式 / More display modes**：在填充之外增加适应、拉伸、居中、平铺等模式，说明缩放与裁剪行为。Add Fit, Stretch, Center and Tile alongside Fill, with clear scaling and cropping behavior.
- [x] **拖动文件夹添加目录 / Drag and drop folders**：允许拖入图片目录和排除目录区域，自动去重并提示无效路径。Drop folders into image or exclusion lists, deduplicate entries and report invalid paths.
- [x] **可视化参照界面 / Visual preview**：展示屏幕布局以及图片缩放、裁剪效果，便于应用前确认。Preview monitor layout, scaling and cropping before applying wallpapers.
- [x] **更多的屏幕拓展（可选）/ Additional monitors (optional)**：评估为第三块及更多屏幕单独设置目录与规则。Consider individual folders and filters for three or more monitors instead of sharing the Secondary profile.
- [x] **配置文件的一键导出和加载 / One-click configuration export and import**：支持导出、加载及格式校验，提示无效目录，并提供覆盖前备份。Export and load settings, validate their format and paths, and back up settings before replacement.
- [x] **软件安装包 / Software installer**：提供可直接运行的安装包，支持安装位置选择、快捷方式创建及卸载，并在升级时保留用户配置。Provide an installer with installation folder selection, shortcuts and uninstall support, preserving user settings during upgrades.
- [x] **在线版本检测和更新 / Online version checks and updates**：手动检查 GitHub 正式版本、查看更新说明、下载并校验更新；支持安装版和便携版，更新前备份并提供恢复入口。Manually check GitHub releases, read notes, download and verify updates for installed and portable copies, with backups and recovery.
- [x] **安装引导 / Setup wizard**：引导用户完成环境检查、主副屏确认、图片目录选择、过滤规则及自动轮播设置。Guide users through prerequisite checks, monitor assignment, image folders, filters and automatic slideshow settings.
- [x] **常见分辨率下拉选项 / Common resolution presets**：在主副屏最低分辨率设置中提供常见横屏、竖屏分辨率下拉选项（如 1920×1080、2560×1440、3840×2160 及对应竖屏尺寸），选中后填入宽高，同时保留自定义输入。Add common landscape and portrait presets to both profiles' minimum-resolution settings (such as 1920×1080, 2560×1440, 3840×2160 and their portrait equivalents), filling in width and height while retaining custom input.

## 本轮验证与保留事项 / Validation and remaining acceptance

- 已通过配置迁移、EXIF/图像处理、混合来源去重与排除、第三屏独立配置、播放顺序、原子备份、恶意 ZIP 拒绝、部分更新失败回滚、独立进程升级/恢复、临时安装/重装/降级阻止/卸载和任务注册/清理检查。三屏配置使用样本验证；真实三屏硬件尚未验证。
- 主窗口缩放、日志扩展、重复打开预览及中英文界面已检查；150%/200% 为控件缩放模拟，不等于切换系统 DPI 的现场测试。
- **淡入淡出仍未勾选**：已改为临时桌面背景层绘制，并通过离线渲染检查；用户要求不再改动桌面，待用户用现有壁纸手动验收真实显示效果及 RDP 行为。没有把早先红蓝测试的接口返回成功当作新实现通过。
- 本机已从 1.4.0 原位升级到 2.0，安装后界面检查通过，配置和壁纸保留；2.0 候选包未发布 Release。独立版包含 .NET 运行时，解压约 154 MiB；依赖运行时版程序不到 1 MiB，但需要已有 .NET Desktop Runtime 10。

Checked items refer to the local C# candidate. Real-desktop acceptance of the new crossfade implementation is explicitly deferred at the user's request; the local installation has been upgraded; no GitHub Release has been published.
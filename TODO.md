# TODO / 后续计划

已完成项已勾选；其余为后续计划，暂无确定的发布时间。
Completed features are checked below. Remaining features have no committed release dates.

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

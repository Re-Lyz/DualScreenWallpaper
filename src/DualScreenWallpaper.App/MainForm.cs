using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.App;

internal sealed class MainForm : Form
{
    private readonly string root;
    private readonly ListBox monitors = new() { Dock = DockStyle.Fill, IntegralHeight = false, HorizontalScrollbar = true };
    private readonly TextBox sources = PathsBox(), exclusions = PathsBox();
    private readonly TextBox log = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill };
    private readonly Label status = new() { AutoSize = true, Dock = DockStyle.Fill };
    private readonly CheckBox independent = new() { AutoSize = true }, orientationEnabled = new() { AutoSize = true }, minimumEnabled = new() { AutoSize = true }, auto = new() { AutoSize = true };
    private readonly ComboBox orientation = Choice("Landscape", "Portrait"), display = Choice("Fill", "Fit", "Stretch", "Center", "Tile"), order = Choice("Random", "Sequential"), transition = Choice("Instant", "CrossFade"), language = Choice("简体中文", "English");
    private readonly NumericUpDown width = Number(0, 100000), height = Number(0, 100000), interval = Number(1, 1440);
    private readonly List<(Control Control, string Chinese, string English)> translations = [];
    private readonly List<Control> mutating = [];
    private readonly List<string> keys = [];
    private readonly Dictionary<string, ImageProfile> profiles = new(StringComparer.OrdinalIgnoreCase);
    private Settings settings = SettingsReader.Defaults;
    private IReadOnlyList<MonitorInfo> screenInfo = [];
    private string? selected;
    private bool loading, busy, dirty;
    private CancellationTokenSource? cancellation;
    private Control? editor;
    private readonly SplitContainer split = new() { Dock = DockStyle.Fill, Orientation = System.Windows.Forms.Orientation.Horizontal };
    private bool English => language.SelectedIndex == 1;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal Exception? Failure { get; set; }
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool IsSmoke { get; set; }
    public bool LoadedConfiguration { get; private set; }
    public int MonitorCount => screenInfo.Count;

    public MainForm(string root, string? config)
    {
        this.root = root;
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Text = "DualScreenWallpaper v" + Updates.CurrentVersion; Font = new Font("Microsoft YaHei UI", 10);
        ClientSize = new Size(1000, 780); MinimumSize = new Size(820, 660); StartPosition = FormStartPosition.CenterScreen;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 1, RowCount = 4 };
        layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.Percent, 100));
        layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.AutoSize));
        var header = Flow(); header.Controls.Add(L("双屏壁纸", "DualScreenWallpaper")); header.Controls.Add(language);
        header.Controls.Add(Button("首次引导", "Setup wizard", ShowWizard));
        header.Controls.Add(Button("检查更新", "Check updates", ShowUpdates));
        layout.Controls.Add(header); layout.Controls.Add(split);
        var body = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
        editor = body;
        body.ColumnStyles.Add(new(SizeType.Percent, 27)); body.ColumnStyles.Add(new(SizeType.Percent, 73));
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1 };
        left.RowStyles.Add(new(SizeType.AutoSize)); left.RowStyles.Add(new(SizeType.Percent, 100)); left.RowStyles.Add(new(SizeType.AutoSize));
        left.Controls.Add(L("1 · 屏幕与默认配置", "1 · Screens and defaults")); left.Controls.Add(monitors);
        left.Controls.Add(Button("刷新屏幕", "Refresh screens", () => { StoreProfile(); ReadMonitors(); })); body.Controls.Add(left);
        var tabs = new TabControl { Dock = DockStyle.Fill };
        var sourceTab = new TabPage(); T(sourceTab, "2 · 图片来源", "2 · Sources");
        var rulesTab = new TabPage(); T(rulesTab, "高级过滤", "Advanced filters");
        var playTab = new TabPage(); T(playTab, "3 · 播放", "3 · Playback");
        tabs.TabPages.AddRange([sourceTab, rulesTab, playTab]); body.Controls.Add(tabs); split.Panel1.Controls.Add(body);
        var logs = new GroupBox { Dock = DockStyle.Fill, Padding = new Padding(8, 24, 8, 8) }; T(logs, "日志（可拖动上方分隔条调整高度）", "Log (drag the divider to resize)"); logs.Controls.Add(log); split.Panel2.Controls.Add(logs);
        var sourceLayout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(8), ColumnCount = 1, RowCount = 4 };
        sourceLayout.RowStyles.Add(new(SizeType.AutoSize)); sourceLayout.RowStyles.Add(new(SizeType.AutoSize));
        sourceLayout.RowStyles.Add(new(SizeType.Percent, 100)); sourceLayout.RowStyles.Add(new(SizeType.AutoSize));
        T(independent, "为这块屏幕使用独立配置", "Use an independent profile for this screen"); sourceLayout.Controls.Add(independent);
        sourceLayout.Controls.Add(L("每行一个文件夹或图片路径，可拖入；过滤规则也适用于单张图片。", "One folder or image per line; drop files here. Filters also apply to individual images."));
        sourceLayout.Controls.Add(sources);
        var sourceActions = Flow(); sourceActions.Controls.Add(Button("添加文件夹", "Add folder", () => AddFolder(sources)));
        sourceActions.Controls.Add(Button("添加图片", "Add images", AddImages)); sourceActions.Controls.Add(Button("壁纸预览", "Preview", () => OpenPreview(false)));
        sourceLayout.Controls.Add(sourceActions); sourceTab.Controls.Add(sourceLayout);
        var rules = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(8), ColumnCount = 1, RowCount = 5 };
        rules.RowStyles.Add(new(SizeType.AutoSize)); rules.RowStyles.Add(new(SizeType.AutoSize)); rules.RowStyles.Add(new(SizeType.AutoSize)); rules.RowStyles.Add(new(SizeType.Percent, 100)); rules.RowStyles.Add(new(SizeType.AutoSize));
        var direction = Flow(); T(orientationEnabled, "方向过滤", "Orientation filter"); direction.Controls.Add(orientationEnabled); direction.Controls.Add(orientation); rules.Controls.Add(direction);
        var minimum = Flow(); T(minimumEnabled, "最低尺寸", "Minimum size"); minimum.Controls.Add(minimumEnabled); minimum.Controls.Add(width); minimum.Controls.Add(L("×", "×")); minimum.Controls.Add(height);
        var presets = Choice("自定义 / Custom", "1920 × 1080", "2560 × 1440", "3840 × 2160", "1080 × 1920", "1440 × 2560", "2160 × 3840");
        presets.SelectedIndexChanged += (_, _) => { if (presets.SelectedIndex > 0) { var dimensions = presets.Text.Split('×'); width.Value = int.Parse(dimensions[0]); height.Value = int.Parse(dimensions[1]); } };
        minimum.Controls.Add(presets); rules.Controls.Add(minimum);
        rules.Controls.Add(L("排除目录（包含其子目录）", "Excluded folders (including descendants)")); rules.Controls.Add(exclusions);
        rules.Controls.Add(Button("添加排除目录", "Exclude folder", () => AddFolder(exclusions))); rulesTab.Controls.Add(rules);
        var playback = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(12) };
        foreach (var row in new[] { Row("间隔（分钟）", "Interval (minutes)", interval), Row("显示方式", "Display mode", display), Row("播放顺序", "Playback order", order), Row("切换效果", "Transition", transition) }) playback.Controls.Add(row);
        T(auto, "自动轮播并在登录后运行", "Automatic slideshow and run at logon"); playback.Controls.Add(auto);
        playback.Controls.Add(L("保存并应用后生效。淡入淡出回退原因会写入日志。", "Save and apply to activate. Transition fallback reasons appear in the log.")); playTab.Controls.Add(playback);
        var actions = Flow();
        actions.Controls.Add(Button("保存并应用", "Save and apply", async () => await Work("apply", true)));
        actions.Controls.Add(Button("刷新索引", "Refresh index", async () => await Work("index", true)));
        actions.Controls.Add(Button("立即换图", "Change now", async () => await Work("run", false)));
        actions.Controls.Add(Button("停止并恢复", "Stop and restore", async () => await Work("stop", false)));
        actions.Controls.Add(Button("导入", "Import", Import)); actions.Controls.Add(Button("导出", "Export", Export));
        var cancel = Button("取消操作", "Cancel operation", () => cancellation?.Cancel()); mutating.Remove(cancel); actions.Controls.Add(cancel);
        layout.Controls.Add(actions); layout.Controls.Add(status); Controls.Add(layout);
        monitors.SelectedIndexChanged += (_, _) => { if (!loading) { StoreProfile(); ShowProfile(); } };
        independent.CheckedChanged += (_, _) => { if (!loading && selected is not null && selected is not "Primary" and not "Secondary") { if (independent.Checked) profiles[selected] = ReadProfile(); else profiles.Remove(selected); ShowProfile(); dirty = true; } };
        language.SelectedIndexChanged += (_, _) => { RefreshLanguage(); if (!loading) dirty = true; };
        foreach (var text in new[] { sources, exclusions }) { EnableDrop(text); text.TextChanged += (_, _) => { if (!loading) dirty = true; }; }
        foreach (var check in new[] { orientationEnabled, minimumEnabled, auto }) check.CheckedChanged += (_, _) => { if (!loading) dirty = true; };
        foreach (var choice in new[] { orientation, display, order, transition }) choice.SelectedIndexChanged += (_, _) => { if (!loading) dirty = true; };
        var options = new Dictionary<string, string> { ["Landscape"] = "横图", ["Portrait"] = "竖图", ["Fill"] = "填充", ["Fit"] = "适应", ["Stretch"] = "拉伸", ["Center"] = "居中", ["Tile"] = "平铺", ["Random"] = "随机", ["Sequential"] = "按文件名顺序", ["Instant"] = "直接切换", ["CrossFade"] = "淡入淡出" };
        foreach (var choice in new[] { orientation, display, order, transition }) { choice.FormattingEnabled = true; choice.Format += (_, e) => { if (!English && e.ListItem is string key && options.TryGetValue(key, out string? label)) e.Value = label; }; }
        foreach (var number in new[] { width, height, interval }) number.ValueChanged += (_, _) => { if (!loading) dirty = true; };
        LoadSettings(config is not null ? SettingsReader.Load(config) : File.Exists(Path.Combine(root, "config.json")) ? SettingsReader.Load(Path.Combine(root, "config.json")) : SettingsReader.Defaults);
        LoadedConfiguration = config is not null || File.Exists(Path.Combine(root, "config.json"));
        FormClosing += (_, e) => { if (busy) { cancellation?.Cancel(); e.Cancel = true; return; } if (dirty && !IsSmoke && MessageBox.Show(this, English ? "Discard unsaved changes?" : "放弃未保存的修改？", Text, MessageBoxButtons.YesNo) != DialogResult.Yes) e.Cancel = true; };
        Shown += (_, _) => { split.SplitterDistance = split.Height * 2 / 3; if (!settings.SetupCompleted && !IsSmoke) ShowWizard(); };
    }
    private static TextBox PathsBox() => new() { Multiline = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill };
    private static NumericUpDown Number(int min, int max) => new() { Minimum = min, Maximum = max, Width = 100 };
    private static ComboBox Choice(params string[] options) { var box = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 }; box.Items.AddRange(options); box.SelectedIndex = 0; return box; }
    private static FlowLayoutPanel Flow() => new() { Dock = DockStyle.Fill, AutoSize = true, WrapContents = true, Margin = new Padding(0, 4, 0, 4) };
    private void T(Control control, string zh, string en) { translations.Add((control, zh, en)); control.Text = English ? en : zh; }
    private Label L(string zh, string en) { var label = new Label { AutoSize = true, Margin = new Padding(3, 7, 6, 7), MaximumSize = new Size(600, 0) }; T(label, zh, en); return label; }
    private Control Row(string zh, string en, Control control) { var row = Flow(); row.Controls.Add(L(zh, en)); row.Controls.Add(control); return row; }
    private Button Button(string zh, string en, Action action)
    {
        var button = new Button { AutoSize = true, Padding = new Padding(7, 3, 7, 3) }; T(button, zh, en);
        button.Click += (_, _) => { try { action(); } catch (Exception ex) { Error(ex); } }; mutating.Add(button); return button;
    }
    private void Error(Exception ex) { Append(ex.Message); if (!IsSmoke) MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    private void RefreshLanguage()
    {
        foreach (var item in translations) item.Control.Text = English ? item.English : item.Chinese;
        bool previous = loading; loading = true;
        foreach (var choice in new[] { orientation, display, order, transition }) { int index = choice.SelectedIndex; choice.SelectedIndex = -1; choice.SelectedIndex = index; choice.Refresh(); }
        for (int i = 0; i < keys.Count; i++)
        {
            string key = keys[i]; var screen = screenInfo.FirstOrDefault(x => x.Id == key);
            monitors.Items[i] = key == "Primary" ? (English ? "Primary default" : "主屏默认配置") : key == "Secondary" ? (English ? "Secondary default" : "副屏默认配置") :
                screen is not null ? $"{(screen.Primary ? (English ? "Primary" : "主屏") : (English ? "Screen" : "屏幕"))} {screen.Width}×{screen.Height}" :
                (English ? "Disconnected profile " : "未连接屏幕配置 ") + (i - 1);
        }
        loading = previous;
    }
    private void Append(string message)
    {
        if (IsDisposed) return;
        if (InvokeRequired) { BeginInvoke((Action)(() => Append(message))); return; }
        if (log.TextLength > 200000) log.Text = log.Text[^100000..];
        log.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}\r\n"); status.Text = message;
    }
    private void LoadSettings(Settings value)
    {
        loading = true; settings = value; selected = null;
        profiles.Clear(); profiles["Primary"] = value.Primary; profiles["Secondary"] = value.Secondary;
        foreach (var pair in value.MonitorProfiles) profiles[pair.Key] = pair.Value;
        language.SelectedIndex = value.Language == "en-US" ? 1 : 0;
        interval.Value = value.IntervalMinutes; auto.Checked = value.AutoStart; display.SelectedItem = value.DisplayMode; order.SelectedItem = value.PlaybackOrder; transition.SelectedItem = value.TransitionEffect;
        loading = false; ReadMonitors(); dirty = false; RefreshLanguage();
        status.Text = SystemInformation.TerminalServerSession ? (English ? "Remote desktop session" : "远程桌面会话") : (English ? "Ready" : "就绪");
    }
    private void ReadMonitors()
    {
        screenInfo = MonitorReader.Read(); loading = true; keys.Clear(); monitors.Items.Clear();
        keys.AddRange(["Primary", "Secondary"]); monitors.Items.AddRange(["主屏默认 / Primary default", "副屏默认 / Secondary default"]);
        foreach (var m in screenInfo) { keys.Add(m.Id); monitors.Items.Add($"{(m.Primary ? "主屏 / Primary" : "屏幕 / Screen")} {m.Width}×{m.Height}"); }
        foreach (string id in profiles.Keys.Except(keys).ToArray()) { keys.Add(id); monitors.Items.Add("未连接 / Disconnected: " + id); }
        monitors.SelectedIndex = 0; loading = false; ShowProfile(); RefreshLanguage();
    }
    private void ShowProfile()
    {
        if (monitors.SelectedIndex < 0) return;
        loading = true; selected = keys[monitors.SelectedIndex];
        bool isDefault = selected is "Primary" or "Secondary";
        independent.Enabled = !isDefault && !busy; independent.Checked = !isDefault && profiles.ContainsKey(selected);
        var profile = profiles.TryGetValue(selected, out var p) ? p : profiles[screenInfo.Any(x => x.Id == selected && x.Primary) ? "Primary" : "Secondary"];
        sources.Lines = profile.Roots; exclusions.Lines = profile.ExcludeFolders; orientationEnabled.Checked = profile.OrientationEnabled;
        orientation.SelectedItem = profile.Orientation; minimumEnabled.Checked = profile.MinResolutionEnabled; width.Value = profile.MinWidth; height.Value = profile.MinHeight;
        foreach (var c in new Control[] { sources, exclusions, orientationEnabled, orientation, minimumEnabled, width, height }) c.Enabled = !busy && (isDefault || independent.Checked);
        loading = false;
    }
    private static string[] Lines(TextBox box) => box.Lines.Select(x => x.Trim().Trim('"')).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    private static string Selected(ComboBox box) => (string)(box.SelectedItem ?? throw new InvalidOperationException("No selection."));
    private ImageProfile ReadProfile() => new(Lines(sources), Lines(exclusions), orientationEnabled.Checked, Selected(orientation), minimumEnabled.Checked, (int)width.Value, (int)height.Value);
    private void StoreProfile() { if (selected is not null && (selected is "Primary" or "Secondary" || independent.Checked)) profiles[selected] = ReadProfile(); }
    private Settings ReadSettings()
    {
        StoreProfile();
        var value = new Settings(3, English ? "en-US" : "zh-CN", Selected(display), Selected(order), Selected(transition), true, profiles["Primary"], profiles["Secondary"], (int)interval.Value, auto.Checked)
        { MonitorProfiles = profiles.Where(x => x.Key is not "Primary" and not "Secondary").ToDictionary(x => x.Key, x => x.Value, StringComparer.OrdinalIgnoreCase) };
        return SettingsReader.Parse(SettingsReader.Serialize(value));
    }
    private void AddFolder(TextBox target) { if (!target.Enabled) { Append("请先启用独立配置 / Enable the independent profile first."); return; } using var dialog = new FolderBrowserDialog(); if (dialog.ShowDialog(this) == DialogResult.OK) AddPaths(target, [dialog.SelectedPath]); }
    private void AddImages() { if (!sources.Enabled) return; using var dialog = new OpenFileDialog { Multiselect = true, Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff;*.webp;*.heic;*.heif;*.avif;*.jxr;*.wdp;*.ico|All files|*.*" }; if (dialog.ShowDialog(this) == DialogResult.OK) AddPaths(sources, dialog.FileNames); }
    private void AddPaths(TextBox target, IEnumerable<string> paths)
    {
        var list = Lines(target).ToList();
        foreach (string path in paths) { if (!Directory.Exists(path) && (target == exclusions || !File.Exists(path))) { Append("Invalid source: " + path); continue; } list.Add(Path.GetFullPath(path)); }
        target.Lines = list.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }
    private void EnableDrop(TextBox target)
    {
        target.AllowDrop = true;
        target.DragEnter += (_, e) => e.Effect = target.Enabled && e.Data?.GetDataPresent(DataFormats.FileDrop) == true ? DragDropEffects.Copy : DragDropEffects.None;
        target.DragDrop += (_, e) => { if (target.Enabled && e.Data?.GetData(DataFormats.FileDrop) is string[] paths) AddPaths(target, paths); };
    }
    private void Import() { using var dialog = new OpenFileDialog { Filter = "Configuration|*.json" }; if (dialog.ShowDialog(this) == DialogResult.OK) { LoadSettings(SettingsReader.Load(dialog.FileName)); dirty = true; Append("已载入，保存后生效 / Imported; save to apply."); } }
    private void Export() { var value = ReadSettings(); using var dialog = new SaveFileDialog { Filter = "Configuration|*.json", FileName = "wallpaper-settings.json" }; if (dialog.ShowDialog(this) == DialogResult.OK) Storage.SaveSettings(dialog.FileName, value); }
    private async Task Work(string operation, bool save)
    {
        if (busy) return;
        try
        {
            if (save) { settings = ReadSettings(); Storage.SaveSettings(Path.Combine(root, "config.json"), settings); dirty = false; LoadedConfiguration = true; }
            busy = true; cancellation = new(); SetBusy(true);
            await RuntimeService.OnSta(() => new RuntimeService(root, Append).Execute(operation, cancellation.Token)); Append("完成 / Completed");
        }
        catch (OperationCanceledException) { Append("已取消 / Cancelled"); }
        catch (Exception ex) { Error(ex); }
        finally { cancellation?.Dispose(); cancellation = null; busy = false; SetBusy(false); }
    }
    private void SetBusy(bool value) { foreach (var control in mutating) control.Enabled = !value; if (editor is not null) editor.Enabled = !value; monitors.Enabled = language.Enabled = !value; if (!value) ShowProfile(); }
    private void OpenPreview(bool smoke)
    {
        var bounds = Bounds; var font = Font; int dpi = DeviceDpi;
        using var preview = new PreviewForm(screenInfo, Selected(display), English);
        if (smoke) preview.Shown += (_, _) => preview.BeginInvoke((Action)(() => preview.Close()));
        if (preview.ShowDialog(this) == DialogResult.OK) { display.SelectedItem = preview.SelectedMode; dirty = true; }
        if (smoke && (Bounds != bounds || Font != font || DeviceDpi != dpi)) throw new InvalidOperationException("Preview changed Settings geometry.");
    }
    private void ShowWizard()
    {
        using var wizard = new SetupForm(ReadSettings(), screenInfo, English);
        if (wizard.ShowDialog(this) == DialogResult.OK && wizard.Result is not null) { LoadSettings(wizard.Result); dirty = true; Append("引导已完成，请保存并应用 / Setup complete; save and apply."); }
    }
    private void ShowUpdates() { using var dialog = new UpdateForm(root, English); dialog.ShowDialog(this); if (dialog.RestartRequested) { dirty = false; Close(); } }
    public void ValidateLoadedState()
    {
        _ = ReadSettings();
        if (language.SelectedIndex < 0 || string.IsNullOrWhiteSpace(language.Text)) throw new InvalidOperationException("Language selection was lost.");
        if (monitors.Items.Count != keys.Count) throw new InvalidOperationException("Monitor selection mismatch.");
        for (int i = 0; i < 3; i++) OpenPreview(true);
        var original = Size; int oldLog = log.Height;
        Size = new Size(Width + 100, Height + 120); PerformLayout();
        if (log.Height <= oldLog) throw new InvalidOperationException("Log did not expand with the window.");
        Size = original; dirty = false;
    }
}

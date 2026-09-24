using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.App;

internal sealed class SetupForm : Form
{
    public Settings? Result { get; private set; }
    public SetupForm(Settings settings, IReadOnlyList<MonitorInfo> screens, bool english)
    {
        Text = english ? "First-run setup" : "首次设置引导";
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(720, 440); MinimumSize = new Size(600, 400); StartPosition = FormStartPosition.CenterParent;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18), RowCount = 4, ColumnCount = 1 };
        layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.Percent, 50)); layout.RowStyles.Add(new(SizeType.Percent, 50)); layout.RowStyles.Add(new(SizeType.AutoSize));
        layout.Controls.Add(new Label { AutoSize = true, Text = (english ? "Detected screens: " : "检测到屏幕：") + string.Join(", ", screens.Select(m => $"{m.Width}×{m.Height}")) + "\n" + (english ? "Choose libraries. Review filters and playback in Settings before applying." : "选择图库后，可在设置中调整过滤与播放方式，再保存并应用。") });
        var primary = new TextBox { Multiline = true, Dock = DockStyle.Fill, Lines = settings.Primary.Roots };
        var secondary = new TextBox { Multiline = true, Dock = DockStyle.Fill, Lines = settings.Secondary.Roots };
        foreach (var (box, title) in new[] { (primary, english ? "Primary" : "主屏图库"), (secondary, english ? "Secondary" : "副屏图库") })
        {
            var group = new GroupBox { Text = title, Dock = DockStyle.Fill, Padding = new Padding(8, 22, 8, 8) };
            var add = new Button { Text = english ? "Add folder" : "添加文件夹", Dock = DockStyle.Bottom };
            add.Click += (_, _) => { using var dialog = new FolderBrowserDialog(); if (dialog.ShowDialog(this) == DialogResult.OK) box.AppendText((box.TextLength > 0 ? "\r\n" : "") + dialog.SelectedPath); };
            group.Controls.Add(box); group.Controls.Add(add); layout.Controls.Add(group);
        }
        var done = new Button { Text = english ? "Finish (review before applying)" : "完成并返回设置", AutoSize = true };
        done.Click += (_, _) =>
        {
            try
            {
                string[] p = primary.Lines.Where(x => !string.IsNullOrWhiteSpace(x)).ToArray(), s = secondary.Lines.Where(x => !string.IsNullOrWhiteSpace(x)).ToArray();
                if (p.Length == 0) throw new FormatException(english ? "Choose a Primary source." : "请选择主屏图库。");
                var secondaryProfile = settings.Secondary with { Roots = s };
                if (screens.Count <= 1 && s.Length == 0) secondaryProfile = settings.Primary with { Roots = p };
                var candidate = settings with { Primary = settings.Primary with { Roots = p }, Secondary = secondaryProfile, SetupCompleted = true };
                Result = SettingsReader.Parse(SettingsReader.Serialize(candidate)); DialogResult = DialogResult.OK; Close();
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message); }
        };
        layout.Controls.Add(done); Controls.Add(layout);
    }
}

using DualScreenWallpaper.Windows;
using System.Windows.Media.Imaging;

namespace DualScreenWallpaper.App;

internal sealed class PreviewForm : Form
{
    private readonly PictureBox picture = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.FromArgb(30, 30, 30) };
    private readonly ComboBox monitors = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 }, modes = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
    private readonly IReadOnlyList<MonitorInfo> screens;
    private readonly CheckBox layoutMode = new() { AutoSize = true, Checked = true };
    private readonly Dictionary<string, string> samples = [];
    private string? sample;
    public string SelectedMode => modes.Text;
    public PreviewForm(IReadOnlyList<MonitorInfo> screens, string mode, bool english)
    {
        this.screens = screens;
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Microsoft YaHei UI", 10); Text = english ? "Wallpaper preview" : "壁纸预览";
        ClientSize = new Size(860, 570); MinimumSize = new Size(620, 420); StartPosition = FormStartPosition.CenterParent;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, Padding = new Padding(12) };
        layout.RowStyles.Add(new(SizeType.Percent, 100)); layout.RowStyles.Add(new(SizeType.AutoSize)); layout.Controls.Add(picture);
        var bar = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        modes.Items.AddRange(RuntimeService.Modes); modes.SelectedItem = mode;
        foreach (var screen in screens) monitors.Items.Add($"{(screen.Primary ? "Primary" : "Secondary")} {screen.Width}×{screen.Height}");
        var choose = new Button { Text = english ? "Choose image" : "选择图片", AutoSize = true };
        var use = new Button { Text = english ? "Use this mode" : "使用此显示方式", AutoSize = true };
        layoutMode.Text = english ? "Screen layout" : "屏幕布局";
        bar.Controls.AddRange([monitors, modes, choose, use, layoutMode]); layout.Controls.Add(bar); Controls.Add(layout);
        choose.Click += (_, _) => { using var dialog = new OpenFileDialog(); if (dialog.ShowDialog(this) == DialogResult.OK && monitors.SelectedIndex >= 0) { sample = dialog.FileName; samples[screens[monitors.SelectedIndex].Id] = sample; Render(); } };
        use.Click += (_, _) => { DialogResult = DialogResult.OK; Close(); };
        modes.SelectedIndexChanged += (_, _) => Render(); monitors.SelectedIndexChanged += (_, _) => { sample = monitors.SelectedIndex >= 0 && samples.TryGetValue(screens[monitors.SelectedIndex].Id, out var value) ? value : null; Render(); };
        layoutMode.CheckedChanged += (_, _) => Render();
        if (screens.Count > 0) monitors.SelectedIndex = 0;
    }
    private void Render()
    {
        if (monitors.SelectedIndex < 0) return;
        if (layoutMode.Checked) { RenderLayout(); return; }
        var screen = screens[monitors.SelectedIndex]; string path = sample ?? screen.Wallpaper;
        if (!File.Exists(path)) return;
        try
        {
            if ((long)screen.Width * screen.Height > 16000000) throw new InvalidOperationException("Preview exceeds 16 million pixels.");
            var frame = Images.Canvas(Images.Load(path), screen.Width, screen.Height, modes.Text, 0);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(frame));
            using var stream = new MemoryStream(); encoder.Save(stream); stream.Position = 0;
            using var decoded = Image.FromStream(stream);
            var old = picture.Image; picture.Image = new Bitmap(decoded); old?.Dispose();
        }
        catch (Exception ex) { Text = "Preview: " + ex.Message; }
    }
    private Bitmap ScreenBitmap(MonitorInfo screen, string path)
    {
        if ((long)screen.Width * screen.Height > 16000000) throw new InvalidOperationException("Preview exceeds 16 million pixels.");
        var frame = Images.Canvas(Images.Load(path), screen.Width, screen.Height, modes.Text, 0);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(frame));
        using var stream = new MemoryStream(); encoder.Save(stream); stream.Position = 0;
        using var decoded = Image.FromStream(stream); return new Bitmap(decoded);
    }
    private void RenderLayout()
    {
        var output = new Bitmap(1000, 600);
        try
        {
            using var graphics = Graphics.FromImage(output); graphics.Clear(Color.FromArgb(30, 30, 30));
            int left = screens.Min(s => s.Left), top = screens.Min(s => s.Top);
            int width = screens.Max(s => s.Left + s.Width) - left, height = screens.Max(s => s.Top + s.Height) - top;
            float scale = Math.Min(960f / width, 560f / height);
            foreach (var screen in screens)
            {
                var rectangle = new RectangleF(20 + (screen.Left - left) * scale, 20 + (screen.Top - top) * scale, screen.Width * scale, screen.Height * scale);
                string path = samples.TryGetValue(screen.Id, out var value) ? value : screen.Wallpaper;
                if (File.Exists(path)) { using var image = ScreenBitmap(screen, path); graphics.DrawImage(image, rectangle); }
                graphics.DrawRectangle(Pens.LightSteelBlue, rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height);
                graphics.FillRectangle(Brushes.Black, rectangle.X, rectangle.Y, rectangle.Width, 23);
                graphics.DrawString($"{(screen.Primary ? "Primary" : "Secondary")} · {screen.Width}×{screen.Height}", Font, Brushes.White, rectangle.X + 4, rectangle.Y + 2);
            }
            var old = picture.Image; picture.Image = output; old?.Dispose();
        }
        catch (Exception ex) { output.Dispose(); Text = "Preview: " + ex.Message; }
    }
    protected override void Dispose(bool disposing) { if (disposing) picture.Image?.Dispose(); base.Dispose(disposing); }
}

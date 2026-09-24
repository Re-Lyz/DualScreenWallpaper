using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.App;

internal sealed class UpdateForm : Form
{
    public bool RestartRequested { get; private set; }
    public UpdateForm(string root, bool english)
    {
        Text = english ? "Check updates" : "检查更新"; ClientSize = new Size(760, 480); MinimumSize = new Size(600, 380);
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi; StartPosition = FormStartPosition.CenterParent;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), RowCount = 4, ColumnCount = 1 };
        layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.Percent, 100)); layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.AutoSize));
        var status = new Label { AutoSize = true, Text = english ? "Checking GitHub…" : "正在检查 GitHub…" };
        var notes = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill };
        var download = new Button { AutoSize = true, Text = english ? "Download update" : "下载更新", Enabled = false };
        var apply = new Button { AutoSize = true, Text = english ? "Update and restart" : "更新并重启", Enabled = false };
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill }; buttons.Controls.AddRange([download, apply]);
        layout.Controls.Add(status); layout.Controls.Add(notes); layout.Controls.Add(new Label { AutoSize = true, Text = english ? "Only saved settings are retained. Close this dialog and save pending edits first." : "仅保留已保存的设置。如有未保存修改，请先关闭此窗口并保存。" }); layout.Controls.Add(buttons); Controls.Add(layout);
        var cancel = new CancellationTokenSource(); string job = Path.Combine(root, "data", "updates", Guid.NewGuid().ToString("N")); Directory.CreateDirectory(job);
        ReleaseInfo? info = null; FormClosed += (_, _) => cancel.Cancel();
        Shown += async (_, _) =>
        {
            try
            {
                string metadata = Path.Combine(job, "release.json");
                await Updates.Download("https://api.github.com/repos/Re-Lyz/DualScreenWallpaper/releases/latest", metadata, 2 * 1024 * 1024, cancel.Token);
                info = Updates.ParseRelease(await File.ReadAllTextAsync(metadata, cancel.Token), Updates.IsInstalled(root));
                if (IsDisposed) return;
                notes.Text = info.Notes.ReplaceLineEndings("\r\n"); status.Text = $"{Updates.CurrentVersion} → {info.Version} ({(info.Installed ? "Installed" : "Portable")})";
                download.Enabled = Version.Parse(info.Version) > Version.Parse(Updates.CurrentVersion);
                if (!download.Enabled) status.Text += english ? " — No update available" : " — 无需更新";
            }
            catch (Exception ex) { if (!IsDisposed) status.Text = ex.Message; }
        };
        download.Click += async (_, _) =>
        {
            if (info is null) return; download.Enabled = false;
            try
            {
                string target = Path.Combine(job, info.Name); if (File.Exists(target)) File.Delete(target);
                status.Text = english ? "Downloading and verifying…" : "正在下载并校验…";
                await Updates.Download(info.Url, target, info.Size, cancel.Token); Updates.Verify(info, target);
                if (!IsDisposed) { apply.Enabled = true; status.Text = english ? "SHA-256 verified" : "SHA-256 校验完成"; }
            }
            catch (Exception ex) { if (!IsDisposed) { status.Text = ex.Message; download.Enabled = true; } }
        };
        apply.Click += (_, _) =>
        {
            try { if (info is null) return; string runner = Updates.PrepareRunner(root, job, info); Updates.StartRunner(runner, job); RestartRequested = true; Close(); }
            catch (Exception ex) { status.Text = ex.Message; }
        };
    }
}

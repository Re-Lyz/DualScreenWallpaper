using System.Diagnostics;
using System.Text.Json;
using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var watch = Stopwatch.StartNew();
        bool automated = args.Any(x => x is "--smoke" or "--run" or "--apply" or "--index" or "--stop" or "--uninstall" or "--self-test");
        try
        {
            string? config = null, report = null, operation = null, job = null;
            string root = Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory);
            int parent = 0; bool restore = false, restart = true; float uiScale = 1;
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--smoke": break;
                    case "--config" when i + 1 < args.Length: config = Path.GetFullPath(args[++i]); break;
                    case "--report" when i + 1 < args.Length: report = Path.GetFullPath(args[++i]); break;
                    case "--root" when i + 1 < args.Length: root = Path.GetFullPath(args[++i]); break;
                    case "--run": operation = "run"; break;
                    case "--apply": operation = "apply"; break;
                    case "--index": operation = "index"; break;
                    case "--stop": operation = "stop"; break;
                    case "--uninstall": operation = "uninstall"; break;
                    case "--migrate-task": operation = "migrate-task"; automated = true; break;
                    case "--self-test": operation = "self-test"; break;
                    case "--update-job" when i + 1 < args.Length: job = Path.GetFullPath(args[++i]); break;
                    case "--parent" when i + 1 < args.Length: parent = int.Parse(args[++i]); break;
                    case "--restore": restore = true; break;
                    case "--no-restart": restart = false; automated = true; break;
                    case "--check-update": operation = "check-update"; automated = true; break;
                    case "--ui-scale" when i + 1 < args.Length: uiScale = float.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture); break;
                    default: throw new ArgumentException("Usage: [--config absolute-path] [--smoke --report output.json]");
                }
            }
            if (args.Contains("--smoke") && report is null) throw new ArgumentException("--smoke requires --report.");
            if (uiScale is < 1 or > 2 || (uiScale != 1 && !args.Contains("--smoke"))) throw new ArgumentException("--ui-scale is a smoke-test option between 1 and 2.");
            if (report is not null && config is not null &&
                string.Equals(report, config, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("Report must not overwrite the configuration.");
            ApplicationConfiguration.Initialize();
            if (job is not null) { Updates.Apply(job, parent, restore, restart); return 0; }
            if (operation == "check-update")
            {
                if (report is null) throw new ArgumentException("--check-update requires --report");
                string temporary = Path.Combine(Path.GetTempPath(), "dsw-release-" + Guid.NewGuid() + ".json");
                try { Updates.Download("https://api.github.com/repos/Re-Lyz/DualScreenWallpaper/releases/latest", temporary, 2 * 1024 * 1024, CancellationToken.None).GetAwaiter().GetResult();
                    var release = Updates.ParseRelease(File.ReadAllText(temporary), Updates.IsInstalled(root));
                    using var output = new FileStream(report, FileMode.CreateNew); JsonSerializer.Serialize(output, release); }
                finally { if (File.Exists(temporary)) File.Delete(temporary); }
                return 0;
            }
            if (operation == "self-test") { IntegrationTests.Run(report ?? throw new ArgumentException("--self-test requires --report")); return 0; }
            if (operation is not null)
            {
                string logs = Path.Combine(root, "data"); Directory.CreateDirectory(logs);
                string output = Path.Combine(logs, "worker.log");
                if (File.Exists(output) && new FileInfo(output).Length > 1024 * 1024) File.Move(output, output + ".old", true);
                void Log(string message) => File.AppendAllText(output, $"{DateTime.Now:O} {message}\n");
                try { new RuntimeService(root, Log).Execute(operation); }
                catch (Exception ex) { Log(ex.ToString()); throw; }
                return 0;
            }
            if (RuntimeService.MaintenanceActive()) throw new IOException("Installation or update in progress.");
            using var mutex = new Mutex(false, automated ? "Local\\DualScreenWallpaperSmoke" : "Local\\DualScreenWallpaperSettings", out bool fresh);
            if (!fresh && !automated) throw new IOException("Close the existing Settings window first.");
            using var form = new MainForm(root, config) { IsSmoke = automated };
            if (uiScale != 1) form.Scale(new SizeF(uiScale, uiScale));
            if (automated) { form.StartPosition = FormStartPosition.Manual; form.Location = new Point(-30000, -30000); form.ShowInTaskbar = false; }
            form.Shown += (_, _) => form.BeginInvoke((Action)(() =>
            {
                if (!automated) return;
                try
                {
                    double readyMilliseconds = watch.Elapsed.TotalMilliseconds;
                    using var process = Process.GetCurrentProcess();
                    long readyWorkingSet = process.WorkingSet64;
                    form.ValidateLoadedState();
                    // CreateNew also guards existing personal files passed as --report.
                    using var stream = new FileStream(report!, FileMode.CreateNew);
                    using var bitmap = new Bitmap(form.Width, form.Height);
                    form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                    using (var capture = new FileStream(report! + ".png", FileMode.CreateNew))
                        bitmap.Save(capture, System.Drawing.Imaging.ImageFormat.Png);
                    JsonSerializer.Serialize(stream, new
                    {
                        Success = true, StartupMilliseconds = readyMilliseconds,
                        WorkingSetBytes = readyWorkingSet,
                        form.LoadedConfiguration, form.MonitorCount,
                        RemoteSession = SystemInformation.TerminalServerSession,
                        Runtime = Environment.Version.ToString()
                    }, new JsonSerializerOptions { WriteIndented = true });
                }
                catch (Exception ex) { form.Failure = ex; }
                finally { form.Close(); }
            }));
            Application.Run(form);
            if (form.Failure is not null) throw form.Failure;
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            if (!automated) MessageBox.Show(ex.Message, "DualScreenWallpaper", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

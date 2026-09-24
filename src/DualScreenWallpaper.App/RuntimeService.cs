using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using DualScreenWallpaper.Core;
using DualScreenWallpaper.Windows;

namespace DualScreenWallpaper.App;

internal sealed record PlaybackState(string Source, int Slot);
internal sealed record OriginalWallpaper(int Position, OriginalMonitor[] Monitors);
internal sealed record OriginalMonitor(string Id, string Path);

internal sealed class RuntimeService(string root, Action<string> log)
{
    public string Root { get; } = Path.GetFullPath(root);
    private string Data => Path.Combine(Root, "data");
    private string Config => Path.Combine(Root, "config.json");
    public static string[] Modes => ["Center", "Tile", "Stretch", "Fit", "Fill"];

    public static Task OnSta(Action action) => OnSta(() => { action(); return true; });
    public static Task<T> OnSta<T>(Func<T> action)
    {
        var done = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() => { try { done.SetResult(action()); } catch (Exception ex) { done.SetException(ex); } }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); return done.Task;
    }
    public static bool MaintenanceActive()
    {
        if (!Mutex.TryOpenExisting("Local\\DualScreenWallpaperMaintenance", out var mutex)) return false;
        mutex.Dispose(); return true;
    }
    public void Execute(string operation, CancellationToken token = default)
    {
        Directory.CreateDirectory(Data);
        using var mutex = new Mutex(false, "Local\\DualScreenWallpaperWorker");
        bool held;
        try { held = mutex.WaitOne(0); } catch (AbandonedMutexException) { held = true; }
        if (!held) throw new InvalidOperationException("Another wallpaper operation is running.");
        try
        {
            if (MaintenanceActive() && operation != "uninstall") throw new InvalidOperationException("Installation or update is in progress.");
            if (operation is "stop" or "uninstall")
            {
                if (ScheduledSlideshow.RemoveOwned(Root, log)) Restore();
                return;
            }
            var settings = SettingsReader.Load(Config);
            if (operation == "migrate-task")
            {
                if (settings.AutoStart) ScheduledSlideshow.Register(Root, settings.IntervalMinutes);
                else ScheduledSlideshow.RemoveOwned(Root, log);
                return;
            }
            string indexPath = Path.Combine(Data, "index-v3.json");
            var index = Storage.Read<LibraryIndex>(indexPath);
            if (operation == "index" || index is null || index.Signature != ImageLibrary.Signature(settings))
            {
                var candidate = ImageLibrary.Scan(settings, Images.Dimensions, log, token);
                foreach (var monitor in MonitorReader.Read())
                {
                    string key = settings.MonitorProfiles.ContainsKey(monitor.Id) ? monitor.Id : monitor.Primary ? "Primary" : "Secondary";
                    if (candidate.Pools[key].Length == 0) throw new InvalidOperationException("No eligible images for " + key + ". Previous index retained.");
                }
                Storage.Write(indexPath, candidate); index = candidate;
            }
            if (operation == "index") return;
            Apply(settings, index, token);
            if (operation == "apply")
            {
                if (settings.AutoStart) ScheduledSlideshow.Register(Root, settings.IntervalMinutes);
                else ScheduledSlideshow.RemoveOwned(Root, log);
                log(settings.AutoStart ? "Slideshow enabled." : "Applied once. Slideshow disabled.");
            }
        }
        finally { mutex.ReleaseMutex(); }
    }
    private void Apply(Settings settings, LibraryIndex index, CancellationToken token)
    {
        using var desktop = Wallpaper.Desktop.Open();
        var monitors = MonitorReader.Read();
        if (monitors.Count == 0) throw new InvalidOperationException("No active monitor in this session.");
        string original = Path.Combine(Data, "original.json");
        if (!File.Exists(original)) Storage.Write(original, new OriginalWallpaper(desktop.GetPosition(),
            monitors.Select(m => new OriginalMonitor(m.Id, desktop.GetWallpaper(m.Id))).ToArray()));
        string statePath = Path.Combine(Data, "state.json");
        var state = Storage.Read<Dictionary<string, PlaybackState>>(statePath) ?? [];
        int oldPosition = desktop.GetPosition();
        desktop.SetPosition(Array.IndexOf(Modes, settings.DisplayMode));
        foreach (var monitor in monitors)
        {
            token.ThrowIfCancellationRequested();
            string key = settings.MonitorProfiles.ContainsKey(monitor.Id) ? monitor.Id : monitor.Primary ? "Primary" : "Secondary";
            state.TryGetValue(monitor.Id, out var previous);
            bool changed = false;
            foreach (string source in ImageLibrary.Candidates(index.Pools[key], previous?.Source, settings.PlaybackOrder))
            {
                token.ThrowIfCancellationRequested();
                try
                {
                    string hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(monitor.Id)))[..16];
                    int slot = 1 - (previous?.Slot ?? 0);
                    string output = Path.Combine(Data, $"{hash}-{slot}.jpg");
                    Images.Save(Images.Load(source), output);
                    Transition(desktop, monitor, output, settings, oldPosition, token);
                    state[monitor.Id] = new(source, slot); Storage.Write(statePath, state);
                    log($"{key} {monitor.Width}×{monitor.Height}: {source}"); changed = true; break;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { log($"Skipped {source}: {ex.Message}"); }
            }
            if (!changed) throw new InvalidOperationException("Unable to apply an image for " + key);
        }
    }
    private void Transition(Wallpaper.Desktop desktop, MonitorInfo monitor, string output, Settings settings, int oldPosition, CancellationToken token)
    {
        try
        {
            if (settings.TransitionEffect != "CrossFade") return;
            string oldPath = desktop.GetWallpaper(monitor.Id);
            string? reason = settings.DisplayMode == "Tile" || oldPosition == 1 ? "Tile mode" :
                (long)monitor.Width * monitor.Height > 16000000 ? "Monitor exceeds 16 million pixels" :
                oldPosition < 0 || oldPosition >= Modes.Length ? "Unsupported previous mode" :
                !File.Exists(oldPath) ? "Previous wallpaper missing" : null;
            if (reason is not null) { log("Crossfade fallback: " + reason); return; }
            var old = Images.Canvas(Images.Load(oldPath), monitor.Width, monitor.Height, Modes[oldPosition], desktop.GetBackgroundColor());
            var next = Images.Canvas(Images.Load(output), monitor.Width, monitor.Height, settings.DisplayMode, desktop.GetBackgroundColor());
            bool animated = CrossfadeLayer.TryAnimate(old, next, desktop.GetMonitorRECT(monitor.Id),
                () => desktop.SetWallpaper(monitor.Id, output), token, out string diagnostic);
            log($"Crossfade {(animated ? "rendered" : "fallback")}: {diagnostic}; remote={SystemInformation.TerminalServerSession}");
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { log("Crossfade fallback: " + ex.Message); }
        finally
        {
            // Never leave the desktop referencing a temporary frame, including cancellation.
            desktop.SetWallpaper(monitor.Id, output);
        }
    }
    private void Restore()
    {
        var original = Storage.Read<OriginalWallpaper>(Path.Combine(Data, "original.json"));
        if (original is null) { log("No original wallpaper backup."); return; }
        using var desktop = Wallpaper.Desktop.Open(); desktop.SetPosition(original.Position);
        foreach (var m in original.Monitors)
            if (File.Exists(m.Path)) { try { desktop.SetWallpaper(m.Id, m.Path); } catch (Exception ex) { log(ex.Message); } }
        log("Stopped and restored available static wallpapers.");
    }
}

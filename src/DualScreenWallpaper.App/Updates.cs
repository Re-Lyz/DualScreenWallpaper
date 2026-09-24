using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using DualScreenWallpaper.Core;

namespace DualScreenWallpaper.App;

internal sealed record ReleaseInfo(string Version, string Name, string Url, long Size, string Sha256, string Notes, bool Installed);
internal sealed record UpdateRequest(string Root, ReleaseInfo Release);
internal sealed record UpdateBackup(string Root, string[] Files, string[] Added);

internal static class Updates
{
    public const string CurrentVersion = "2.0.0";
    private const string Repo = "https://github.com/Re-Lyz/DualScreenWallpaper";
    private static readonly string[] Hosts = ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"];
    public static bool IsInstalled(string root)
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1");
        return key?.GetValue("InstallLocation") is string path && Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)).Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)), StringComparison.OrdinalIgnoreCase);
    }
    public static async Task Download(string url, string path, long limit, CancellationToken token)
    {
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(90) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("DualScreenWallpaper/2.0");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromMinutes(5));
        for (int i = 0; i < 6; i++)
        {
            var uri = new Uri(url);
            if (uri.Scheme != "https" || !Hosts.Contains(uri.Host)) throw new InvalidDataException("Untrusted update host.");
            using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests)
                throw new HttpRequestException("GitHub temporarily refused the request (rate limit or access restriction). Retry later. No application files were changed.");
            if (response.StatusCode is HttpStatusCode.Moved or HttpStatusCode.Redirect or HttpStatusCode.SeeOther or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
            { url = new Uri(uri, response.Headers.Location ?? throw new InvalidDataException("Missing redirect location.")).AbsoluteUri; continue; }
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > limit) throw new InvalidDataException("Update too large.");
            await using var input = await response.Content.ReadAsStreamAsync(deadline.Token);
            await using var output = new FileStream(path, FileMode.CreateNew);
            byte[] buffer = new byte[65536]; long total = 0;
            for (int read; (read = await input.ReadAsync(buffer, deadline.Token)) > 0;)
            {
                total += read; if (total > limit) throw new InvalidDataException("Update exceeds size limit.");
                await output.WriteAsync(buffer.AsMemory(0, read), deadline.Token);
            }
            return;
        }
        throw new InvalidDataException("Too many update redirects.");
    }
    public static ReleaseInfo ParseRelease(string json, bool installed)
    {
        using var document = JsonDocument.Parse(json); var r = document.RootElement;
        string tag = r.GetProperty("tag_name").GetString() ?? "";
        if (r.GetProperty("draft").GetBoolean() || r.GetProperty("prerelease").GetBoolean() || !Regex.IsMatch(tag, @"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")) throw new InvalidDataException("Unsupported release.");
        string name = "DualScreenWallpaper-" + tag[1..] + (installed ? "-Setup.exe" : ".zip");
        var assets = r.GetProperty("assets").EnumerateArray().Where(x => x.GetProperty("name").GetString() == name).ToArray();
        if (assets.Length != 1) throw new InvalidDataException("Matching release asset missing.");
        var asset = assets[0]; string digest = asset.GetProperty("digest").GetString() ?? "";
        if (!digest.StartsWith("sha256:", StringComparison.Ordinal)) throw new InvalidDataException("Release has no SHA-256 digest.");
        var info = new ReleaseInfo(tag[1..], name, asset.GetProperty("browser_download_url").GetString() ?? "", asset.GetProperty("size").GetInt64(), digest[7..], r.GetProperty("body").GetString() ?? "", installed);
        Validate(info); return info;
    }
    private static void Validate(ReleaseInfo info)
    {
        if (!Regex.IsMatch(info.Version, @"^\d+\.\d+\.\d+$") || !Regex.IsMatch(info.Sha256, "^[a-fA-F0-9]{64}$") || info.Size is <= 0 or > 314572800) throw new InvalidDataException("Invalid update metadata.");
        string name = "DualScreenWallpaper-" + info.Version + (info.Installed ? "-Setup.exe" : ".zip");
        if (info.Name != name || info.Url != $"{Repo}/releases/download/v{info.Version}/{name}") throw new InvalidDataException("Unexpected update source.");
    }
    public static void Verify(ReleaseInfo info, string path)
    {
        Validate(info); using var input = File.OpenRead(path);
        if (input.Length != info.Size || !Convert.ToHexString(SHA256.HashData(input)).Equals(info.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Package size or SHA-256 mismatch.");
    }
    internal static bool ProgramFile(string name) => name is "VERSION" or "config.example.json" or "LICENSE.txt" or "ThirdPartyNotices.txt" ||
        Regex.IsMatch(name, @"^[A-Za-z0-9][A-Za-z0-9._-]*\.(exe|dll|pdb|deps\.json|runtimeconfig\.json|md|cmd)$", RegexOptions.IgnoreCase);
    internal static string[] Expand(string archive, string stage, string version)
    {
        if (Directory.Exists(stage)) throw new IOException("Staging directory already exists.");
        using var zip = ZipFile.OpenRead(archive);
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase); long total = 0;
        if (zip.Entries.Count > 1000) throw new InvalidDataException("Too many files.");
        foreach (var entry in zip.Entries)
        {
            if (!ProgramFile(entry.FullName) || !names.Add(entry.FullName)) throw new InvalidDataException("Unsafe package entry: " + entry.FullName);
            total += entry.Length; if (total > 500L * 1024 * 1024) throw new InvalidDataException("Unpacked update too large.");
        }
        foreach (string required in new[] { "VERSION", "DualScreenWallpaper.exe", "DualScreenWallpaper.dll", "DualScreenWallpaper.runtimeconfig.json" })
            if (!names.Contains(required)) throw new InvalidDataException("Incomplete package: " + required);
        using (var reader = new StreamReader(zip.GetEntry("VERSION")!.Open()))
            if (reader.ReadToEnd().Trim() != version) throw new InvalidDataException("Package version mismatch.");
        Directory.CreateDirectory(stage);
        foreach (var entry in zip.Entries) entry.ExtractToFile(Path.Combine(stage, entry.FullName));
        return names.ToArray();
    }
    private static void NoLink(string path)
    {
        for (string? p = Path.GetFullPath(path); p is not null; p = Path.GetDirectoryName(p))
            if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0) throw new IOException("Linked update paths are not supported.");
    }
    internal static void Backup(string root, string job, string[] next)
    {
        string[] names = Directory.GetFiles(root).Select(Path.GetFileName).Where(x => x is not null && ProgramFile(x) && !x.StartsWith("unins", StringComparison.OrdinalIgnoreCase)).Cast<string>()
            .Concat(new[] { "config.json", @"data\original.json", @"data\state.json" }.Where(x => File.Exists(Path.Combine(root, x)))).ToArray();
        string backup = Path.Combine(job, "backup"); if (Directory.Exists(backup)) throw new IOException("Backup already exists.");
        foreach (string name in names)
        {
            string source = Path.Combine(root, name); NoLink(source);
            string target = Path.Combine(backup, name); Directory.CreateDirectory(Path.GetDirectoryName(target)!); File.Copy(source, target);
        }
        Storage.Write(Path.Combine(job, "backup.json"), new UpdateBackup(root, names, next.Except(names, StringComparer.OrdinalIgnoreCase).ToArray()));
    }
    internal static void Restore(string job, string root)
    {
        var backup = Storage.Read<UpdateBackup>(Path.Combine(job, "backup.json")) ?? throw new InvalidDataException("Backup manifest missing.");
        if (!Path.GetFullPath(backup.Root).Equals(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Backup root mismatch.");
        foreach (string name in backup.Files)
        {
            if (!ProgramFile(name) && name is not "config.json" and not @"data\original.json" and not @"data\state.json") throw new InvalidDataException("Unsafe backup manifest.");
            NoLink(Path.Combine(root, name)); NoLink(Path.Combine(job, "backup", name));
            if (!File.Exists(Path.Combine(job, "backup", name))) throw new InvalidDataException("Incomplete backup.");
        }
        foreach (string name in backup.Added) { if (!ProgramFile(name)) throw new InvalidDataException("Unsafe added file."); NoLink(Path.Combine(root, name)); }
        foreach (string name in backup.Files)
        {
            string source = Path.Combine(job, "backup", name), target = Path.Combine(root, name);
            // Do not rewrite an unchanged file that may be read-only or loaded by Windows.
            if (File.Exists(target))
            {
                using var existing = File.OpenRead(target); using var saved = File.OpenRead(source);
                if (existing.Length == saved.Length && SHA256.HashData(existing).SequenceEqual(SHA256.HashData(saved))) continue;
            }
            File.Copy(source, target, true);
        }
        foreach (string name in backup.Added) File.Delete(Path.Combine(root, name));
    }
    internal static void InstallPortable(string root, string stage, string job, Action<string, string>? copy = null)
    {
        string[] names = Directory.GetFiles(stage).Select(Path.GetFileName).Cast<string>().ToArray();
        foreach (string name in names)
        {
            if (!ProgramFile(name)) throw new InvalidDataException("Unsafe staged file.");
            string target = Path.Combine(root, name); NoLink(target);
            if (Directory.Exists(target) || (File.Exists(target) && (File.GetAttributes(target) & FileAttributes.ReadOnly) != 0)) throw new IOException("Update target is a directory or read-only file.");
        }
        Backup(root, job, names);
        copy ??= (source, target) => File.Copy(source, target, true);
        try { foreach (string name in names) copy(Path.Combine(stage, name), Path.Combine(root, name)); }
        catch { Restore(job, root); throw; }
    }
    public static string PrepareRunner(string root, string job, ReleaseInfo info)
    {
        Verify(info, Path.Combine(job, info.Name));
        string runner = Path.Combine(job, "runner"); Directory.CreateDirectory(runner);
        foreach (string file in Directory.GetFiles(AppContext.BaseDirectory))
            if (ProgramFile(Path.GetFileName(file))) File.Copy(file, Path.Combine(runner, Path.GetFileName(file)));
        Storage.Write(Path.Combine(job, "request.json"), new UpdateRequest(root, info));
        File.WriteAllText(Path.Combine(job, "Restore.cmd"), "@echo off\r\n\"%~dp0runner\\DualScreenWallpaper.exe\" --update-job \"%~dp0.\" --restore\r\n");
        return Path.Combine(runner, "DualScreenWallpaper.exe");
    }
    public static void StartRunner(string runner, string job)
    {
        var start = new ProcessStartInfo(runner) { UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add("--update-job"); start.ArgumentList.Add(job); start.ArgumentList.Add("--parent"); start.ArgumentList.Add(Environment.ProcessId.ToString());
        Process.Start(start)?.Dispose();
    }
    public static void Apply(string job, int parent, bool restore, bool restart = true)
    {
        if (parent > 0) { try { using var process = Process.GetProcessById(parent); if (!process.WaitForExit(60000)) throw new IOException("Settings did not close."); } catch (ArgumentException) { } }
        var request = Storage.Read<UpdateRequest>(Path.Combine(job, "request.json")) ?? throw new InvalidDataException("Missing update request.");
        string root = Path.GetFullPath(request.Root);
        if (!ImageLibrary.IsWithin(job, Path.Combine(root, "data", "updates")) || !File.Exists(Path.Combine(root, "DualScreenWallpaper.exe"))) throw new InvalidDataException("Invalid update directory.");
        NoLink(root); NoLink(job);
        using var updater = new Mutex(true, "Local\\DualScreenWallpaperUpdate", out bool fresh);
        if (!fresh) throw new IOException("Another update is running.");
        try
        {
            if (Mutex.TryOpenExisting("Local\\DualScreenWallpaperSettings", out var settings)) { settings.Dispose(); throw new IOException("Close Settings first."); }
            if (restore) { using var guard = Maintenance(); Restore(job, root); }
            else
            {
                var info = request.Release;
                Verify(info, Path.Combine(job, info.Name));
                string current = File.ReadAllText(Path.Combine(root, "VERSION")).Trim();
                if (Version.Parse(info.Version) <= Version.Parse(current) || info.Installed != IsInstalled(root)) throw new InvalidDataException("Update is not newer or distribution type changed.");
                if (info.Installed)
                {
                    using (var guard = Maintenance()) Backup(root, job, []);
                    var start = new ProcessStartInfo(Path.Combine(job, info.Name)) { UseShellExecute = false, CreateNoWindow = true };
                    foreach (string arg in new[] { "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=" + root, "/LOG=" + Path.Combine(job, "installer.log") }) start.ArgumentList.Add(arg);
                    try
                    {
                        using var process = Process.Start(start)!; process.WaitForExit();
                        if (process.ExitCode != 0 || File.ReadAllText(Path.Combine(root, "VERSION")).Trim() != info.Version) throw new IOException("Installer update failed.");
                    }
                    catch { using var guard = Maintenance(); Restore(job, root); throw; }
                }
                else
                {
                    string stage = Path.Combine(job, "stage"); Expand(Path.Combine(job, info.Name), stage, info.Version);
                    using var guard = Maintenance();
                    InstallPortable(root, stage, job);
                }
            }
            Storage.Write(Path.Combine(job, "apply-result.json"), new { Success = true, Restored = restore });
        }
        catch (Exception ex) { Storage.Write(Path.Combine(job, "apply-result.json"), new { Success = false, Error = ex.Message }); throw; }
        finally { updater.ReleaseMutex(); }
        if (restart) Process.Start(new ProcessStartInfo(Path.Combine(root, "DualScreenWallpaper.exe")) { UseShellExecute = true, WorkingDirectory = root })?.Dispose();
    }
    private static IDisposable Maintenance() => new MaintenanceGuard();
    private sealed class MaintenanceGuard : IDisposable
    {
        private readonly Mutex maintenance;
        private readonly Mutex worker;
        public MaintenanceGuard()
        {
            maintenance = new Mutex(false, "Local\\DualScreenWallpaperMaintenance", out bool fresh);
            if (!fresh) { maintenance.Dispose(); throw new IOException("Another maintenance operation is active."); }
            worker = new Mutex(false, "Local\\DualScreenWallpaperWorker"); bool held;
            try { held = worker.WaitOne(30000); } catch (AbandonedMutexException) { held = true; }
            if (!held) { worker.Dispose(); maintenance.Dispose(); throw new IOException("Wallpaper worker is busy."); }
        }
        public void Dispose() { worker.ReleaseMutex(); worker.Dispose(); maintenance.Dispose(); }
    }
}

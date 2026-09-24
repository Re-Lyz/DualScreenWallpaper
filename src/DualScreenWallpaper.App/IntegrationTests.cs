using System.IO.Compression;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DualScreenWallpaper.Core;
using DualScreenWallpaper.Windows;

namespace DualScreenWallpaper.App;

internal static class IntegrationTests
{
    public static void Run(string report)
    {
        string temp = Path.Combine(Path.GetTempPath(), "dsw-csharp-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
        int assertions = 0;
        void Check(bool value, string message) { assertions++; if (!value) throw new InvalidOperationException(message); }
        void Reject(Action action) { bool rejected = false; try { action(); } catch (InvalidDataException) { rejected = true; } Check(rejected, "Unsafe package accepted."); }
        try
        {
            CrossfadeLayer.VerifyRenderer(); Check(true, "Desktop-layer renderer");
            BitmapSource Solid(byte r, byte b) => BitmapSource.Create(12, 8, 96, 96, PixelFormats.Bgra32, null,
                Enumerable.Range(0, 96).SelectMany(_ => new byte[] { b, 0, r, 255 }).ToArray(), 48);
            var red = Solid(255, 0); var blue = Solid(0, 255); var blended = Images.Blend(red, blue, .5);
            byte[] pixels = new byte[12 * 8 * 4]; blended.CopyPixels(pixels, 48, 0);
            Check(pixels[0] is >= 126 and <= 129 && pixels[2] is >= 126 and <= 129, "Crossfade pixel blend incorrect.");
            string image = Path.Combine(temp, "sample.jpg"); Images.Save(red, image);
            Check(Images.Dimensions(image) == new ImageSize(12, 8), "JPEG dimensions incorrect.");
            foreach (string mode in RuntimeService.Modes)
            { var frame = Images.Canvas(red, 60, 80, mode, 0); Check(frame.PixelWidth == 60 && frame.PixelHeight == 80, mode + " canvas dimensions"); }
            var metadata = new BitmapMetadata("jpg"); metadata.SetQuery("/app1/ifd/{ushort=274}", (ushort)6);
            var encoder = new JpegBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(red, null, metadata, null));
            string rotated = Path.Combine(temp, "rotated.jpg"); using (var stream = File.Create(rotated)) encoder.Save(stream);
            Check(Images.Load(rotated).PixelWidth == 8 && Images.Dimensions(rotated) == new ImageSize(8, 12), "EXIF orientation was not applied.");
            var profile = new ImageProfile([temp, image], [], false, "Landscape", false, 0, 0);
            var settings = SettingsReader.Defaults with { Primary = profile, Secondary = profile, MonitorProfiles = new() { ["screen3"] = profile with { Roots = [rotated] } } };
            var index = ImageLibrary.Scan(settings, Images.Dimensions, _ => { }, CancellationToken.None);
            Check(index.Pools["Primary"].Length == 2, "Mixed folders/files not deduplicated.");
            Check(index.Pools["screen3"].SequenceEqual([rotated]), "Independent monitor library incorrect.");
            Check(settings.ForMonitor("screen3", false).Roots.SequenceEqual([rotated]), "Monitor override lost.");
            Check(settings.ForMonitor("unknown", false) == profile, "Unknown monitor fallback incorrect.");
            string ownedXml = "<Task xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\"><Actions><Exec><Command>" + System.Security.SecurityElement.Escape(Path.Combine(temp, "DualScreenWallpaper.exe")) + "</Command></Exec></Actions></Task>";
            Check(ScheduledSlideshow.Owns(ownedXml, temp) && !ScheduledSlideshow.Owns(ownedXml, temp + "other"), "Scheduled task ownership boundary incorrect.");
            Check(ImageLibrary.Signature(settings with { TransitionEffect = "CrossFade", IntervalMinutes = 3 }) == index.Signature, "Playback-only edits invalidated the index.");
            Check(ImageLibrary.Candidates(["B.jpg", "A.jpg"], "A.jpg", "Sequential").SequenceEqual(["B.jpg", "A.jpg"]), "Sequential resume incorrect.");
            Check(ImageLibrary.Candidates(["A.jpg", "B.jpg"], "A.jpg", "Random")[0] == "B.jpg", "Random repeated previous image.");
            string excluded = Path.Combine(temp, "private"), sibling = excluded + "2";
            Directory.CreateDirectory(excluded); Directory.CreateDirectory(sibling);
            File.Copy(image, Path.Combine(excluded, "hidden.jpg")); File.Copy(image, Path.Combine(sibling, "visible.jpg"));
            var paths = ImageLibrary.Enumerate(profile with { ExcludeFolders = [excluded] }, _ => { }, CancellationToken.None).ToArray();
            Check(paths.Contains(Path.Combine(sibling, "visible.jpg")) && !paths.Contains(Path.Combine(excluded, "hidden.jpg")), "Exclusion boundary incorrect.");
            string config = Path.Combine(temp, "config.json"); File.WriteAllText(config, "original"); Storage.SaveSettings(config, settings);
            Check(File.ReadAllText(Directory.GetFiles(temp, "config.json.backup-*.json").Single()) == "original", "Configuration backup missing.");
            Check(SettingsReader.Load(config).MonitorProfiles.ContainsKey("screen3"), "Monitor profile persistence lost.");
            string zipPath = Path.Combine(temp, "update.zip");
            void Zip(string bad)
            {
                if (File.Exists(zipPath)) File.Delete(zipPath);
                using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);
                foreach (string name in new[] { "VERSION", "DualScreenWallpaper.exe", "DualScreenWallpaper.dll", "DualScreenWallpaper.runtimeconfig.json", bad }.Distinct())
                { using var writer = new StreamWriter(zip.CreateEntry(name).Open()); writer.Write(name == "VERSION" ? "2.1.0" : "test"); }
            }
            foreach (string bad in new[] { "../escape.dll", "data/state.json", "config.json", "C:/escape.exe", "folder/thing.dll" })
            { Zip(bad); Reject(() => Updates.Expand(zipPath, Path.Combine(temp, "stage"), "2.1.0")); }
            Zip("extra.dll"); string stage = Path.Combine(temp, "stage");
            string[] names = Updates.Expand(zipPath, stage, "2.1.0"); Check(names.Length == 5, "Valid update extraction failed.");
            string app = Path.Combine(temp, "app"), job = Path.Combine(temp, "job"); Directory.CreateDirectory(app); Directory.CreateDirectory(job);
            File.WriteAllText(Path.Combine(app, "VERSION"), "2.0.0"); File.WriteAllText(Path.Combine(app, "config.json"), "keep");
            Updates.Backup(app, job, names); File.WriteAllText(Path.Combine(app, "VERSION"), "broken"); File.WriteAllText(Path.Combine(app, "extra.dll"), "new");
            Updates.Restore(job, app);
            Check(File.ReadAllText(Path.Combine(app, "VERSION")) == "2.0.0" && !File.Exists(Path.Combine(app, "extra.dll")), "Update restore failed.");
            Check(File.ReadAllText(Path.Combine(app, "config.json")) == "keep", "Update changed personal configuration.");
            string rollbackJob = Path.Combine(temp, "rollback-job"); Directory.CreateDirectory(rollbackJob);
            int copied = 0; bool failed = false;
            try
            {
                Updates.InstallPortable(app, stage, rollbackJob, (source, target) =>
                { if (++copied == 2) throw new IOException("Injected write failure after the first copy."); File.Copy(source, target, true); });
            }
            catch (IOException) { failed = true; }
            Check(failed && File.ReadAllText(Path.Combine(app, "VERSION")) == "2.0.0" && !File.Exists(Path.Combine(app, "DualScreenWallpaper.exe")), "Partial update did not roll back.");
            string release = JsonSerializer.Serialize(new { tag_name = "v2.1.0", draft = false, prerelease = false, body = "notes", assets = new[] { new { name = "DualScreenWallpaper-2.1.0.zip", browser_download_url = "https://github.com/Re-Lyz/DualScreenWallpaper/releases/download/v2.1.0/DualScreenWallpaper-2.1.0.zip", size = 1, digest = "sha256:" + new string('0', 64) } } });
            Check(Updates.ParseRelease(release, false).Version == "2.1.0", "Release parsing failed.");
            Reject(() => Updates.ParseRelease(release.Replace("github.com", "evil.example"), false));
            Reject(() => Updates.Verify(Updates.ParseRelease(release, false), image));
            using var output = new FileStream(report, FileMode.CreateNew);
            JsonSerializer.Serialize(output, new { Success = true, Assertions = assertions, Description = "Images, EXIF, mixed sources, independent profiles, playback, backups and hostile update packages. No desktop/task mutation." });
        }
        finally { Directory.Delete(temp, true); }
    }
}

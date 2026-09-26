namespace DualScreenWallpaper.App;

internal sealed record SlideshowStatus(bool Exists, bool Owned, bool Enabled, bool Running,
    DateTime? LastRun = null, DateTime? NextRun = null, int LastResult = 0)
{
    public string Describe(bool requested, bool english)
    {
        string state = !Exists ? (english ? "No slideshow task" : "未创建轮播任务") :
            !Owned ? (english ? "Task belongs to another installation" : "任务属于其他安装目录") :
            !Enabled ? (english ? "Task disabled" : "任务已禁用") :
            Running ? (english ? "Slideshow running" : "正在换图") : (english ? "Slideshow enabled" : "自动轮播已开启");
        if (requested != (Exists && Owned && Enabled))
            state += english ? " · Saved setting and task differ; save and apply to reconcile" : " · 已保存开关与任务不一致，请保存并应用";
        if (Owned && Exists)
        {
            string last = LastRun?.ToString("MM-dd HH:mm:ss") ?? "—", next = NextRun?.ToString("MM-dd HH:mm:ss") ?? "—";
            string result = LastRun is null ? "—" : LastResult == 0 ? (english ? "Success" : "成功") : $"0x{LastResult:X8}";
            state += english ? $"\nLast: {last} ({result}) · Next: {next}" : $"\n上次：{last}（{result}） · 下次：{next}";
        }
        return state;
    }
}

internal static class SlideshowLifecycle
{
    // Save first: even if removing the task fails, a later upgrade must not re-enable it.
    internal static void Stop(string config, Func<bool> removeTask, Action restore)
    {
        if (File.Exists(config))
        {
            var settings = Core.SettingsReader.Load(config);
            if (settings.AutoStart) Core.Storage.SaveSettings(config, settings with { AutoStart = false });
        }
        if (!removeTask()) throw new IOException("The slideshow task belongs to another installation. Its task and wallpaper were left unchanged.");
        restore();
    }
}

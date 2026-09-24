using System.Runtime.InteropServices;
using System.Security;
using System.Security.Principal;
using System.Xml.Linq;

namespace DualScreenWallpaper.App;

internal static class ScheduledSlideshow
{
    internal const string Name = "DualScreenWallpaper-1Minute";
    private static dynamic Connect()
    {
        dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service")!)!;
        service.Connect(); return service;
    }
    public static bool RemoveOwned(string root, Action<string> log)
    {
        dynamic service = Connect(); dynamic folder = service.GetFolder("\\");
        try
        {
            dynamic task;
            try { task = folder.GetTask(Name); }
            catch (Exception ex) when ((ex is COMException or FileNotFoundException) && (uint)ex.HResult == 0x80070002) { return true; }
            try
            {
                string xml = task.Xml;
                if (!Owns(xml, root)) { log("Another installation owns the task; left unchanged."); return false; }
                task.Stop(0); folder.DeleteTask(Name, 0); return true;
            }
            finally { Marshal.FinalReleaseComObject(task); }
        }
        finally { Marshal.FinalReleaseComObject(folder); Marshal.FinalReleaseComObject(service); }
    }
    internal static bool Owns(string xml, string root)
    {
        XNamespace ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";
        var actions = XDocument.Parse(xml).Root?.Element(ns + "Actions")?.Elements(ns + "Exec") ?? [];
        string exe = Path.Combine(Path.GetFullPath(root), "DualScreenWallpaper.exe");
        string script = "\"" + Path.Combine(Path.GetFullPath(root), "Run-Wallpaper.vbs") + "\"";
        return actions.Any(action => string.Equals((string?)action.Element(ns + "Command"), exe, StringComparison.OrdinalIgnoreCase) ||
            (((string?)action.Element(ns + "Arguments"))?.Contains(script, StringComparison.OrdinalIgnoreCase) == true &&
             Path.GetFileName((string?)action.Element(ns + "Command") ?? "").Equals("wscript.exe", StringComparison.OrdinalIgnoreCase)));
    }
    public static void Register(string root, int minutes)
    {
        string exe = Path.Combine(root, "DualScreenWallpaper.exe");
        if (!File.Exists(exe)) throw new FileNotFoundException("Publish the application before enabling slideshow.", exe);
        string user = SecurityElement.Escape(WindowsIdentity.GetCurrent().Name)!;
        string xml = $"""
        <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
          <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>{user}</UserId></LogonTrigger>
          <TimeTrigger><Repetition><Interval>PT{minutes}M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>{DateTime.Now.AddMinutes(1):yyyy-MM-ddTHH:mm:ss}</StartBoundary><Enabled>true</Enabled></TimeTrigger></Triggers>
          <Principals><Principal id="Author"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
          <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><ExecutionTimeLimit>PT3M</ExecutionTimeLimit><Enabled>true</Enabled></Settings>
          <Actions Context="Author"><Exec><Command>{SecurityElement.Escape(exe)}</Command><Arguments>--run --root &quot;{SecurityElement.Escape(root)}&quot;</Arguments><WorkingDirectory>{SecurityElement.Escape(root)}</WorkingDirectory></Exec></Actions>
        </Task>
        """;
        dynamic service = Connect(); dynamic folder = service.GetFolder("\\");
        try { dynamic task = folder.RegisterTask(Name, xml, 6, null, null, 3); Marshal.FinalReleaseComObject(task); }
        finally { Marshal.FinalReleaseComObject(folder); Marshal.FinalReleaseComObject(service); }
    }
}

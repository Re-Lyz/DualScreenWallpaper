# Architecture

The C# / .NET 10 application lives under `src/`. The old PowerShell/VBScript application has been removed from the current tree and remains available in Git history. Build and test scripts still use PowerShell.

| Project | Responsibility |
| --- | --- |
| `DualScreenWallpaper.Core` | Typed settings, Schema 3 migration, atomic storage, source scanning, filters and playback ordering |
| `DualScreenWallpaper.Windows` | Desktop COM interface, image headers, WPF decoding, EXIF orientation and rendering |
| `DualScreenWallpaper.App` | WinForms settings, previews, setup, wallpaper worker, native Task Scheduler integration, updates and recovery |
| `DualScreenWallpaper.Tests` | Configuration regression tests without an external test framework |

The Windows project owns its copies of `Desktop.cs` and `ImageHeader.cs`. The old copies remain in Git history. Core has no UI or COM dependency. Monitor settings use device IDs with Primary/Secondary defaults. UI operations dispatch WPF/COM work to STA threads. Task Scheduler invokes the compiled executable; no permanent slideshow process is required.

`src/Build.ps1` uses `src/VERSION`, the root example configuration and `src/README.md`. `Directory.Build.props` supplies assembly versions; the updater reads the assembly version, and the build passes it to Inno Setup. Each build uses a fresh staging directory and rejects existing output before publishing. It writes packages and SHA-256 files to `dist/` or a specified output directory. Development tools, reports and backups stay in ignored `data/`.

Explicit stop persists AutoStart=false with a backup before removing the owned task and restoring wallpaper. Uninstall remains independent of configuration parsing. UI task status is refreshed read-only every 15 seconds, including configuration/task mismatches. Task creation refuses to overwrite another installation's task. Lifecycle regression uses injected task/removal callbacks; it does not touch the user's desktop or scheduled task.

The updater verifies release source, size and SHA-256, rejects unsafe ZIP entries, backs up files and coordinates changes with maintenance/worker locks. Installed upgrades preserve configuration and data. Portable update failures restore previous files. Schema 2 settings migrate on save; the old image index is not yet converted to `index-v3.json`.

Crossfade uses a temporary Explorer background child window. This depends on an undocumented window structure and can fall back to direct switching. The user confirmed visible crossfade on their actual setup on 2026-10-06. RDP and broader hardware coverage remain unverified.

See [validation details and limits](src/README.md) and the [remaining work](TODO.md). Version 2.0.1 is the first published C# release.

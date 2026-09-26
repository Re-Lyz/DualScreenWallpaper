# Architecture

The current application lives under `src/`. The PowerShell/VBScript 1.4.0 application is archived under `legacy/v1.4.0/`, including its packaging scripts and historical documentation. New builds do not depend on archived source files.

| Project | Responsibility |
| --- | --- |
| `DualScreenWallpaper.Core` | Typed settings, Schema 3 migration, atomic storage, source scanning, filters and playback ordering |
| `DualScreenWallpaper.Windows` | Desktop COM interface, image headers, WPF decoding, EXIF orientation and rendering |
| `DualScreenWallpaper.App` | WinForms settings, previews, setup, wallpaper worker, native Task Scheduler integration, updates and recovery |
| `DualScreenWallpaper.Tests` | Configuration regression tests without an external test framework |

The Windows project owns its copies of `Desktop.cs` and `ImageHeader.cs`; archived copies remain with the old application for maintenance. Core has no UI or COM dependency. Monitor settings use device IDs with Primary/Secondary defaults. UI operations dispatch WPF/COM work to STA threads. Task Scheduler invokes the compiled executable; no permanent slideshow process is required.

`src/Build.ps1` uses `src/VERSION`, the root example configuration and `src/README.md`. It writes to `dist/`, validates package entries and optionally invokes `src/Installer.iss`. Development tools, reports and backups stay in ignored `data/`. The old build scripts use paths relative to the archive and accept an explicit compiler path where needed.

The updater verifies release source, size and SHA-256, rejects unsafe ZIP entries, backs up files and coordinates changes with maintenance/worker locks. Installed upgrades preserve configuration and data. Portable update failures restore previous files. Schema 2 settings migrate on save; the old image index is not yet converted to `index-v3.json`.

Crossfade uses a temporary Explorer background child window. This depends on an undocumented window structure and can fall back to direct switching. Offline rendering tests do not establish visible desktop behavior; real-desktop acceptance remains pending at the user's request.

See [validation details and limits](src/README.md) and the [remaining work](TODO.md). The local installation has been upgraded to 2.0; no 2.0 GitHub Release has been published.

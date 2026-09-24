# Architecture and refactoring decision

The released application remains a Windows PowerShell 5.1 / WinForms utility using IDesktopWallpaper and Task Scheduler. Version 1.4.0 uses focused extraction rather than a full rewrite. The C# / .NET 10 candidate is implemented under src/; see src/README.md for build instructions, validation and remaining acceptance. C# was selected for reuse of the Windows/.NET implementation. Warm UI startup, working set and deployment size were measured; no Rust comparison or cold-start benchmark is claimed.

This release separates the responsibilities that were growing together:

| File | Responsibility |
| --- | --- |
| `Settings.ps1` | Main window, localization events and background-worker orchestration |
| `Settings.Controls.ps1` | Shared folder/filter controls used by Settings and the wizard |
| `Settings.Persistence.ps1` | Form-to-config mapping, staged import/export and saving |
| `SetupWizard.ps1` | First-run prerequisites, monitor confirmation and guided setup |
| `Config.ps1` | Configuration migration/validation, filtering and playback ordering |
| `ImageProcessing.ps1` | Monitor geometry, image decoding, EXIF orientation and conversion |
| `Preview.ps1` | Read-only layout and rendering preview |
| `Rendering.ps1` / `Transition.ps1` | Shared image placement and bounded intermediate crossfade frames |
| `UpdateCore.ps1` | Release validation, restricted downloads, safe extraction and backup/restore |
| `UpdateUI.ps1` / `UpdateWorker.ps1` | Manual update dialog and separate network worker |
| `UpdateApply.ps1` | Detached application of verified updates after Settings exits |
| `Wallpaper.ps1` | Indexing, applying wallpapers and registering the slideshow |
| `Lifecycle.ps1` / `Uninstall.ps1` | Task ownership, maintenance coordination and uninstall cleanup |
| `Package.ps1` | Single explicit release-file allowlist |
| `Release.ps1` / `Build-Installer.ps1` / `Installer.iss` | ZIP and per-user Windows installer builds |
| `Test-*.ps1` | Isolated regression, UI, feature and setup checks |

The released 1.4 UI helper files are dot-sourced and share form state. The local C# 2.0 candidate under [src/](src/README.md) now implements the application in compiled C#: typed Schema 3 configuration and atomic storage, mixed image sources, independent monitor profiles, Windows decoding/rendering, resizable WinForms UI, task scheduling and detached update transactions. It reuses the existing C# COM ABI and image-header reader. Production 1.4 files and package allowlist remain available for maintenance; the new build has its own VERSION, installer and publish outputs. The installed user copy has not been replaced.

## C# candidate boundaries

- Core contains no UI/COM dependencies. Image decoding is injected into scanning tests; source enumeration and filtering apply identically to folders and explicit files.
- Monitor profiles use stable Windows device IDs, with Primary/Secondary defaults for unconfigured screens. Disconnected profiles persist. Schema 2 and legacy input migrate in memory; save writes Schema 3 with a backup.
- Background operations run on separate STA threads for WPF/COM compatibility. Task Scheduler invokes the compiled EXE, not PowerShell/VBScript. No permanent slideshow process is required.
- Crossfade now uses a short-lived child of Explorer's background WorkerW rather than repeatedly replacing wallpaper files. Host detection can fail and is not a documented extension contract; failures are logged and direct switching remains available. Only offline rendering has been validated for this implementation. Real-desktop acceptance is deferred at the user's request.
- The updater restricts HTTPS hosts and validates GitHub asset names, sizes and SHA-256. Portable ZIPs contain root-level program files only. A separate copied runner waits for Settings to exit, backs up files and applies or restores them under maintenance/worker locks. Installed updates use Inno Setup; file recovery does not rewrite uninstall registration.
- Independent packages include .NET 10; smaller framework-dependent packages require the shared Desktop Runtime. Runtime-included size is explicitly reported, rather than comparing only the managed EXE with the old installer.

## Update and transition boundaries

Updates are user initiated. Network work runs outside the UI process; release source, asset name, size and SHA-256 must match before applying. ZIP entries are root-only allowlisted program files, excluding personal settings and data. The detached runner lives under `data/updates`, waits for Settings to exit, and coordinates with wallpaper workers and installer maintenance. Portable updates back up program/configuration files before copying and restore on failure. Installed updates use the installer, then verify VERSION; file recovery does not replace the installer's registry/uninstall rollback. A retained Restore.cmd provides manual file/configuration recovery.

Crossfade renders eight intermediate frames through IDesktopWallpaper, then commits the normal final wallpaper. Two intermediate cache files are reused per monitor. Tile, missing old images and screens above 16 million pixels fall back to direct switching. There is no permanent animation process; timing depends on Windows wallpaper application latency.

## Installation invariants

- Install per user into a writable directory. Upgrade in place; keep `config.json` and `data/` unchanged.
- Stage only allowlisted files. Never include personal paths, caches or downloaded build tools.
- Installer maintenance prevents new workers/settings windows from starting; existing operations must close before changing program files.
- Uninstall removes only the scheduled task pointing to this installation's `Run-Wallpaper.vbs`. A different installation's task is left alone.
- Uninstall attempts wallpaper restoration, but keeps configuration, backups and caches. It never recursively deletes the installation directory.
- Uninstall cleanup does not parse `config.json`, so damaged settings do not strand the scheduled task.
- Setup wizard edits are staged until Finish and apply; cancel does not save settings or change wallpapers/tasks. Existing configured installations do not automatically repeat the wizard.

## Validation

Run `Test-Settings.ps1`, `Test-Features.ps1`, `Settings.ps1 -SmokeTest`, `Test-Setup.ps1` and `Test-Updates.ps1` with Windows PowerShell. These use isolated files and mocked task/wallpaper mutation boundaries. `Test-Updates.ps1 -LiveCheck` additionally queries GitHub and verifies a real release download. Update tests cover hostile ZIP paths, invalid hashes, portable application, injected copy failure, rollback, manual restore and blend pixels. Installer integration testing additionally covers actual extraction, repeat installation, installed update application and removal in a disposable installation directory; it must not point at the user's working installation.

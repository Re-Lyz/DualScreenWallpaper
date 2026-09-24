# Architecture and refactoring decision

The application remains a Windows PowerShell 5.1 / WinForms utility using IDesktopWallpaper and Task Scheduler. A full rewrite is not justified by the current feature set: it would replace working OS integration, configuration migration and image handling without a demonstrated user benefit.

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

The UI helper files are dot-sourced, not independent modules: they deliberately share the active form's controls and language. This is an incremental boundary, not a dependency-injection framework. Extract a typed application service or move to compiled C# only if future work (tray process, continuous animation, many independent monitor profiles) makes long-lived state and UI concurrency significantly more complex.

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

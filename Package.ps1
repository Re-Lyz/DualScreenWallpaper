# One explicit allowlist for ZIP releases and installers; no personal data or build tools.
function Get-PackageFiles {
    @('00-settings.cmd','01-install.cmd','02-refresh-index.cmd','03-change-now.cmd','04-stop-and-restore.cmd','05-show-monitors.cmd',
      'Config.ps1','ImageProcessing.ps1','Preview.ps1','Language.ps1','Lifecycle.ps1','Uninstall.ps1',
      'Desktop.cs','ImageHeader.cs','Initialize-Config.ps1','Launch-Settings.ps1','Open-Settings.vbs','Run-Wallpaper.vbs',
      'Settings.ps1','Settings.Controls.ps1','Settings.Persistence.ps1','SetupWizard.ps1','Wallpaper.ps1',
      'config.example.json','README.md','README.en.md','TODO.md','CHANGELOG.md','ARCHITECTURE.md','VERSION',
      'Release.ps1','Package.ps1','Build-Installer.ps1','Installer.iss',
      'Test-Settings.ps1','Test-SettingsUI.ps1','Test-Features.ps1','Test-Setup.ps1','Test-Installer.ps1')
}

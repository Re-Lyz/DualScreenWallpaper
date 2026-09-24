#ifndef StageDir
  #error StageDir is required
#endif
#ifndef AppGuid
  #define AppGuid "{609C20B9-0177-4C33-92AB-D5E11347ED72}"
#endif
#ifndef OutputName
  #define OutputName "DualScreenWallpaper-2.0.0-Setup"
#endif
[Setup]
AppId={{#AppGuid}
AppName=DualScreenWallpaper
AppVersion=2.0.0
AppPublisher=DualScreenWallpaper
DefaultDirName={localappdata}\Programs\DualScreenWallpaper
DefaultGroupName=DualScreenWallpaper
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename={#OutputName}
OutputDir={#OutputDir}
AppMutex=Local\DualScreenWallpaperSettings,Local\DualScreenWallpaperWorker
SetupMutex=Local\DualScreenWallpaperInstaller
CloseApplications=no
RestartApplications=no
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\Settings"; Filename: "{app}\DualScreenWallpaper.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"
Name: "{autodesktop}\DualScreenWallpaper"; Filename: "{app}\DualScreenWallpaper.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\DualScreenWallpaper.exe"; Description: "Open settings"; Flags: nowait postinstall skipifsilent
[Code]
var
  MaintenanceHandle: LongWord;
  ExistingPage: TOutputMsgWizardPage;
function CreateMutexHandle(Attributes: LongWord; InitialOwner: Boolean; Name: String): LongWord;
  external 'CreateMutexW@kernel32.dll stdcall';
function CloseHandle(Handle: LongWord): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function LastError: LongWord;
  external 'GetLastError@kernel32.dll stdcall';
procedure LeaveMaintenance;
begin
  if MaintenanceHandle <> 0 then begin CloseHandle(MaintenanceHandle); MaintenanceHandle := 0; end;
end;
function EnterMaintenance: Boolean;
begin
  Result := False;
  if MaintenanceHandle = 0 then begin
    MaintenanceHandle := CreateMutexHandle(0, False, 'Local\DualScreenWallpaperMaintenance');
    if MaintenanceHandle = 0 then exit;
    if LastError = 183 then begin LeaveMaintenance; exit; end;
  end;
  Result := not CheckForMutexes('Local\DualScreenWallpaperSettings,Local\DualScreenWallpaperWorker');
end;
function PreviousVersion: String;
var Value: AnsiString;
begin
  Result := '';
  if LoadStringFromFile(ExpandConstant('{app}\VERSION'), Value) then Result := Trim(String(Value));
  if Result = '' then RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppGuid}_is1', 'DisplayVersion', Result);
end;
function Summary: String;
begin
  Result := 'Target version: 2.0.0' + #13#10 + 'Existing version: ' + PreviousVersion + #13#10 + ExpandConstant('{app}') + #13#10#13#10 + 'Saved configuration and data are preserved. C# replaces the PowerShell/VBScript runtime. Existing slideshow tasks are migrated to the executable.';
end;
procedure InitializeWizard;
begin
  ExistingPage := CreateOutputMsgPage(wpSelectDir, 'Existing installation', 'Review the upgrade', '');
end;
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ExistingPage.ID) and (PreviousVersion = '');
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = ExistingPage.ID then ExistingPage.MsgLabel.Caption := Summary;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var Old, New: Int64; PreviousPath: String;
begin
  Result := '';
  if StrToVersion(PreviousVersion + '.0', Old) and StrToVersion('2.0.0.0', New) then
    if ComparePackedVersion(Old, New) > 0 then begin Result := 'A newer version is already installed. Downgrade is blocked.'; exit; end;
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppGuid}_is1', 'InstallLocation', PreviousPath) then
    if CompareText(RemoveBackslashUnlessRoot(PreviousPath), RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) <> 0 then begin Result := 'Upgrade in the existing installation folder.'; exit; end;
  if not EnterMaintenance then Result := 'Close Settings and wait for wallpaper operations to finish.';
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssPostInstall then begin
    LeaveMaintenance;
    if FileExists(ExpandConstant('{app}\config.json')) then begin
      if not Exec(ExpandConstant('{app}\DualScreenWallpaper.exe'), '--migrate-task', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) then Code := -1;
      if Code <> 0 then SuppressibleMsgBox('Program files installed, but slideshow task migration failed. Open Settings and Save and apply. See data\worker.log.', mbError, MB_OK, IDOK);
    end;
  end;
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    if not EnterMaintenance then begin SuppressibleMsgBox('Close Settings and wait for wallpaper operations.', mbError, MB_OK, IDOK); Abort; end;
    if not Exec(ExpandConstant('{app}\DualScreenWallpaper.exe'), '--uninstall', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) then Code := -1;
    if Code <> 0 then begin SuppressibleMsgBox('Could not safely stop the slideshow. Files have been retained.', mbError, MB_OK, IDOK); Abort; end;
  end;
end;
procedure DeinitializeSetup;
begin LeaveMaintenance; end;
procedure DeinitializeUninstall;
begin LeaveMaintenance; end;

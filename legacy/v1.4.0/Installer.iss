#ifndef StageDir
  #error StageDir is required; use Build-Installer.ps1
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
[Setup]
AppId={{609C20B9-0177-4C33-92AB-D5E11347ED72}
AppName=DualScreenWallpaper
AppVersion={#AppVersion}
AppPublisher=DualScreenWallpaper
DefaultDirName={localappdata}\Programs\DualScreenWallpaper
DefaultGroupName=DualScreenWallpaper
DisableProgramGroupPage=auto
DisableDirPage=no
PrivilegesRequired=lowest
MinVersion=10.0.22000
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename=DualScreenWallpaper-{#AppVersion}-Setup
OutputDir={#OutputDir}
UninstallDisplayName=DualScreenWallpaper
AppMutex=Local\DualScreenWallpaperSettings,Local\DualScreenWallpaperWorker
SetupMutex=Local\DualScreenWallpaperInstaller
CloseApplications=no
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
; StageDir is populated only from Package.ps1. config.json and data/ are never staged.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Settings"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Open-Settings.vbs"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 167
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"
Name: "{autodesktop}\DualScreenWallpaper"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Open-Settings.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{sys}\shell32.dll"; IconIndex: 167

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\Open-Settings.vbs"""; Description: "Open settings / first-run setup"; Flags: nowait postinstall skipifsilent

[Code]
var
  MaintenanceHandle: LongWord;
  ExistingInstallPage: TOutputMsgWizardPage;

function InstalledVersionText: String;
var
  VersionFile: AnsiString;
  RegisteredPath: String;
  Parsed: Int64;
begin
  Result := '';
  if LoadStringFromFile(ExpandConstant('{app}\VERSION'), VersionFile) then
    if StrToVersion(Trim(String(VersionFile)) + '.0', Parsed) then begin
      Result := Trim(String(VersionFile));
      exit;
    end;
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1', 'InstallLocation', RegisteredPath) then
    if CompareText(RemoveBackslashUnlessRoot(RegisteredPath), RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) = 0 then
      RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1', 'DisplayVersion', Result);
end;

function HasExistingInstall: Boolean;
begin
  Result := (InstalledVersionText <> '') or FileExists(ExpandConstant('{app}\Settings.ps1'));
end;

function IsNewerInstalled: Boolean;
var
  ExistingVersion, NewVersion: Int64;
begin
  Result := False;
  if StrToVersion(InstalledVersionText + '.0', ExistingVersion) and StrToVersion('{#AppVersion}.0', NewVersion) then
    Result := ComparePackedVersion(ExistingVersion, NewVersion) > 0;
end;

function InstallationSummary: String;
var
  VersionText, ActionText: String;
begin
  VersionText := InstalledVersionText;
  if not HasExistingInstall then begin
    Result := 'New installation: {#AppVersion}';
    exit;
  end;
  if VersionText = '' then VersionText := 'Unknown';
  if IsNewerInstalled then ActionText := 'Blocked: a newer version is already installed. Downgrades are not supported.'
  else if VersionText = '{#AppVersion}' then ActionText := 'Reinstall this version to replace program files.'
  else if VersionText = 'Unknown' then ActionText := 'Replace existing program files. The installed version could not be determined.'
  else ActionText := 'Upgrade the existing installation.';
  Result := 'Existing version: ' + VersionText + #13#10 +
    'Installer version: {#AppVersion}' + #13#10 +
    'Installation folder: ' + ExpandConstant('{app}') + #13#10#13#10 + ActionText + #13#10#13#10 +
    'Your config.json and data folder will be preserved. You do not need to uninstall first.';
end;

procedure InitializeWizard;
begin
  ExistingInstallPage := CreateOutputMsgPage(wpSelectDir, 'Existing installation detected',
    'Review the installed version before continuing.', '');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ExistingInstallPage.ID) and not HasExistingInstall;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = ExistingInstallPage.ID then
    ExistingInstallPage.MsgLabel.Caption := InstallationSummary;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = ExistingInstallPage.ID) and IsNewerInstalled then begin
    Log(InstallationSummary);
    SuppressibleMsgBox(InstallationSummary, mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := InstallationSummary + NewLine + NewLine + MemoDirInfo + NewLine + MemoGroupInfo;
  if MemoTasksInfo <> '' then Result := Result + NewLine + MemoTasksInfo;
end;

function CreateMutexHandle(Attributes: LongWord; InitialOwner: Boolean; Name: String): LongWord;
  external 'CreateMutexW@kernel32.dll stdcall';
function CloseHandle(Handle: LongWord): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function LastError: LongWord;
  external 'GetLastError@kernel32.dll stdcall';

procedure LeaveMaintenance;
begin
  if MaintenanceHandle <> 0 then begin
    CloseHandle(MaintenanceHandle);
    MaintenanceHandle := 0;
  end;
end;

function EnterMaintenance: Boolean;
begin
  Result := False;
  if MaintenanceHandle = 0 then begin
    MaintenanceHandle := CreateMutexHandle(0, False, 'Local\DualScreenWallpaperMaintenance');
    if (MaintenanceHandle = 0) then exit;
    if LastError = 183 then begin
      LeaveMaintenance;
      exit;
    end;
  end;
  Result := not CheckForMutexes('Local\DualScreenWallpaperSettings,Local\DualScreenWallpaperWorker');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then LeaveMaintenance;
end;

procedure DeinitializeSetup;
begin
  LeaveMaintenance;
end;

procedure DeinitializeUninstall;
begin
  LeaveMaintenance;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  PreviousPath: String;
  HostEnabled: Cardinal;
begin
  Result := '';
  Log(InstallationSummary);
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{609C20B9-0177-4C33-92AB-D5E11347ED72}_is1', 'InstallLocation', PreviousPath) then begin
    if (PreviousPath <> '') and (CompareText(RemoveBackslashUnlessRoot(PreviousPath), RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) <> 0) then begin
      Result := 'Upgrade in the existing installation folder to preserve settings. Uninstall first if you need to move the application.';
      exit;
    end;
  end;
  if not FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) or
     not FileExists(ExpandConstant('{sys}\wscript.exe')) then begin
    Result := 'Windows PowerShell and Windows Script Host are required.';
    exit;
  end;
  if (RegQueryDWordValue(HKCU, 'Software\Microsoft\Windows Script Host\Settings', 'Enabled', HostEnabled) and (HostEnabled = 0)) or
     (RegQueryDWordValue(HKLM, 'Software\Microsoft\Windows Script Host\Settings', 'Enabled', HostEnabled) and (HostEnabled = 0)) then begin
    Result := 'Windows Script Host is disabled. Enable it before installing this application.';
    exit;
  end;
  if not RegKeyExists(HKCR, 'VBScript\CLSID') then begin
    Result := 'The Windows VBScript feature is required. Enable it before installing this application.';
    exit;
  end;
  if IsNewerInstalled then begin
    Result := InstallationSummary;
    exit;
  end;
  if not EnterMaintenance then
    Result := 'Close DualScreenWallpaper Settings and wait for wallpaper operations to finish, then retry.';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    if not EnterMaintenance then begin
      MsgBox('Close Settings and wait for wallpaper operations to finish, then retry uninstalling.', mbError, MB_OK);
      Abort;
    end;
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Uninstall.ps1') + '"',
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then ResultCode := -1;
    if ResultCode <> 0 then begin
      MsgBox('Could not stop the slideshow safely. Program files have been kept. See data\uninstall-error.log and retry.', mbError, MB_OK);
      Abort;
    end;
  end;
end;
// User-created config.json and data/ are retained by uninstall. No recursive delete rules.

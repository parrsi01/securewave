; SecureWave - Windows Installer (Inno Setup 6)
;
; Build on Windows:
;   1) flutter build windows --release (from securewave_app/)
;   2) Download WireGuard MSI to windows_installer\deps\wireguard-amd64.msi
;   3) ISCC.exe /DMyAppVersion=4.0.0 /DMyAppVersionInfo=4.0.0.1 securewave_installer.iss
;
; Output:
;   artifacts\windows_release\securewave-windows-x64-setup.exe

#include "version.iss"

#define MyAppName "SecureWave"
#define MyAppPublisher "SecureWave"
#define MyAppExeName "securewave_app.exe"
#define MyAppId "{{D02D8289-0695-485D-BAA1-141C257B048B}"
#define WireGuardMsiName "wireguard-amd64.msi"
#define TunnelName "SecureWave"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersionInfo}
VersionInfoProductVersion={#MyAppVersionInfo}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputBaseFilename=securewave-windows-x64-setup
OutputDir=..\artifacts\windows_release
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\securewave_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Flutter Windows release bundle (built output).
Source: "..\securewave_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; WireGuard for Windows (MSI) bundled as a prerequisite.
; The build script downloads it to windows_installer\deps\wireguard-amd64.msi.
Source: "deps\{#WireGuardMsiName}"; Flags: dontcopy

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Optional: launch after install when not running silently.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove SecureWave's per-user config directory (contains WireGuard config).
Type: filesandordirs; Name: "{userappdata}\{#MyAppName}"

[UninstallRun]
; Best-effort cleanup of the WireGuard tunnel service on uninstall.
Filename: "{code:GetWireGuardExe}"; Parameters: "/uninstalltunnelservice {#TunnelName}"; Flags: runhidden waituntilterminated; Check: WireGuardAvailable

[Code]
const
  SC_MANAGER_CONNECT = $0001;
  SERVICE_QUERY_STATUS = $0004;

type
  SC_HANDLE = LongWord;

function OpenSCManager(lpMachineName, lpDatabaseName: string; dwDesiredAccess: Cardinal): SC_HANDLE;
  external 'OpenSCManagerW@advapi32.dll stdcall';
function OpenService(hSCManager: SC_HANDLE; lpServiceName: string; dwDesiredAccess: Cardinal): SC_HANDLE;
  external 'OpenServiceW@advapi32.dll stdcall';
function CloseServiceHandle(hSCObject: SC_HANDLE): Boolean;
  external 'CloseServiceHandle@advapi32.dll stdcall';

function ServiceExists(const ServiceName: string): Boolean;
var
  scm: SC_HANDLE;
  svc: SC_HANDLE;
begin
  Result := False;
  scm := OpenSCManager('', '', SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  svc := OpenService(scm, ServiceName, SERVICE_QUERY_STATUS);
  if svc <> 0 then begin
    CloseServiceHandle(svc);
    Result := True;
  end;
  CloseServiceHandle(scm);
end;

function WireGuardExePath(): string;
begin
  Result := ExpandConstant('{pf}\WireGuard\wireguard.exe');
  if FileExists(Result) then
    Exit;
  Result := ExpandConstant('{pf32}\WireGuard\wireguard.exe');
  if FileExists(Result) then
    Exit;
  Result := '';
end;

function GetWireGuardExe(Param: string): string;
begin
  Result := WireGuardExePath();
end;

function WireGuardAvailable(): Boolean;
begin
  Result := WireGuardExePath() <> '';
end;

function InstallWireGuard(var NeedsRestart: Boolean): Boolean;
var
  ResultCode: Integer;
  MsiPath: string;
begin
  Result := False;
  NeedsRestart := False;

  try
    ExtractTemporaryFile('{#WireGuardMsiName}');
    MsiPath := ExpandConstant('{tmp}\{#WireGuardMsiName}');

    if not FileExists(MsiPath) then begin
      Log('WireGuard MSI missing at: ' + MsiPath);
      Exit;
    end;

    Log('Installing WireGuard MSI: ' + MsiPath);
    if not Exec('msiexec.exe',
      '/i "' + MsiPath + '" /quiet /norestart DO_NOT_LAUNCH=1',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      Log('Failed to execute msiexec.exe');
      Exit;
    end;

    Log('WireGuard MSI exit code: ' + IntToStr(ResultCode));
    if ResultCode = 0 then begin
      Result := True;
      Exit;
    end;
    if ResultCode = 3010 then begin
      NeedsRestart := True;
      Result := True;
      Exit;
    end;
    if ResultCode = 1641 then begin
      NeedsRestart := True;
      Result := True;
      Exit;
    end;
  except
    Log('Exception while installing WireGuard MSI.');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): string;
var
  NeedReboot: Boolean;
begin
  Result := '';

  if not WireGuardAvailable() then begin
    WizardForm.StatusLabel.Caption := 'Installing WireGuard for Windows...';

    if not InstallWireGuard(NeedReboot) then begin
      Result :=
        'WireGuard for Windows could not be installed.' + #13#10 +
        '{#MyAppName} requires WireGuard to create the VPN tunnel.' + #13#10 +
        'Please install WireGuard manually and run this installer again.';
      Exit;
    end;

    NeedsRestart := NeedsRestart or NeedReboot;

    if not WireGuardAvailable() then begin
      Result :=
        'WireGuard was not detected after installation.' + #13#10 +
        'Please install WireGuard manually and run this installer again.';
      Exit;
    end;
  end;

  // Defensive: validate that the WireGuard manager service exists.
  // If this check fails on a future WireGuard build, remove or relax it.
  if not ServiceExists('WireGuardManager') then begin
    Result :=
      'WireGuard installation appears incomplete (WireGuardManager service not found).' + #13#10 +
      'VPN driver/service installation may have failed. ' + #13#10 +
      'Please reinstall WireGuard and retry.';
    Exit;
  end;
end;

; HYNE ASM for Windows: one small setup. Installs the app for the current user (no admin), and when the
; .NET Desktop Runtime is missing, downloads it from Microsoft and installs it (Windows asks once for admin rights).
; Built by .github/workflows (ISCC with /DAppVersion=X.Y.Z), from the exe published into ..\..\publish.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F3C2B9E-8B1D-4C55-9E57-2A7B1D7A41C3}
AppName=HYNE ASM
AppVerName=HYNE ASM {#AppVersion}
AppVersion={#AppVersion}
AppPublisher=HYNE
AppPublisherURL=https://github.com/hynemusic/hyne-asm
AppSupportURL=https://github.com/hynemusic/hyne-asm
DefaultDirName={localappdata}\Programs\HYNE ASM
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=HYNE-ASM-Windows-Setup-{#AppVersion}
SetupIconFile=..\HyneAsm.App\AppIcon.ico
UninstallDisplayIcon={app}\HYNE ASM.exe
UninstallDisplayName=HYNE ASM
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; An update closes the running app first.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
en.RuntimeTitle=Getting the .NET Desktop Runtime
de.RuntimeTitle=.NET Desktop Runtime wird geladen
en.RuntimeText=HYNE ASM needs Microsoft's free .NET Desktop Runtime. It is downloaded from Microsoft and installed once.
de.RuntimeText=HYNE ASM braucht Microsofts kostenlose .NET Desktop Runtime. Sie wird einmalig von Microsoft geladen und installiert.
en.RuntimeFailed=The .NET Desktop Runtime couldn't be installed. Install it from https://dotnet.microsoft.com/download/dotnet/8.0 (".NET Desktop Runtime", x64), then start HYNE ASM.
de.RuntimeFailed=Die .NET Desktop Runtime konnte nicht installiert werden. Installiere sie von https://dotnet.microsoft.com/download/dotnet/8.0 („.NET Desktop Runtime“, x64) und starte dann HYNE ASM.
en.StartApp=Start HYNE ASM
de.StartApp=HYNE ASM starten

[Files]
Source: "..\..\publish\HYNE ASM.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\HYNE ASM"; Filename: "{app}\HYNE ASM.exe"

[Registry]
; The app writes these itself (hyneasm:// link, Start with Windows); the uninstaller removes them.
Root: HKCU; Subkey: "Software\Classes\hyneasm"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "HYNE ASM"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\HYNE ASM.exe"; Description: "{cm:StartApp}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DownloadPage: TDownloadWizardPage;

{ .NET 8 or newer (the app rolls forward to newer major versions). }
function DesktopRuntimeInstalled: Boolean;
var
  FindRec: TFindRec;
  Major: Integer;
begin
  Result := False;
  if FindFirst(ExpandConstant('{commonpf64}\dotnet\shared\Microsoft.WindowsDesktop.App\*'), FindRec) then
  begin
    try
      repeat
        Major := StrToIntDef(Copy(FindRec.Name, 1, Pos('.', FindRec.Name) - 1), 0);
        if Major >= 8 then Result := True;
      until Result or not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(CustomMessage('RuntimeTitle'), CustomMessage('RuntimeText'), nil);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if (CurPageID <> wpReady) or DesktopRuntimeInstalled then Exit;
  DownloadPage.Clear;
  DownloadPage.Add('https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe', 'windowsdesktop-runtime-win-x64.exe', '');
  DownloadPage.Show;
  try
    try
      DownloadPage.Download;
      { The runtime goes into Program Files: Windows asks once for admin rights. }
      if not ShellExec('runas', ExpandConstant('{tmp}\windowsdesktop-runtime-win-x64.exe'), '/install /quiet /norestart', '',
                       SW_SHOW, ewWaitUntilTerminated, ResultCode) or ((ResultCode <> 0) and (ResultCode <> 3010)) then
        MsgBox(CustomMessage('RuntimeFailed'), mbError, MB_OK);
    except
      MsgBox(CustomMessage('RuntimeFailed') + #13#10#13#10 + GetExceptionMessage, mbError, MB_OK);
    end;
  finally
    DownloadPage.Hide;
  end;
end;

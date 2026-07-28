[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
AppId={{5A1B8C0D-1234-5678-ABCD-E90F1A2B3C4D}
AppName=Voucher App
AppVersion=1.0.1
AppPublisher=JCBoy
DefaultDirName={autopf}\Voucher App
DefaultGroupName=Voucher App
OutputDir=.\build\windows\installer
OutputBaseFilename=VoucherApp_v1.0.1_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=compiler:SetupClassicIcon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: ".\build\windows\x64\runner\Release\voucherapps.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\Voucher App"; Filename: "{app}\voucherapps.exe"
Name: "{autodesktop}\Voucher App"; Filename: "{app}\voucherapps.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\voucherapps.exe"; Description: "{cm:LaunchProgram,Voucher App}"; Flags: nowait postinstall skipifsilent

; Instalador do NN Cloud para Windows (Inno Setup 6).
; Gerado por scripts/empacotar-windows.ps1 — não compile à mão sem antes rodar
; o `flutter build windows --release` e copiar o runtime do Visual C++ (o script faz).
;
; ⚠️ POR USUÁRIO, sem administrador: instala em %LOCALAPPDATA%\Programs\NN Cloud.
;    Por isso o runtime do Visual C++ vai JUNTO do app (as três DLLs ao lado do
;    .exe, "app-local", que a Microsoft suporta) em vez do VC_redist, que exige admin.
; ⚠️ AppMutex = o mutex que o app cria ao abrir: o instalador pede para fechar
;    o NN Cloud antes de atualizar (senão os arquivos estariam em uso).
; ⚠️ AppUserModelID no atalho do menu Iniciar: SEM ele as notificações do
;    Windows não aparecem (é o mesmo id de lib/servicos/notificacoes.dart).
; ⚠️ AppId NUNCA muda: é por ele que a atualização encontra a instalação anterior
;    e mantém o login (o token fica no Gerenciador de Credenciais do Windows).

#ifndef Versao
  #define Versao "1.0.0"
#endif
#ifndef Origem
  #define Origem "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8F3C6A1E-2B7D-4C5E-9A41-6E0B3D2F7C19}
AppName=NN Cloud
AppVersion={#Versao}
AppVerName=NN Cloud {#Versao}
AppPublisher=Norton Nunes
AppPublisherURL=https://nnconecta.com
DefaultDirName={localappdata}\Programs\NN Cloud
DefaultGroupName=NN Cloud
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\instaladores
OutputBaseFilename=NN-Cloud-{#Versao}-Windows
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nncloud.exe
UninstallDisplayName=NN Cloud
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
AppMutex=NNCloudAppMutex
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked
Name: "iniciar"; Description: "Iniciar o NN Cloud junto com o Windows"; GroupDescription: "Inicialização:"

[Files]
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\NN Cloud"; Filename: "{app}\nncloud.exe"; AppUserModelID: "NortonNunes.NNCloud"
Name: "{userdesktop}\NN Cloud"; Filename: "{app}\nncloud.exe"; Tasks: desktopicon

[Registry]
; Iniciar com o Windows (o app também liga/desliga isto em Configurações).
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "NN Cloud"; \
  ValueData: """{app}\nncloud.exe"" --oculto"; Flags: uninsdeletevalue; Tasks: iniciar

[Run]
Filename: "{app}\nncloud.exe"; Description: "Abrir o NN Cloud"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Só o que é do PROGRAMA. As pastas sincronizadas e os arquivos da pessoa ficam.
Type: filesandordirs; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(Etapa: TUninstallStep);
begin
  // O app pode ter ligado o início com o Windows sozinho (Configurações).
  if Etapa = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'NN Cloud');
end;

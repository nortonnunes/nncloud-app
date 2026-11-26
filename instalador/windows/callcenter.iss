; Instalador do Conecta Callcenter para Windows (Inno Setup 6).
; Gerado por scripts/empacotar-windows.ps1 — não compile à mão sem antes rodar
; o `flutter build windows --release` e copiar o runtime do Visual C++ (o script faz).
;
; ⚠️ POR USUÁRIO, sem administrador: instala em %LOCALAPPDATA%\Programs\Conecta Callcenter.
; ⚠️ AppMutex = o mutex que o app cria ao abrir (NNCallcenterAppMutex, lib/servicos/sistema.dart).
; ⚠️ AppUserModelID no atalho: SEM ele as notificações do Windows (comunicados,
;    mensagens novas) não aparecem — é o mesmo id de lib/servicos/notificacoes.dart.
; ⚠️ AppId NUNCA muda: é por ele que a atualização acha a instalação anterior e
;    mantém a autorização do computador (fica no Gerenciador de Credenciais).
; ⚠️ "Iniciar com o Windows" nasce MARCADO: o comunicado só chega com o app aberto.

#ifndef Versao
  #define Versao "1.0.0"
#endif
#ifndef Origem
  #define Origem "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{C7A2E4D9-5B13-4F6A-8E27-1D9C3B5A0F64}
AppName=Conecta Callcenter
AppVersion={#Versao}
AppVerName=Conecta Callcenter {#Versao}
AppPublisher=Norton Nunes
AppPublisherURL=https://nnconecta.com
DefaultDirName={localappdata}\Programs\Conecta Callcenter
DefaultGroupName=Conecta Callcenter
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\instaladores
OutputBaseFilename=Conecta-Callcenter-{#Versao}-Windows
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ConectaCallcenter.exe
UninstallDisplayName=Conecta Callcenter
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
AppMutex=NNCallcenterAppMutex
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos:"
Name: "iniciar"; Description: "Iniciar o Conecta Callcenter junto com o Windows (recomendado: os comunicados só chegam com o app aberto)"; GroupDescription: "Inicialização:"

[Files]
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Conecta Callcenter"; Filename: "{app}\ConectaCallcenter.exe"; AppUserModelID: "NortonNunes.NNCallcenter"
Name: "{userdesktop}\Conecta Callcenter"; Filename: "{app}\ConectaCallcenter.exe"; AppUserModelID: "NortonNunes.NNCallcenter"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Conecta Callcenter"; \
  ValueData: """{app}\ConectaCallcenter.exe"" --oculto"; Flags: uninsdeletevalue; Tasks: iniciar

[Run]
Filename: "{app}\ConectaCallcenter.exe"; Description: "Abrir o Conecta Callcenter"; Flags: nowait postinstall skipifsilent
; Atualização automática (o app roda este instalador em silêncio depois de sair):
; reabre escondido, na bandeja — a linha acima não roda em modo silencioso.
Filename: "{app}\ConectaCallcenter.exe"; Parameters: "--oculto"; Flags: nowait; Check: WizardSilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(Etapa: TUninstallStep);
begin
  if Etapa = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Conecta Callcenter');
end;

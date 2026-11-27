; Instalador do NN Conversas para Windows (Inno Setup 6).
; Gerado por scripts/empacotar-windows.ps1 — não compile à mão sem antes rodar
; o `flutter build windows --release` e copiar o runtime do Visual C++ (o script faz).
;
; ⚠️ POR USUÁRIO, sem administrador: instala em %LOCALAPPDATA%\Programs\NN Conversas.
; ⚠️ AppMutex = o mutex que o app cria ao abrir (NNConversasAppMutex, lib/servicos/sistema.dart).
; ⚠️ AppUserModelID no atalho: SEM ele as notificações do Windows (comunicados,
;    mensagens novas) não aparecem — é o mesmo id de lib/servicos/notificacoes.dart.
; ⚠️ AppId NUNCA muda (e é DIFERENTE do NN Unifi): é por ele que a
;    atualização acha a instalação anterior.
; ⚠️ "Iniciar com o Windows" nasce MARCADO: o comunicado só chega com o app aberto.
; ⚠️ O valor "NN Conversas" da chave Run é o mesmo que o app lê (lib/servicos/sistema.dart).

#ifndef Versao
  #define Versao "1.0.1"
#endif
#ifndef Origem
  #define Origem "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{CA2AEA6B-AE3B-485A-AC33-F2EC982DCAF4}
AppName=NN Conversas
AppVersion={#Versao}
AppVerName=NN Conversas {#Versao}
AppPublisher=Norton Nunes
AppPublisherURL=https://nnconecta.com
DefaultDirName={localappdata}\Programs\NN Conversas
DefaultGroupName=NN Conversas
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\instaladores
OutputBaseFilename=NN-Conversas-{#Versao}-Windows
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\NNConversas.exe
UninstallDisplayName=NN Conversas
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
AppMutex=NNConversasAppMutex
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos:"
Name: "iniciar"; Description: "Iniciar o NN Conversas junto com o Windows (recomendado: as mensagens e os comunicados só chegam com o app aberto)"; GroupDescription: "Inicialização:"

[Files]
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\NN Conversas"; Filename: "{app}\NNConversas.exe"; AppUserModelID: "NortonNunes.NNConversas"
Name: "{userdesktop}\NN Conversas"; Filename: "{app}\NNConversas.exe"; AppUserModelID: "NortonNunes.NNConversas"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "NN Conversas"; \
  ValueData: """{app}\NNConversas.exe"" --oculto"; Flags: uninsdeletevalue; Tasks: iniciar

[Run]
Filename: "{app}\NNConversas.exe"; Description: "Abrir o NN Conversas"; Flags: nowait postinstall skipifsilent
; Atualização automática (o app roda este instalador em silêncio depois de sair):
; reabre escondido, na bandeja — a linha acima não roda em modo silencioso.
Filename: "{app}\NNConversas.exe"; Parameters: "--oculto"; Flags: nowait; Check: WizardSilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(Etapa: TUninstallStep);
begin
  if Etapa = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'NN Conversas');
end;

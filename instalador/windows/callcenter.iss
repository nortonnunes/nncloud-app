; Instalador do NN Unifi para Windows (Inno Setup 6). Até a 1.0.3: "APP Operação UNIFI"; até a 1.0.2: "Conecta Callcenter".
; Gerado por scripts/empacotar-windows.ps1 — não compile à mão sem antes rodar
; o `flutter build windows --release` e copiar o runtime do Visual C++ (o script faz).
;
; ⚠️ POR USUÁRIO, sem administrador: instala em %LOCALAPPDATA%\Programs\Conecta Callcenter.
; ⚠️ O nome NOVO é só o que se vê (AppName, atalhos, Programas e Recursos). A pasta,
;    o .exe e o valor "Conecta Callcenter" da chave Run ficam: é o app que os lê
;    (lib/servicos/sistema.dart), e quem atualiza continua na mesma pasta.
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
AppName=NN Unifi
AppVersion={#Versao}
AppVerName=NN Unifi {#Versao}
AppPublisher=Norton Nunes
AppPublisherURL=https://nnconecta.com
DefaultDirName={localappdata}\Programs\Conecta Callcenter
DefaultGroupName=NN Unifi
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\instaladores
OutputBaseFilename=NN-Unifi-{#Versao}-Windows
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ConectaCallcenter.exe
UninstallDisplayName=NN Unifi
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
Name: "iniciar"; Description: "Iniciar o NN Unifi junto com o Windows (recomendado: os comunicados só chegam com o app aberto)"; GroupDescription: "Inicialização:"

[Files]
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Os atalhos com os nomes antigos (até a 1.0.2 e a 1.0.3) — sem isto ficariam dois no menu Iniciar.
Type: files; Name: "{userprograms}\Conecta Callcenter.lnk"
Type: files; Name: "{userdesktop}\Conecta Callcenter.lnk"
Type: files; Name: "{userprograms}\APP Operação UNIFI.lnk"
Type: files; Name: "{userdesktop}\APP Operação UNIFI.lnk"

[Icons]
Name: "{userprograms}\NN Unifi"; Filename: "{app}\ConectaCallcenter.exe"; AppUserModelID: "NortonNunes.NNCallcenter"
Name: "{userdesktop}\NN Unifi"; Filename: "{app}\ConectaCallcenter.exe"; AppUserModelID: "NortonNunes.NNCallcenter"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Conecta Callcenter"; \
  ValueData: """{app}\ConectaCallcenter.exe"" --oculto"; Flags: uninsdeletevalue; Tasks: iniciar

[Run]
Filename: "{app}\ConectaCallcenter.exe"; Description: "Abrir o NN Unifi"; Flags: nowait postinstall skipifsilent
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

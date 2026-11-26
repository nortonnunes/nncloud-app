# APP Operação UNIFI (até a 1.0.2: Conecta Callcenter)

O app de computador do Tele Atendimento do NN Conecta (Flutter desktop: Windows, macOS
Apple Silicon/Intel e Linux). Abre numa dashboard (NN News, Quadro de avisos,
aniversariantes do mês), tem as **Conversas completas** do site, recebe os **comunicados**
com alerta, fica **sempre em tela cheia** e, ao minimizar, vai para o ícone ao lado do relógio.
O topo (logo, cores, tema sazonal, degradê da barra) vem do NN Conecta.

Só **tele atendentes** entram, com e-mail e senha, num **computador autorizado** (o app mostra
um código na primeira abertura e o administrador aprova em Sistema → APP Operação UNIFI), e só
a partir dos **IPs liberados** lá. A API é `/v1/callapp/*` (regime `callapp` do servidor).

## Desenvolvimento

```sh
flutter pub get
flutter analyze
flutter test                                    # formatação do chat + telas (goldens)
flutter run -d macos --dart-define=CALLAPP_TESTE=true --dart-define=CALLAPP_API=http://127.0.0.1:8892
```

- `CALLAPP_API` = endereço da API (padrão `https://api.nortonnunes.com.br`). `http://` só vale
  com `CALLAPP_TESTE=true` — a senha e o token nunca trafegam abertos.
- `AppConfig.versao` (lib/config.dart) anda junto do `version` do pubspec: é ela que o servidor
  compara para oferecer a atualização.
- Ponta a ponta contra a API real (banco de teste do servidor):
  `CALLAPP_E2E=1 CALLAPP_E2E_APROVAR="php <scratchpad>/semear_dart.php aprovar" flutter test test/e2e_chat_test.dart`
- Capturas: `flutter test test/telas_test.dart --update-goldens` (PNG em `test/goldens/`).

## Onde está cada coisa

| | |
|---|---|
| `lib/api/cliente.dart` | cliente HTTP (chave do computador + token, keep-alive curto, repete queda em leitura) |
| `lib/servicos/controle.dart` | estado: computador → login → sessão; comunicados, `/eu`, aparência |
| `lib/servicos/janela.dart` | tela cheia sempre; minimizar/fechar → bandeja |
| `lib/servicos/atualizacao.dart` | atualização automática (Inno silencioso / troca do .app conferida / .deb) |
| `lib/telas/casca.dart` | topo igual ao do NN Conecta, menu, comunicado por cima |
| `lib/telas/conversas/` | o chat: lista, conversa, compositor formatado, diálogos, tempo real |
| `lib/telas/conversas/formato.dart` | o HTML do chat ↔ compositor (as tags do `ChatHtml` do site) |

## Gerar os instaladores

| Sistema | Como | Sai em |
|---|---|---|
| macOS | `CALLAPP_API=https://… scripts/empacotar-macos.sh` (neste Mac: Developer ID + notarização pelo perfil `NNCLOUD`) | `build/instaladores/APP-Operacao-UNIFI-<v>.dmg` |
| Windows | `git tag -a callcenter-v<versão> && git push origin callcenter callcenter-v<versão>` (roda Windows e Linux no GitHub), ou `scripts\empacotar-windows.ps1` num PC com Windows | `APP-Operacao-UNIFI-<v>-Windows.exe` (em Actions → Artifacts) |
| Linux | a mesma tag (ou `scripts/empacotar-linux.sh` no Ubuntu 22.04) | `conecta-callcenter_<v>_amd64.deb` |

O código mora no **repositório do NN Cloud** (`nortonnunes/nncloud-app`), na **branch `callcenter`**
(independente da `main` do NN Cloud). As tags levam o prefixo `callcenter-` porque o espaço de tags é
do repositório inteiro, e os workflows (`callcenter-windows.yml`, `callcenter-linux.yml`) têm nome de
arquivo próprio — o GitHub agrupa as execuções pelo caminho do arquivo.

Publique cada instalador em **Sistema → APP Operação UNIFI → Aplicativo**, com a versão. Os
computadores com o app aberto baixam sozinhos, conferem e instalam quando a janela vai para a bandeja.

⚠️ Não mude: o bundle id `br.com.nortonnunes.callcenter` (macOS), o time `52YUD97UMR`, o `AppId`
do Inno Setup, o mutex `NNCallcenterAppMutex` e o AppUserModelID `NortonNunes.NNCallcenter` —
a atualização e as notificações dependem deles.

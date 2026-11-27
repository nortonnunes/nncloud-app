# NN Conversas

As **Conversas do NN Conecta** no computador (Flutter desktop: Windows, macOS Apple Silicon/Intel e
Linux). Abre nas Conversas — com **todas as funções do site** (formatação, anexos, responder,
reações, editar, encaminhar, enquetes, grupos, menções, busca, favoritos) —, tem o **Início**
(NN News, avisos e aniversariantes), o **NN News** para leitura, o **Quadro de avisos** e os
**comunicados** com alerta. Janela normal (lembra o tamanho e a posição); minimizar ou fechar leva
para o ícone ao lado do relógio. O topo e o menu são os do NN Unifi (logo, cores, tema
sazonal e a barra em onda do NN Conecta).

Entra quem tem a **permissão de Conversas** no NN Conecta (operadora e tele atendente não), com o
**login igual ao do site**: e-mail e senha → política de uso (quando falta aceitar) → verificação em
duas etapas (app autenticador, código por e-mail ou aprovação no celular), ou configurar o app
autenticador; ou o **QR code** lido com o app NN Conecta do celular. Sem lista de IPs e sem aprovar
computador. A API é `/v1/conversas/*` (regime `conversas` do servidor).

## Desenvolvimento

```sh
flutter pub get
flutter analyze
flutter test                                    # formatação do chat + telas (goldens)
flutter run -d macos --dart-define=CONVERSAS_TESTE=true --dart-define=CONVERSAS_API=http://127.0.0.1:8893
```

- `CONVERSAS_API` = endereço da API (padrão `https://api.nortonnunes.com.br`). `http://` só vale
  com `CONVERSAS_TESTE=true` — a senha e o token nunca trafegam abertos.
- `AppConfig.versao` (lib/config.dart) anda junto do `version` do pubspec: é ela que o servidor
  compara para oferecer a atualização.
- Ponta a ponta contra a API real (banco de teste do servidor, `php preparar.php && php semear_dart.php`,
  que imprime o token do "celular"): `CONVERSAS_E2E=1 CONVERSAS_E2E_TOKEN=<token> flutter test test/e2e_chat_test.dart`.
  O login é feito pelo `Controle` do próprio app (senha, TOTP, política, configuração, e-mail, QR).
- Capturas: `flutter test test/telas_test.dart --update-goldens` (PNG em `test/goldens/`).

## Onde está cada coisa

| | |
|---|---|
| `lib/api/cliente.dart` | cliente HTTP (token `nnconv_`, keep-alive curto, repete queda em leitura) |
| `lib/servicos/controle.dart` | estado: login em etapas (senha, política, 2FA, setup, QR) → sessão; comunicados, `/eu`, aparência |
| `lib/telas/acesso.dart` | as telas do login (e o bloqueio) |
| `lib/servicos/janela.dart` | janela normal que lembra o tamanho/posição; minimizar/fechar → bandeja |
| `lib/servicos/atualizacao.dart` | atualização automática (Inno silencioso / troca do .app conferida / .deb) |
| `lib/telas/casca.dart` | topo igual ao do NN Conecta, menu, comunicado por cima |
| `lib/telas/conversas/` | o chat: lista, conversa, compositor formatado, diálogos, tempo real |

⚠️ **Gêmeo do NN Unifi** (`public_app_call/`): o chat, o topo, o NN News, os avisos, o
rodapé e a atualização são cópias. Correção feita num lado precisa ir ao outro.

## Gerar os instaladores

| Sistema | Como | Sai em |
|---|---|---|
| macOS | `CONVERSAS_API=https://… scripts/empacotar-macos.sh` (neste Mac: Developer ID + notarização pelo perfil `NNCLOUD`) | `build/instaladores/NN-Conversas-<v>.dmg` |
| Windows | `git tag -a conversas-v<versão> && git push origin conversas conversas-v<versão>` (roda Windows e Linux no GitHub), ou `scripts\empacotar-windows.ps1` num PC com Windows | `NN-Conversas-<v>-Windows.exe` (em Actions → Artifacts) |
| Linux | a mesma tag (ou `scripts/empacotar-linux.sh` no Ubuntu 22.04) | `nn-conversas_<v>_amd64.deb` |

O código mora no **repositório do NN Cloud** (`nortonnunes/nncloud-app`), na **branch `conversas`**
(independente da `main` do NN Cloud e da `callcenter` do Unifi). As tags levam o prefixo
`conversas-` e os workflows têm nome próprio (`conversas-windows.yml`, `conversas-linux.yml`).

Publique cada instalador em **Sistema → NN Conversas → Aplicativo** (ou pelo terminal com
`scripts/publicar-no-servidor.php`). Os computadores com o app aberto baixam sozinhos, conferem e
instalam quando a janela vai para a bandeja.

⚠️ Não mude: o bundle id `br.com.nortonnunes.conversas` (macOS), o time `52YUD97UMR`, o `AppId`
do Inno Setup, o mutex `NNConversasAppMutex`, o AppUserModelID `NortonNunes.NNConversas`, o
`ProductName` do Runner.rc e a pasta de dados "NN Conversas" — a atualização, a sessão guardada e as
notificações dependem deles.

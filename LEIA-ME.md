# NN Cloud — aplicativo para Windows, macOS e Linux

O NN Cloud mantém pastas do computador iguais a pastas do NN Cloud (o drive do NN Conecta), nos dois sentidos.
Esta pasta não vai para o servidor: o aplicativo chega às pessoas pelo instalador, publicado em
**Sistema → NN Cloud → Aplicativo**.

## O que há aqui

| Pasta | O que é |
|---|---|
| `motor/` | O motor de sincronização, em Dart puro (sem Flutter). Toda a lógica que decide e executa está aqui, e é testada sozinha. |
| `lib/` | O aplicativo Flutter: telas, bandeja, notificações, início com o sistema. |
| `macos/`, `windows/`, `linux/` | Os projetos nativos (nome, ícone, permissões). `linux/pacote/` tem os ícones do menu de aplicativos. |
| `macos/NNCloudKit/` | Cliente Swift da API (impressão, envio, download, credenciais) — `swift test`. |
| `macos/NNCloudFP/` | A extensão do Finder (File Provider): o "NN Cloud" sob demanda. |
| `windows/runner/nuvem_windows.*` | A ponte com a Cloud Files API: o "NN Cloud" sob demanda no Explorador de Arquivos. |
| `instalador/windows/nncloud.iss` | O instalador do Windows (Inno Setup). |
| `scripts/` | `empacotar-macos.sh`, `empacotar-windows.ps1` e `empacotar-linux.sh`. |
| `assets/` | Logo e ícones da bandeja. |

## Como funciona, em uma página

- **Conectar**: o app pede um código ao NN Conecta e abre o navegador. A pessoa, já logada (com 2FA), confere o código e
  clica em **Autorizar**. O app recebe um token próprio do computador (`nncl_…`), guardado no chaveiro do sistema
  (Keychain no macOS, Gerenciador de Credenciais no Windows). O app nunca vê a senha.
- **Cada pasta sincronizada** é um *par*: pasta do computador ↔ pasta do NN Cloud. Para cada par, o motor compara três
  visões — a nuvem, o computador e a **base** (o último estado em que os dois concordavam) — e decide:

  | Situação | O que acontece |
  |---|---|
  | Mudou só no computador | Envia |
  | Mudou só na nuvem | Baixa (confere a impressão, troca o arquivo de uma vez e guarda a versão anterior) |
  | Mudou nos dois | Conteúdo igual: nada trafega. Diferente: a nuvem fica com o nome e a versão do computador vira `nome (conflito de COMPUTADOR data).ext` |
  | Apagado no computador | Vai para a lixeira do NN Cloud |
  | Apagado na nuvem | Vai para a lixeira local do app (`.nncloud-lixeira`, 30 dias) |
  | Mudança × exclusão | A mudança vence |
  | Movido ou renomeado | Detectado (pelo id na nuvem; por tamanho + impressão no computador) e refeito do outro lado, sem transferir de novo |

- **Liberar espaço** (botão **Opções** de cada pasta):
  - **Pasta de envio**: o que entra na pasta sobe e sai do computador depois de confirmado na nuvem (e sem
    alteração há 5 minutos). Nada desce; apagar no computador não apaga na nuvem. Para scanner, backup, arquivo morto.
  - **Sincronização seletiva**: desmarque as subpastas que podem ficar só na nuvem. Saem do computador; marcar de
    novo faz descer (a tela avisa quanto antes de salvar).
  - Só sai do disco o que está igual na nuvem; a base é gravada antes de apagar.
- **NN Cloud no Finder (macOS 13+)** — cartão na Visão geral: um local "NN Cloud" na barra lateral com Meu Drive,
  Compartilhados comigo e Drives compartilhados. Tudo aparece sem ocupar espaço e só desce o que é aberto;
  botão direito → "Remover download" devolve o espaço. Com **"Liberar o espaço depois de enviar"**, o que é colocado
  lá sobe e sai do disco. Quem faz o trabalho é a extensão `NNCloudFP` (roda mesmo com o app fechado).
  - **No macOS 15+ é preciso aprovar uma vez** em Ajustes do Sistema → Geral → Itens de Início e Extensões; até lá a
    pasta aparece vazia. O app avisa e tem o botão que abre os Ajustes.
  - Desligar tira o NN Cloud do Finder; o que ainda não tinha subido o macOS guarda numa pasta à parte.
- **NN Cloud no Explorador de Arquivos (Windows 10 1809+)** — o mesmo cartão: a pasta `%USERPROFILE%\NN Cloud` aparece
  no painel lateral, com Meu Drive, Compartilhados comigo e Drives compartilhados. Botão direito → "Liberar espaço" /
  "Sempre manter neste dispositivo". **No Windows quem entrega os arquivos é o próprio app**: com ele fechado, o que
  não está no disco não abre (por isso ele inicia com o Windows). Desligar deixa o que estava baixado como arquivo
  comum na mesma pasta. A regra está no motor (`motor/lib/src/sob_demanda.dart`); a ponte com a Cloud Files API em
  `windows/runner/nuvem_windows.cpp`.
- **Proteções contra perda de dados**:
  - um marcador `.nncloud` na raiz: pasta sumida ou disco desconectado **para** a sincronização, nunca apaga nada;
  - diário local perdido (app reinstalado): **junção segura**, sem exclusão em lado nenhum até um ciclo limpo;
  - mais de 50 exclusões (ou 25% da pasta) de uma vez: o app **pede confirmação**, nos dois sentidos;
  - nome que o Windows não aceita, pasta só de leitura: vira **Problema** na tela, e o arquivo fica no computador.
- **Ritmo**: uma consulta de mudanças a cada 30 s; o observador de pastas antecipa o ciclo; varredura completa a cada 10
  minutos e ao acordar da suspensão; até 3 transferências ao mesmo tempo, direto com o armazenamento (S3).

## Desenvolvimento

```sh
cd motor && dart test                 # planejador + contrato com o PHP
cd .. && flutter analyze && flutter test
flutter run -d macos
```

O endereço da API fica em Configurações → Rede (padrão `https://api.nortonnunes.com.br`). Para apontar para um
servidor de teste antes de abrir o app, crie
`~/Library/Application Support/br.com.nortonnunes.nncloud/NN Cloud/preferencias.json` com `{"api": "http://127.0.0.1:8782"}`.

Testes de ponta a ponta (precisam da API, do S3 falso e do MySQL de teste no ar):

```sh
NCL_E2E=1 NCL_API=http://127.0.0.1:8782 NCL_PREPARAR=<script que zera o banco e imprime os tokens> dart test motor/test/e2e_test.dart
NCL_E2E=1 NCL_API=… NCL_PREPARAR=… NCL_PHP_T=<pasta dos scripts PHP> flutter test test/controle_test.dart
flutter test test/telas_test.dart --update-goldens   # renders das telas em test/goldens/
```

⚠️ **Mudou uma regra de nome ou a impressão?** Elas são contrato com `app/Core/NnCloud/Nome.php` e `Impressao.php`.
Gere de novo `motor/test/fixtures/contrato_php.json` a partir do PHP e rode `dart test`.

## Gerar os instaladores

### macOS (neste Mac)

```sh
scripts/empacotar-macos.sh
```

Compila (universal), assina com o certificado **Developer ID Application** do chaveiro, com runtime endurecido, e
gera `build/instaladores/NN-Cloud-<versão>.dmg`.

Para **notarizar** (sem isso, outros Macs avisam que o desenvolvedor não pôde ser verificado), guarde as credenciais
da Apple uma vez neste Mac — a senha fica no chaveiro e o script nunca a vê:

```sh
xcrun notarytool store-credentials NNCLOUD --apple-id <e-mail da conta Apple> --team-id <ID do time>
```

Depois disso, o mesmo script envia, espera a aprovação e grampeia o resultado no DMG.

A extensão do Finder (`NNCloudFP.appex`) é assinada pelo mesmo script, antes do app, com
`macos/NNCloudFP/NNCloudFP.entitlements` (sandbox, rede e o App Group `52YUD97UMR.br.com.nortonnunes.nncloud`).
Se mexer no projeto Xcode e a extensão sumir, rode de novo `scripts/adicionar-extensao-fp.rb` (com a gem `xcodeproj`
do CocoaPods).

**Testar o Finder sem mexer no NN Cloud instalado**: troque `NNCLOUD_ID` em `macos/Runner/Configs/AppInfo.xcconfig`
para `br.com.nortonnunes.nncloud.teste` (e **volte depois**), gere com
`DART_DEFINES="--dart-define=NNCLOUD_TESTE=true" SEM_DMG=1 scripts/empacotar-macos.sh`, copie o app para
`~/Applications` e abra com `NNCLOUD_TOKEN=<token> NNCLOUD_API=<api> NNCLOUD_FP=1`. Para remover o domínio de teste,
abra de novo com `NNCLOUD_FP=0` (só o app dono remove o domínio — apagar o app não basta).

⚠️ Abrir o `.app` de `build/` sem passar pelo script falha com "different Team IDs": com o runtime endurecido, todos
os frameworks precisam da mesma assinatura do app, e é o script que faz isso.

### Windows (num PC com Windows)

Requisitos: Flutter 3.41.6, Visual Studio 2022 com "Desenvolvimento para desktop com C++", Inno Setup 6.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\empacotar-windows.ps1
```

Gera `build\instaladores\NN-Cloud-<versão>-Windows.exe`: instalação **por usuário** (sem administrador), runtime do
Visual C++ junto do app, atalho com o AppUserModelID das notificações, e opção de iniciar com o Windows. Com
`$env:CERTIFICADO_PFX` e `$env:SENHA_PFX`, assina com Authenticode (evita o aviso do SmartScreen).

**Conferir no PC com Windows antes do piloto**: notificação aparece; inicia escondido depois de reiniciar; ícone na
bandeja; arquivo aberto no Word não sobe pela metade; renomear só maiúscula/minúscula; caminho longo; atualizar por
cima sem perder o login; desinstalar remove o início com o Windows e mantém as pastas.

### Publicar

Em **Sistema → NN Cloud → Aplicativo**, envie o `.dmg` e o `.exe` com o número da versão. Quem pode usar o app baixa
pela página do NN Cloud ou pelo Perfil → Integrações; os apps já instalados avisam que há versão nova.

## Versão

Mude a versão em **dois lugares**: `pubspec.yaml` (`version:`) e `lib/config.dart` (`AppConfig.versao`).

## Linux

- **Gerar**: o Flutter só compila para Linux numa máquina Linux. No GitHub: aba **Actions → "Instalador Linux" → Run
  workflow** (`.github/workflows/linux.yml`, Ubuntu 22.04); os arquivos saem em *Artifacts*. Num PC com Linux:
  `bash scripts/empacotar-linux.sh` (pré-requisitos no topo do script).
- **Saem dois arquivos** (em `build/instaladores/`):
  - `nncloud_<versão>_amd64.deb` — Ubuntu, Debian, Mint, Pop!_OS: `sudo apt install ./nncloud_<versão>_amd64.deb`.
    Instala em `/opt/nncloud`, com atalho no menu de aplicativos e o comando `nncloud`.
  - `NN-Cloud-<versão>-linux-x64.tar.gz` — as demais distribuições: desempacotar e rodar `./instalar.sh` (só para o
    usuário, sem sudo; `./instalar.sh --remover` tira).
- **Compatibilidade**: compilado no Ubuntu 22.04, roda no Ubuntu 22.04+, Debian 12+ e equivalentes (o binário depende
  da glibc de onde foi compilado). x64; para ARM, rode o script numa máquina ARM.
- **Publicar**: Sistema → NN Cloud → Aplicativo → Linux (aceita `.deb`, `.tar.gz` ou `.AppImage`). A página do NN Cloud
  e o Perfil passam a oferecer "Baixar para Linux".
- **O que é diferente no Linux**:
  - **Sem "NN Cloud no Finder/Explorador"** (arquivos sob demanda): o Linux não tem um padrão do sistema para isso.
    Ficam as pastas sincronizadas, a pasta de envio e a sincronização seletiva — iguais às dos outros sistemas.
  - **Token** no chaveiro da sessão (GNOME Keyring / KWallet, via libsecret). Sem chaveiro (gerenciador de janelas
    mínimo, sessão remota), vai para o arquivo `token` na pasta do app, com permissão 600.
  - **Ícone na barra** pelo AppIndicator (no GNOME puro, a extensão "AppIndicator"; o Ubuntu já traz). Sem ele, o app
    continua sincronizando com a janela fechada; abrir de novo pelo menu de aplicativos mostra a janela.
  - **Iniciar com o sistema**: `~/.config/autostart/br.com.nortonnunes.nncloud.desktop` (`--oculto`).
  - **Dados do app**: `~/.local/share/br.com.nortonnunes.nncloud/NN Cloud/`.
  - O Linux diferencia maiúsculas: dois arquivos `Foto.jpg` e `foto.jpg` na mesma pasta não convivem no NN Cloud (que
    segue a regra do Windows e do macOS) — o segundo aparece em **Problemas**.


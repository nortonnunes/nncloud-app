# NN Cloud — aplicativo para Windows e macOS

O NN Cloud mantém pastas do computador iguais a pastas do NN Cloud (o drive do NN Conecta), nos dois sentidos.
Esta pasta não vai para o servidor: o aplicativo chega às pessoas pelo instalador, publicado em
**Sistema → NN Cloud → Aplicativo**.

## O que há aqui

| Pasta | O que é |
|---|---|
| `motor/` | O motor de sincronização, em Dart puro (sem Flutter). Toda a lógica que decide e executa está aqui, e é testada sozinha. |
| `lib/` | O aplicativo Flutter: telas, bandeja, notificações, início com o sistema. |
| `macos/`, `windows/` | Os projetos nativos (nome, ícone, permissões). |
| `instalador/windows/nncloud.iss` | O instalador do Windows (Inno Setup). |
| `scripts/` | `empacotar-macos.sh` e `empacotar-windows.ps1`. |
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

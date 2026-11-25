// API falsa para a verificação de ponta a ponta do "Atualizar agora" (só testes).
//
//   dart run test/bin/api_falsa_atualizacao.dart <porta> <instalador.dmg|.exe> <versao> <so>
//
// Responde `eu` com o instalador como versão nova, `app/baixar` com a URL dele (com
// a impressão calculada aqui, como o servidor guarda) e o arquivo em /arquivo. O resto
// devolve listas vazias (nenhuma pasta) — o bastante para o app abrir e se atualizar.
import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/motor.dart';

Future<void> main(List<String> a) async {
  final porta = int.parse(a[0]);
  final arquivo = File(a[1]);
  final versao = a[2], so = a[3];
  final imp = await Impressao.deArquivo(arquivo);
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
  stdout.writeln('api falsa em http://127.0.0.1:$porta (impressão ${imp!.hex.substring(0, 12)}…)');
  final instalador = {'versao': versao, 'nome': arquivo.uri.pathSegments.last, 'tamanho': imp.tamanho, 'sha256': imp.hex, 'em': '2026-11-25 12:00:00'};
  await for (final r in s) {
    final caminho = r.uri.path;
    stdout.writeln('${r.method} $caminho');
    if (caminho == '/arquivo') {
      r.response.headers.contentType = ContentType.binary;
      await r.response.addStream(arquivo.openRead());
      await r.response.close();
      continue;
    }
    Object dados;
    if (caminho.endsWith('/eu')) {
      dados = {
        'pessoa': {'id': 1, 'nome': 'Teste', 'email': 'teste@exemplo.test'},
        'computador': {'id': 1, 'nome': 'Teste', 'plataforma': so},
        'meu_drive': {'id': 1, 'nome': 'Meu Drive', 'usado': 0, 'limite': 1 << 30},
        'permissoes': {'compartilhar': false},
        'config': {'intervalo_seg': 30, 'tamanho_parte': 8 << 20, 'max_arquivo': 1 << 30, 'bloqueadas': [], 'ignorados': [],
          'versao_minima': '1.0.0', 'web': 'http://127.0.0.1:$porta/cloud'},
        'app': {'windows': null, 'macos': null, 'linux': null, so: instalador},
      };
    } else if (caminho.endsWith('/app/baixar')) {
      dados = {'url': 'http://127.0.0.1:$porta/arquivo', 'versao': versao, 'nome': instalador['nome'], 'tamanho': imp.tamanho,
        'impressao': imp.hex, 'expira_seg': 300};
    } else {
      dados = {'pares': [], 'itens': [], 'espacos': [], 'pastas': [], 'envios': [], 'removidos': [], 'ok': true};
    }
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode({'data': dados}));
    await r.response.close();
  }
}

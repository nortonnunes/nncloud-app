// A "impressão digital" do arquivo — contrato com `app/Core/NnCloud/Impressao.php`
// e com o `nncloud-envio.js`:
//
//   impressão = hex( sha256( sha256(parte 1) ‖ sha256(parte 2) ‖ … ) )
//
// com partes de 8 MiB (um arquivo vazio é UMA parte vazia). O servidor confere
// a impressão no S3 sem confiar no cliente, e cada URL de parte trava o sha256
// daquela parte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int tamanhoParte = 8388608;

int nPartes(int tamanho) => tamanho <= 0 ? 1 : (tamanho + tamanhoParte - 1) ~/ tamanhoParte;

int tamanhoDaParte(int tamanho, int n) {
  final total = nPartes(tamanho);
  if (n < 1 || n > total) return 0;
  return n < total ? tamanhoParte : tamanho - tamanhoParte * (total - 1);
}

class Impressao {
  /// sha256 (base64) de cada parte, na ordem.
  final List<String> partes;

  /// hex(sha256(concatenação dos sha256 das partes)).
  final String hex;

  final int tamanho;

  const Impressao(this.partes, this.hex, this.tamanho);

  static Impressao dePartesBinarias(List<List<int>> digests, int tamanho) {
    final todos = BytesBuilder(copy: false);
    for (final d in digests) {
      todos.add(d);
    }
    return Impressao(digests.map(base64.encode).toList(), sha256.convert(todos.takeBytes()).toString(), tamanho);
  }

  /// Calcula lendo o arquivo em blocos de 1 MiB (nunca o arquivo inteiro na
  /// memória). Devolve null se o arquivo mudou de tamanho durante a leitura.
  static Future<Impressao?> deArquivo(File f) async {
    final raf = await f.open();
    try {
      final tam = await raf.length();
      final digests = <List<int>>[];
      final n = nPartes(tam);
      for (var p = 1; p <= n; p++) {
        final t = tamanhoDaParte(tam, p);
        final saida = _Coletor();
        final entrada = sha256.startChunkedConversion(saida);
        var lido = 0;
        while (lido < t) {
          final pedaco = await raf.read(t - lido < 1048576 ? t - lido : 1048576);
          if (pedaco.isEmpty) return null;   // encolheu enquanto líamos
          entrada.add(pedaco);
          lido += pedaco.length;
        }
        entrada.close();
        digests.add(saida.valor!.bytes);
      }
      if (await raf.length() != tam) return null;
      return dePartesBinarias(digests, tam);
    } finally {
      await raf.close();
    }
  }

  /// Para bytes em memória (testes e arquivos pequenos).
  static Impressao deBytes(List<int> dados) {
    final digests = <List<int>>[];
    final n = nPartes(dados.length);
    for (var p = 1; p <= n; p++) {
      final ini = (p - 1) * tamanhoParte;
      final fim = ini + tamanhoDaParte(dados.length, p);
      digests.add(sha256.convert(dados.sublist(ini, fim)).bytes);
    }
    return dePartesBinarias(digests, dados.length);
  }
}

class _Coletor implements Sink<Digest> {
  Digest? valor;
  @override
  void add(Digest data) => valor = data;
  @override
  void close() {}
}

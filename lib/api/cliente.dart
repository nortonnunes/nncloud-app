// O cliente da API do app do callcenter (`/v1/callapp/*`).
//
// ⚠️ Toda requisição leva a CHAVE DO COMPUTADOR (`X-NN-Computador`) e, depois do
// login, o TOKEN (`Authorization: Bearer nncall_…`). Os dois moram no chaveiro do
// sistema (ver `Armazenamento`), nunca em arquivo comum.
//
// ⚠️ O keep-alive fica abaixo do do Apache (5 s): reaproveitar uma conexão que o
// servidor já fechou derruba o pedido com "Connection closed" — a lição do NN Cloud.
// Quedas de conexão em pedidos de LEITURA são repetidas na hora; envio nunca.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config.dart';

class ApiErro implements Exception {
  final int status;
  final String mensagem;
  final String codigo;
  const ApiErro(this.status, this.mensagem, [this.codigo = '']);

  /// Sem resposta do servidor (rede, DNS, tempo esgotado).
  bool get semRede => status == 0;

  /// O app volta para o login.
  bool get sessaoAcabou => codigo == 'sessao_invalida' || codigo == 'sessao_expirada';

  /// O app volta para a tela do computador (pedir autorização de novo).
  bool get computadorFora =>
      codigo == 'computador_desconhecido' || codigo == 'computador_recusado' || codigo == 'computador_revogado' || codigo == 'computador_pendente';

  @override
  String toString() => mensagem;
}

class Api {
  final String base;
  String? chave;
  String? token;
  late final http.Client _http;

  /// Chamado quando a sessão ou o computador deixam de valer (o app troca de tela).
  void Function(ApiErro e)? aoPerderAcesso;

  Api({String? base, this.chave, this.token, http.Client? cliente}) : base = base ?? AppConfig.api {
    _http = cliente ??
        IOClient(HttpClient()
          ..connectionTimeout = const Duration(seconds: 10)
          ..idleTimeout = const Duration(seconds: 3)
          ..userAgent = 'ConectaCallcenter/${AppConfig.versao} (${AppConfig.so})');
  }

  Map<String, String> cabecalhos({bool json = false}) => {
        if (chave != null && chave!.isNotEmpty) 'X-NN-Computador': chave!,
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        'X-NN-App-Versao': AppConfig.versao,
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
      };

  Uri uri(String caminho, [Map<String, String>? q]) {
    final c = caminho.startsWith('/') ? caminho : '/$caminho';
    final u = Uri.parse('$base$c');
    return q == null || q.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  Future<dynamic> get(String caminho, {Map<String, String>? q}) =>
      _pedir(() => _http.get(uri(caminho, q), headers: cabecalhos()).timeout(const Duration(seconds: 30)), repetivel: true);

  Future<dynamic> post(String caminho, [Map<String, dynamic>? corpo]) => _pedir(
      () => _http.post(uri(caminho), headers: cabecalhos(json: true), body: jsonEncode(corpo ?? {})).timeout(const Duration(seconds: 30)));

  Future<dynamic> delete(String caminho) =>
      _pedir(() => _http.delete(uri(caminho), headers: cabecalhos()).timeout(const Duration(seconds: 30)));

  /// Envio com arquivos (multipart). `arquivos` = campo → caminhos.
  Future<dynamic> multipart(String caminho, Map<String, String> campos, Map<String, List<File>> arquivos,
      {void Function(int enviado, int total)? progresso}) async {
    final req = http.MultipartRequest('POST', uri(caminho))
      ..headers.addAll(cabecalhos())
      ..fields.addAll(campos);
    for (final e in arquivos.entries) {
      for (final f in e.value) {
        req.files.add(await http.MultipartFile.fromPath(e.key, f.path, filename: f.uri.pathSegments.last));
      }
    }
    return _pedir(() async {
      final r = await _http.send(req).timeout(const Duration(minutes: 5));
      return http.Response.fromStream(r);
    });
  }

  /// Baixa um endereço da API para um arquivo (com a chave e o token).
  Future<File> baixar(String caminhoOuUrl, File destino, {void Function(int recebido, int? total)? progresso}) async {
    final u = caminhoOuUrl.startsWith('http') ? Uri.parse(caminhoOuUrl) : uri(caminhoOuUrl);
    final req = http.Request('GET', u)..headers.addAll(cabecalhos());
    final http.StreamedResponse r;
    try {
      r = await _http.send(req).timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      throw ApiErro(0, 'Sem conexão com o servidor ($e).');
    }
    if (r.statusCode != 200) {
      final corpo = await r.stream.bytesToString();
      throw _erro(r.statusCode, corpo);
    }
    destino.parent.createSync(recursive: true);
    final tmp = File('${destino.path}.parcial');
    final sink = tmp.openWrite();
    var recebido = 0;
    try {
      await for (final pedaco in r.stream.timeout(const Duration(seconds: 60))) {
        sink.add(pedaco);
        recebido += pedaco.length;
        progresso?.call(recebido, r.contentLength);
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      if (tmp.existsSync()) tmp.deleteSync();
      throw ApiErro(0, 'O download foi interrompido ($e).');
    }
    if (destino.existsSync()) destino.deleteSync();
    return tmp.renameSync(destino.path);
  }

  /// Bytes de uma imagem da API (miniaturas, NN News) — com a chave e o token.
  Future<List<int>> bytes(String caminhoOuUrl) async {
    final u = caminhoOuUrl.startsWith('http') ? Uri.parse(caminhoOuUrl) : uri(caminhoOuUrl);
    final r = await _http.get(u, headers: cabecalhos()).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw _erro(r.statusCode, r.body);
    return r.bodyBytes;
  }

  Future<dynamic> _pedir(Future<http.Response> Function() fazer, {bool repetivel = false}) async {
    http.Response r;
    var tentativa = 0;
    while (true) {
      try {
        r = await fazer();
        break;
      } on Object catch (e) {
        final queda = e is SocketException || e is http.ClientException || e is HttpException;
        if (repetivel && queda && tentativa < 2) {
          tentativa++;
          await Future<void>.delayed(Duration(milliseconds: tentativa == 1 ? 300 : 1500));
          continue;
        }
        if (e is TimeoutException) throw const ApiErro(0, 'O servidor demorou a responder. Tente de novo.');
        throw ApiErro(0, 'Sem conexão com o servidor. Confira a internet.');
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        return j is Map && j.containsKey('data') ? j['data'] : j;
      } catch (_) {
        throw ApiErro(r.statusCode, 'Resposta inesperada do servidor.');
      }
    }
    final e = _erro(r.statusCode, utf8.decode(r.bodyBytes, allowMalformed: true));
    if (e.sessaoAcabou || e.computadorFora) aoPerderAcesso?.call(e);
    throw e;
  }

  ApiErro _erro(int status, String corpo) {
    try {
      final j = jsonDecode(corpo);
      final er = j is Map ? j['error'] : null;
      if (er is Map) {
        return ApiErro(status, (er['message'] ?? 'Erro $status').toString(), (er['code'] ?? '').toString());
      }
    } catch (_) {}
    return ApiErro(status, switch (status) {
      413 => 'O arquivo passou do limite do servidor.',
      429 => 'Muitas tentativas. Espere um pouco.',
      >= 500 => 'O servidor não conseguiu processar agora. Tente de novo.',
      _ => 'Erro $status.',
    });
  }

  void fechar() => _http.close();
}

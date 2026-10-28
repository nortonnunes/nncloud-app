// Cliente da API `/v1/cloud` do NN Conecta (só `dart:io`, sem pacote http).
//
// ⚠️ A resposta vem em `{"data": …}` e o erro em `{"error": {"status", "message"}}`.
// ⚠️ O token (`nncl_…`) só é guardado por quem usa o motor (o aplicativo o põe
// no chaveiro do sistema); aqui ele só viaja no cabeçalho.
// ⚠️ O Dart ignora o proxy do sistema: `proxy` vem das configurações do app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiErro implements Exception {
  final int status;
  final String mensagem;
  const ApiErro(this.status, this.mensagem);

  /// Sem rede, servidor fora ou tempo esgotado: tentar de novo mais tarde.
  bool get transitorio => status == 0 || status == 429 || status >= 500;

  /// O computador foi desconectado (ou o token não vale mais).
  bool get desconectado => status == 401;

  @override
  String toString() => 'ApiErro($status): $mensagem';
}

class Api {
  final String base;            // ex.: https://api.nortonnunes.com.br
  String? token;
  final String? proxy;          // "host:porta"
  final String versaoApp;
  final HttpClient _http;

  Api(this.base, {this.token, this.proxy, this.versaoApp = '1.0.0', HttpClient? http})
      : _http = http ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 20);
    _http.idleTimeout = const Duration(seconds: 30);
    _http.userAgent = 'NN Cloud/$versaoApp (${Platform.operatingSystem})';
    if (proxy != null && proxy!.isNotEmpty) {
      _http.findProxy = (_) => 'PROXY $proxy';
    }
  }

  void fechar() => _http.close(force: true);

  Future<dynamic> pedir(String metodo, String caminho, {Map<String, dynamic>? corpo, Map<String, String>? query,
      Duration tempo = const Duration(seconds: 60)}) async {
    var uri = Uri.parse('$base/v1/cloud/$caminho');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    try {
      final req = await _http.openUrl(metodo, uri).timeout(tempo);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (corpo != null) {
        final b = utf8.encode(jsonEncode(corpo));
        req.headers.contentType = ContentType.json;
        req.contentLength = b.length;
        req.add(b);
      }
      final res = await req.close().timeout(tempo);
      final txt = await res.transform(utf8.decoder).join().timeout(tempo);
      dynamic j;
      try {
        j = txt.isEmpty ? null : jsonDecode(txt);
      } catch (_) {
        j = null;
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (j is Map && j.containsKey('data')) return j['data'];
        throw ApiErro(502, 'Resposta inesperada do servidor.');
      }
      final msg = j is Map && j['error'] is Map ? (j['error']['message'] ?? '').toString() : '';
      throw ApiErro(res.statusCode, msg.isNotEmpty ? msg : 'O servidor respondeu ${res.statusCode}.');
    } on ApiErro {
      rethrow;
    } on TimeoutException {
      throw const ApiErro(0, 'O servidor demorou demais para responder.');
    } on SocketException catch (e) {
      throw ApiErro(0, 'Sem conexão com o servidor (${e.osError?.message ?? e.message}).');
    } on HandshakeException {
      throw const ApiErro(0, 'Não foi possível estabelecer uma conexão segura com o servidor.');
    } on HttpException catch (e) {
      throw ApiErro(0, 'A conexão caiu (${e.message}).');
    }
  }

  Future<Map<String, dynamic>> _m(String metodo, String caminho, {Map<String, dynamic>? corpo, Map<String, String>? query}) async =>
      ((await pedir(metodo, caminho, corpo: corpo, query: query)) as Map).cast<String, dynamic>();

  // ---------- Conexão ----------
  Future<Map<String, dynamic>> conectar(String computador, String plataforma) =>
      _m('POST', 'conectar', corpo: {'computador': computador, 'plataforma': plataforma, 'versao': versaoApp});
  Future<Map<String, dynamic>> buscarToken(String segredo) => _m('POST', 'token', corpo: {'segredo': segredo});
  Future<Map<String, dynamic>> eu() => _m('GET', 'eu', query: {'versao': versaoApp});
  Future<void> desconectar() => _m('POST', 'desconectar');

  // ---------- Espaços e pastas ----------
  Future<List<Map<String, dynamic>>> espacos() async =>
      ((await _m('GET', 'espacos'))['espacos'] as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> pastas({int? espacoId, int? pastaId}) =>
      _m('GET', 'pastas', query: {if (espacoId != null) 'espaco_id': '$espacoId', if (pastaId != null) 'pasta_id': '$pastaId'});
  Future<Map<String, dynamic>> criarPasta({int? espacoId, int? pastaId, required String nome}) =>
      _m('POST', 'pastas', corpo: {'espaco_id': espacoId, 'pasta_id': pastaId, 'nome': nome});
  Future<Map<String, dynamic>> garantir({int? espacoId, int? pastaId, required List<String> caminhos}) =>
      _m('POST', 'pastas/garantir', corpo: {'espaco_id': espacoId, 'pasta_id': pastaId, 'caminhos': caminhos});

  // ---------- Pares ----------
  Future<List<Map<String, dynamic>>> pares() async =>
      ((await _m('GET', 'sincronizacoes'))['pares'] as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> criarPar({required int espacoId, int? raizId, required String caminhoLocal, required String nome}) async =>
      ((await _m('POST', 'sincronizacoes', corpo: {'espaco_id': espacoId, 'raiz_id': raizId, 'caminho_local': caminhoLocal, 'nome': nome}))['par'] as Map)
          .cast<String, dynamic>();
  Future<void> atualizarPar(int par, Map<String, dynamic> d) => _m('POST', 'sincronizacoes/$par', corpo: d);
  Future<void> removerPar(int par) => _m('DELETE', 'sincronizacoes/$par');
  Future<Map<String, dynamic>> baseDoPar(int par, int depoisDe) =>
      _m('GET', 'sincronizacoes/$par/base', query: {'depois_de': '$depoisDe', 'limite': '1000'});
  Future<void> gravarBase(int par, List<Map<String, dynamic>> linhas, List<int> remover, {int? cursor}) =>
      _m('POST', 'sincronizacoes/$par/base', corpo: {'linhas': linhas, 'remover': remover, if (cursor != null) 'cursor': cursor});
  Future<void> gravarHistorico(List<Map<String, dynamic>> linhas) => _m('POST', 'historico', corpo: {'linhas': linhas});

  // ---------- Árvore e mudanças ----------
  Future<Map<String, dynamic>> arvore(int par, int depoisDe) =>
      _m('GET', 'arvore', query: {'par': '$par', 'depois_de': '$depoisDe', 'limite': '1000'});
  Future<List<Map<String, dynamic>>> mudancas(List<Map<String, dynamic>> pares) async =>
      ((await _m('POST', 'mudancas', corpo: {'pares': pares}))['pares'] as List).cast<Map<String, dynamic>>();

  // ---------- Itens ----------
  Future<Map<String, dynamic>> renomear(int id, String nome) async =>
      ((await _m('POST', 'itens/$id/renomear', corpo: {'nome': nome}))['item'] as Map).cast<String, dynamic>();
  Future<Map<String, dynamic>> mover(int id, {int? espacoId, int? pastaId}) async =>
      ((await _m('POST', 'itens/$id/mover', corpo: {'espaco_id': espacoId, 'pasta_id': pastaId}))['item'] as Map).cast<String, dynamic>();
  Future<List<Map<String, dynamic>>> lixeira(List<int> ids, {bool confirmado = false}) async =>
      ((await _m('POST', 'itens/lixeira', corpo: {'ids': ids, 'confirmado': confirmado ? 1 : 0}))['itens'] as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> baixar(int id) => _m('GET', 'itens/$id/baixar');

  // ---------- Envios ----------
  Future<Map<String, dynamic>> iniciarEnvio(Map<String, dynamic> d) => _m('POST', 'envios', corpo: d);
  Future<Map<String, dynamic>> estadoEnvio(String id, {int de = 1}) => _m('GET', 'envios/$id', query: {'de': '$de'});
  Future<Map<String, dynamic>> concluirEnvio(String id) => _m('POST', 'envios/$id/concluir');
  Future<void> cancelarEnvio(String id) => _m('DELETE', 'envios/$id');

  /// PUT de uma parte direto no S3 (URL assinada). Content-Length EXATO — ele
  /// faz parte da assinatura. Devolve o status HTTP (0 = rede).
  Future<int> putParte(String url, Map<String, String> cabecalhos, Stream<List<int>> corpo, int tamanho) async {
    try {
      final req = await _http.putUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
      req.headers.contentType = ContentType('application', 'octet-stream');
      req.contentLength = tamanho;
      cabecalhos.forEach((k, v) {
        if (k.toLowerCase() != 'content-length') req.headers.set(k, v);
      });
      await req.addStream(corpo);
      final res = await req.close().timeout(const Duration(minutes: 10));
      await res.drain<void>();
      return res.statusCode;
    } on TimeoutException {
      return 0;
    } on SocketException {
      return 0;
    } on HttpException {
      return 0;
    }
  }

  /// GET de um arquivo direto do S3 para um arquivo local (com Range para retomar).
  Future<int> baixarPara(String url, IOSink destino, {int inicio = 0, void Function(int)? aoReceber}) async {
    try {
      final req = await _http.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (inicio > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$inicio-');
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.drain<void>();
        return res.statusCode;
      }
      await for (final b in res.timeout(const Duration(seconds: 90))) {
        destino.add(b);
        aoReceber?.call(b.length);
      }
      return res.statusCode;
    } on TimeoutException {
      return 0;
    } on SocketException {
      return 0;
    } on HttpException {
      return 0;
    }
  }
}

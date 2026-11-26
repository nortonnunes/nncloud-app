// O Atendimento do Tele Atendimento pela API do app (`/v1/callapp/atendimento/*`).
//
// ⚠️ As AÇÕES são as do portal (o servidor herda o `AtendimentoAcaoController`):
// mandam os MESMOS campos dos formulários de lá, em formulário (multipart), e
// respondem `{ok, id, aba, success, error}` — o contrato da Mesa. A aba de
// volta é decidida pelo servidor, por ação; o app só obedece.
import 'dart:io';

import '../../api/cliente.dart';

/// O resultado de uma ação da ficha.
class RespostaAcao {
  final bool ok;
  final String aba;
  final String? mensagem;
  const RespostaAcao(this.ok, this.aba, this.mensagem);

  factory RespostaAcao.de(dynamic r) {
    final m = r is Map ? r : const {};
    final ok = m['ok'] == true;
    return RespostaAcao(ok, (m['aba'] ?? '').toString(),
        (ok ? m['success'] : m['error'])?.toString());
  }
}

class AtendimentoApi {
  final Api api;
  const AtendimentoApi(this.api);

  static const _b = '/v1/callapp/atendimento';

  Future<Map<String, dynamic>> busca(String q, {int page = 1}) async =>
      _mapa(await api.get('$_b/busca', q: {'q': q, 'page': '$page'}));

  Future<List<Map<String, dynamic>>> sugestoes(String q) async {
    final r = _mapa(await api.get('$_b/sugestoes', q: {'q': q}));
    return ((r['itens'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> ficha(int id, String aba,
          {String classe = '', bool meus = false}) async =>
      _mapa(await api.get('$_b/ficha', q: {
        'id': '$id',
        'aba': aba,
        if (classe.isNotEmpty) 'classe': classe,
        if (meus) 'meus': '1',
      }));

  /// Uma ação da ficha. `caminho` é o do portal (`/acionamento`, `/agenda/status`…).
  Future<RespostaAcao> acao(String caminho, Map<String, String> campos,
      {File? arquivo, String query = ''}) async {
    final r = await api.multipart(
        '$_b$caminho$query',
        campos,
        arquivo != null
            ? {
                'arquivo': [arquivo]
              }
            : const {});
    return RespostaAcao.de(r);
  }

  /// O documento anexado, gravado em `destino`.
  Future<File> baixarDocumento(int id, int doc, File destino) =>
      api.baixar('$_b/documento?id=$id&doc=$doc', destino);

  /// O endereço de um CEP (logradouro, bairro, cidade, uf) — nulo se não achou.
  Future<Map<String, dynamic>?> cep(String cep) async {
    try {
      return _mapa(await api.get('/v1/callapp/cep', q: {'cep': cep}));
    } on ApiErro catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  static Map<String, dynamic> _mapa(dynamic r) =>
      r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
}

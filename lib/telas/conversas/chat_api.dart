// O chat do app: os modelos (conversa, mensagem, anexo, enquete) e as chamadas
// a `/v1/conversas/chat/*` — o MESMO `ChatController` do app do celular, com as
// regras do chat do site (formatação, grupos, encaminhar, enquetes).
//
// ⚠️ Os endereços de anexo vêm prontos do servidor (`/v1/conversas/chat/attachment?a=`)
// e exigem o token da sessão: passam sempre pela `Api`.
import 'dart:io';

import '../../api/cliente.dart';

const _base = '/v1/conversas/chat';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(Object? v) => v == null ? '' : v.toString();
List<Map<String, dynamic>> _lista(Object? v) =>
    v is List ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : const [];

/// "Fulano" → "fulano"; tira acento para a busca (o site busca sem acento).
String semAcento(String s) {
  const de = 'áàâãäåéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const pa = 'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = de.indexOf(ch);
    b.write(i >= 0 ? pa[i] : ch);
  }
  return b.toString().toLowerCase();
}

class StatusContato {
  final String codigo, rotulo, texto, mensagem;
  final bool online;
  const StatusContato({required this.codigo, required this.rotulo, required this.texto, required this.mensagem, required this.online});
  static StatusContato? de(Object? v) {
    if (v is! Map) return null;
    return StatusContato(
      codigo: _str(v['codigo']),
      rotulo: _str(v['rotulo']),
      texto: _str(v['texto']),
      mensagem: _str(v['mensagem']),
      online: v['online'] == true,
    );
  }

  /// O aviso colado no compositor ("… A resposta pode demorar.") — quando a
  /// pessoa escolheu um status que não é "Disponível".
  bool get avisa => codigo.isNotEmpty && codigo != 'disponivel' && codigo != 'offline';
}

class Conversa {
  final int id;
  String titulo;
  final String tipo;
  String previa;
  int naoLidas;
  bool favorita;
  bool arquivada;
  String? avatar;
  String atualizada;
  StatusContato? status;

  Conversa({
    required this.id,
    required this.titulo,
    required this.tipo,
    this.previa = '',
    this.naoLidas = 0,
    this.favorita = false,
    this.arquivada = false,
    this.avatar,
    this.atualizada = '',
    this.status,
  });

  bool get grupo => tipo == 'group';

  factory Conversa.de(Map<String, dynamic> m) => Conversa(
        id: _int(m['id']),
        titulo: _str(m['title']).isEmpty ? 'Conversa' : _str(m['title']),
        tipo: _str(m['type']),
        previa: _str(m['preview']),
        naoLidas: _int(m['unread']),
        favorita: m['is_favorite'] == true,
        arquivada: m['is_archived'] == true,
        avatar: (m['avatar'] ?? '').toString().isEmpty ? null : m['avatar'].toString(),
        atualizada: _str(m['updated_at']),
        status: StatusContato.de(m['status']),
      );
}

class Anexo {
  final int id;
  final String nome, mime, url;
  final String? miniatura;
  final int tamanho;
  final bool imagem, audio;
  const Anexo({required this.id, required this.nome, required this.mime, required this.url, this.miniatura, this.tamanho = 0, this.imagem = false, this.audio = false});

  factory Anexo.de(Map<String, dynamic> m) => Anexo(
        id: _int(m['id']),
        nome: _str(m['name']).isEmpty ? 'arquivo' : _str(m['name']),
        mime: _str(m['mime']),
        url: _str(m['url']),
        miniatura: (m['thumb_url'] ?? '').toString().isEmpty ? null : m['thumb_url'].toString(),
        tamanho: _int(m['size']),
        imagem: m['is_image'] == true,
        audio: m['is_audio'] == true,
      );
}

String tamanhoLegivel(int b) {
  if (b <= 0) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

class Reacao {
  final String emoji;
  final int total;
  final bool minha;
  final List<String> quem;
  const Reacao(this.emoji, this.total, this.minha, this.quem);
  static List<Reacao> lista(Object? v) => _lista(v)
      .map((r) => Reacao(_str(r['emoji']), _int(r['count']), r['mine'] == true, (r['users'] is List ? (r['users'] as List).map((e) => '$e').toList() : const <String>[])))
      .toList();
}

class OpcaoEnquete {
  final int id, votos;
  final String texto;
  final bool minha;
  const OpcaoEnquete(this.id, this.texto, this.votos, this.minha);
}

class Enquete {
  final int id, autorId, total;
  final String pergunta;
  final bool multi, encerrada, votou;
  final List<OpcaoEnquete> opcoes;
  const Enquete({required this.id, required this.autorId, required this.total, required this.pergunta, required this.multi, required this.encerrada, required this.votou, required this.opcoes});

  static Enquete? de(Object? v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    return Enquete(
      id: _int(m['id']),
      autorId: _int(m['author_id']),
      total: _int(m['total']),
      pergunta: _str(m['question']),
      multi: m['multi'] == true || m['multi'] == 1,
      encerrada: m['closed'] == true || m['closed'] == 1,
      votou: m['voted'] == true,
      opcoes: _lista(m['options']).map((o) => OpcaoEnquete(_int(o['id']), _str(o['text']), _int(o['votes']), o['mine'] == true)).toList(),
    );
  }
}

class Resposta {
  final int id;
  final String autor, texto;
  const Resposta(this.id, this.autor, this.texto);
}

class Mensagem {
  final int id;
  final int? autorId;
  final String autor, quando, criada;
  final String? avatar;
  final bool minha, editada, encaminhada, podeEditar, mencionaMim;
  final String corpo;          // texto puro
  final String? html;          // o HTML permitido (mensagem formatada)
  final int ts;
  final List<Anexo> anexos;
  final Resposta? resposta;
  List<Reacao> reacoes;
  Enquete? enquete;
  final List<String> mencoes;

  Mensagem({
    required this.id,
    required this.autorId,
    required this.autor,
    required this.quando,
    required this.criada,
    required this.avatar,
    required this.minha,
    required this.editada,
    required this.encaminhada,
    required this.podeEditar,
    required this.mencionaMim,
    required this.corpo,
    required this.html,
    required this.ts,
    required this.anexos,
    required this.resposta,
    required this.reacoes,
    required this.enquete,
    required this.mencoes,
  });

  factory Mensagem.de(Map<String, dynamic> m) {
    final r = m['reply'];
    return Mensagem(
      id: _int(m['id']),
      autorId: m['user_id'] == null ? null : _int(m['user_id']),
      autor: _str(m['user_name']).isEmpty ? 'Usuário removido' : _str(m['user_name']),
      quando: _str(m['at']),
      criada: _str(m['created_at']),
      avatar: (m['avatar'] ?? '').toString().isEmpty ? null : m['avatar'].toString(),
      minha: m['mine'] == true,
      editada: m['edited'] == true,
      encaminhada: m['forwarded'] == true,
      podeEditar: m['can_edit'] == true,
      mencionaMim: m['mentions_me'] == true,
      corpo: _str(m['body']),
      html: (m['body_html'] ?? '').toString().isEmpty ? null : m['body_html'].toString(),
      ts: _int(m['ts']),
      anexos: _lista(m['attachments']).map(Anexo.de).toList(),
      resposta: r is Map ? Resposta(_int(r['id']), _str(r['author']), _str(r['text'])) : null,
      reacoes: Reacao.lista(m['reactions']),
      enquete: Enquete.de(m['poll']),
      mencoes: _lista(m['mentions']).map((x) => _str(x['name'])).toList(),
    );
  }

  /// Dia da mensagem (para os divisores), pela data que o SERVIDOR formatou —
  /// a mesma que aparece na bolha (regra do site: divisor e hora não se contradizem).
  String get dia {
    final p = quando.split(' ');
    return p.isNotEmpty ? p.first : '';
  }

  String get hora {
    final p = quando.split(' ');
    return p.length > 1 ? p[1] : '';
  }

  /// A janela de edição (15 min), conferida de novo no servidor ao salvar.
  bool get aindaEditavel => podeEditar && minha && enquete == null && (DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts) < 15 * 60;
}

class Participante {
  final int id;
  final String nome;
  const Participante(this.id, this.nome);
}

/// Estado de leitura de cada participante (os tiques).
class EstadoLeitura {
  final Map<int, (int lida, int entregue, String nome)> porPessoa;
  const EstadoLeitura(this.porPessoa);
  static const vazio = EstadoLeitura({});

  static EstadoLeitura de(Object? v) {
    if (v is! Map) return vazio;
    final out = <int, (int, int, String)>{};
    for (final p in _lista(v['participants'])) {
      out[_int(p['user_id'])] = (_int(p['last_read_message_id']), _int(p['last_delivered_message_id']), _str(p['user_name']));
    }
    return EstadoLeitura(out);
  }

  /// 0 enviada · 1 entregue a todos · 2 lida por todos.
  int tique(int msgId, int eu) {
    final outros = porPessoa.entries.where((e) => e.key != eu).map((e) => e.value).toList();
    if (outros.isEmpty) return 0;
    if (outros.every((o) => o.$1 >= msgId)) return 2;
    if (outros.every((o) => o.$2 >= msgId || o.$1 >= msgId)) return 1;
    return 0;
  }
}

class ChatApi {
  final Api api;
  const ChatApi(this.api);

  Future<List<Conversa>> conversas({bool arquivadas = false}) async {
    final r = await api.get('$_base/conversations', q: arquivadas ? {'archived': '1'} : null);
    return _lista(r).map(Conversa.de).toList();
  }

  Future<Map<String, dynamic>> mensagens(int id, {int after = 0, int before = 0}) async {
    final q = <String, String>{};
    if (after > 0) q['after'] = '$after';
    if (before > 0) q['before'] = '$before';
    final r = await api.get('$_base/conversations/$id', q: q);
    return (r as Map).cast<String, dynamic>();
  }

  Future<Mensagem> enviar(int id, {required String corpo, required bool html, int? responderA, List<File> arquivos = const []}) async {
    final campos = <String, String>{
      'body': corpo,
      if (html) 'format': 'html',
      if (responderA != null && responderA > 0) 'reply_to': '$responderA',
    };
    final r = arquivos.isEmpty
        ? await api.post('$_base/conversations/$id/messages', campos)
        : await api.multipart('$_base/conversations/$id/messages', campos, {'attachment[]': arquivos});
    return Mensagem.de((r as Map).cast<String, dynamic>());
  }

  Future<Mensagem> editar(int msgId, String corpo, bool html) async {
    final r = await api.post('$_base/message/edit', {'message_id': msgId, 'body': corpo, if (html) 'format': 'html'});
    return Mensagem.de((r as Map).cast<String, dynamic>());
  }

  Future<List<Reacao>> reagir(int msgId, String emoji) async {
    final r = await api.post('$_base/react', {'message_id': msgId, 'emoji': emoji});
    return Reacao.lista((r as Map)['reactions']);
  }

  Future<Map<String, dynamic>> leituras(int msgId) async =>
      ((await api.get('$_base/message/reads', q: {'id': '$msgId'})) as Map).cast<String, dynamic>();

  Future<void> digitando(int id) => api.post('$_base/conversations/$id/typing');

  Future<bool> favoritar(int id) async => ((await api.post('$_base/conversations/$id/favorite')) as Map)['favorite'] == true;
  Future<bool> arquivar(int id) async => ((await api.post('$_base/conversations/$id/archive')) as Map)['archived'] == true;
  Future<void> ordemFavoritos(List<int> ids) => api.post('$_base/favorites/order', {'ids': ids});

  /// Todos com quem dá para conversar (sem operadora — a lista do site).
  Future<List<Map<String, dynamic>>> usuarios() async => _lista(await api.get('$_base/users'));

  Future<List<Map<String, dynamic>>> contatos(String q) async => _lista(await api.get('$_base/contatos', q: {'q': q}));

  Future<int> direta(int userId) async => _int(((await api.post('$_base/direct', {'user_id': userId})) as Map)['id']);

  Future<int> grupo(String nome, List<int> membros) async =>
      _int(((await api.post('$_base/group', {'name': nome, 'members': membros})) as Map)['id']);

  Future<Map<String, dynamic>> membros(int id) async => ((await api.get('$_base/conversations/$id/members')) as Map).cast<String, dynamic>();
  Future<void> definirMembros(int id, List<int> membros, List<int> admins) =>
      api.post('$_base/conversations/$id/members', {'members': membros, 'admins': admins});
  Future<void> renomear(int id, String nome) => api.post('$_base/conversations/$id/rename', {'name': nome});
  Future<void> sair(int id) => api.post('$_base/conversations/$id/leave');
  Future<void> excluir(int id) => api.delete('$_base/conversations/$id');
  Future<String?> fotoGrupo(int id, File f) async {
    final r = await api.multipart('$_base/conversations/$id/avatar', const {}, {'avatar': [f]});
    return (r as Map)['avatar']?.toString();
  }

  Future<List<Map<String, dynamic>>> arquivos(int id) async => _lista(await api.get('$_base/conversations/$id/files'));

  Future<Map<String, dynamic>> encaminhar(List<int> mensagens, List<String> destinos) async =>
      ((await api.post('$_base/encaminhar', {'mensagens': mensagens, 'destinos': destinos})) as Map).cast<String, dynamic>();

  Future<void> criarEnquete(int id, String pergunta, List<String> opcoes, bool multi) =>
      api.post('$_base/conversations/$id/poll', {'question': pergunta, 'options': opcoes, 'multi': multi});
  Future<Enquete?> votar(int pollId, int opcaoId) async => Enquete.de(((await api.post('$_base/poll/vote', {'poll_id': pollId, 'option_id': opcaoId})) as Map)['poll']);
  Future<Enquete?> encerrarEnquete(int pollId) async => Enquete.de(((await api.post('$_base/poll/close', {'poll_id': pollId})) as Map)['poll']);
  Future<Map<String, dynamic>> votos(int pollId) async => ((await api.get('$_base/poll/voters', q: {'poll_id': '$pollId'})) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> socket() async => ((await api.get('$_base/socket')) as Map).cast<String, dynamic>();
  Future<String> socketAuth(String socketId, String canal) async =>
      _str(((await api.post('$_base/socket-auth', {'socket_id': socketId, 'channel_name': canal})) as Map)['auth']);
}

/// Erro do servidor em português (ou o genérico).
String erroChat(Object e) => e is ApiErro ? e.mensagem : 'Não foi possível agora. Tente de novo.';

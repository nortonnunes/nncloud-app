// As janelas do chat: nova conversa, novo grupo, gerenciar o grupo, encaminhar,
// nova enquete, quem votou, quem leu, os arquivos da conversa e as reuniões do Meet.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/cliente.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import 'chat_api.dart';
import 'mensagem.dart';

/// Escolher pessoas (com busca). Usado no novo grupo, nos membros e no encaminhar.
class _ListaPessoas extends StatefulWidget {
  final List<Map<String, dynamic>> pessoas;
  final Set<int> marcados;
  final bool unica;
  final void Function(int id) alternar;
  final Set<int>? admins;
  final void Function(int id)? alternarAdmin;
  const _ListaPessoas({required this.pessoas, required this.marcados, required this.alternar, this.unica = false, this.admins, this.alternarAdmin});
  @override
  State<_ListaPessoas> createState() => _ListaPessoasState();
}

class _ListaPessoasState extends State<_ListaPessoas> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final q = semAcento(_q.trim());
    final lista = widget.pessoas.where((x) => q.isEmpty || semAcento('${x['name']} ${x['email'] ?? ''}').contains(q)).toList();
    return Column(children: [
      TextField(
        autofocus: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar pelo nome'),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: lista.isEmpty
            ? const Vazio(Icons.person_search_outlined, 'Ninguém encontrado.')
            : ListView.builder(
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final x = lista[i];
                  final id = (x['id'] as num).toInt();
                  final marcado = widget.marcados.contains(id);
                  return ListTile(
                    dense: true,
                    leading: Avatar(url: x['avatar']?.toString(), nome: '${x['name']}', tam: 32),
                    title: Text('${x['name']}'),
                    onTap: () => setState(() => widget.alternar(id)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.alternarAdmin != null && marcado)
                        TextButton(
                          onPressed: () => setState(() => widget.alternarAdmin!(id)),
                          child: Text(widget.admins!.contains(id) ? 'Administrador' : 'Tornar admin',
                              style: TextStyle(color: widget.admins!.contains(id) ? p.primary : p.muted, fontSize: 12.5)),
                        ),
                      widget.unica
                          ? Icon(Icons.chevron_right_rounded, color: p.muted)
                          : Checkbox(value: marcado, onChanged: (_) => setState(() => widget.alternar(id))),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

Future<List<Map<String, dynamic>>> _pessoas(ChatApi chat) async {
  try {
    return await chat.usuarios();
  } catch (_) {
    return [];
  }
}

/// Nova conversa direta: devolve o id da conversa.
Future<int?> novaConversa(BuildContext context, ChatApi chat) async {
  final pessoas = await _pessoas(chat);
  if (!context.mounted) return null;
  final escolhido = await showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Nova conversa'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: _ListaPessoas(pessoas: pessoas, marcados: const {}, unica: true, alternar: (id) => Navigator.pop(d, id)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar'))],
    ),
  );
  if (escolhido == null) return null;
  try {
    return await chat.direta(escolhido);
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return null;
  }
}

/// Novo grupo: nome + membros. Devolve o id.
Future<int?> novoGrupo(BuildContext context, ChatApi chat) async {
  final pessoas = await _pessoas(chat);
  if (!context.mounted) return null;
  final nome = TextEditingController();
  final marcados = <int>{};
  final r = await showDialog<int>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, set) {
      return AlertDialog(
        title: const Text('Novo grupo'),
        content: SizedBox(
          width: 480,
          height: 540,
          child: Column(children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome do grupo'), maxLength: 160),
            Align(alignment: Alignment.centerLeft, child: Text('${marcados.length} selecionado(s)', style: TextStyle(color: d.pal.muted, fontSize: 12.5))),
            const SizedBox(height: 6),
            Expanded(child: _ListaPessoas(pessoas: pessoas, marcados: marcados, alternar: (id) => set(() => marcados.contains(id) ? marcados.remove(id) : marcados.add(id)))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (nome.text.trim().isEmpty || marcados.isEmpty) {
                avisar(d, 'Dê um nome e escolha ao menos uma pessoa.', erro: true);
                return;
              }
              try {
                final id = await chat.grupo(nome.text.trim(), marcados.toList());
                if (d.mounted) Navigator.pop(d, id);
              } catch (e) {
                if (d.mounted) avisar(d, erroChat(e), erro: true);
              }
            },
            child: const Text('Criar grupo'),
          ),
        ],
      );
    }),
  );
  nome.dispose();
  return r;
}

/// Gerenciar o grupo: nome, foto, membros e administradores. Devolve true se mudou.
Future<bool> gerenciarGrupo(BuildContext context, ChatApi chat, int id, {required bool souAdmin, required int meuId}) async {
  Map<String, dynamic> info;
  try {
    info = await chat.membros(id);
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return false;
  }
  final pessoas = await _pessoas(chat);
  if (!context.mounted) return false;
  final membros = <int>{for (final x in (info['participants'] as List? ?? [])) (x['id'] as num).toInt()};
  final admins = <int>{for (final x in (info['admin_ids'] as List? ?? [])) (x as num).toInt()};
  // quem já está no grupo e não aparece na lista do chat (ex.: conta desativada) continua listado
  final todos = [...pessoas];
  for (final x in (info['participants'] as List? ?? [])) {
    final pid = (x['id'] as num).toInt();
    if (pid != meuId && !todos.any((t) => (t['id'] as num).toInt() == pid)) todos.add({'id': pid, 'name': x['name']});
  }
  todos.removeWhere((t) => (t['id'] as num).toInt() == meuId);
  final nome = TextEditingController(text: (info['name'] ?? '').toString());
  var mudou = false;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, set) {
      return AlertDialog(
        title: const Text('Grupo'),
        content: SizedBox(
          width: 520,
          height: 580,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(controller: nome, enabled: souAdmin, decoration: const InputDecoration(labelText: 'Nome do grupo'))),
              if (souAdmin) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
                    final caminho = r?.files.single.path;
                    if (caminho == null) return;
                    try {
                      await chat.fotoGrupo(id, File(caminho));
                      mudou = true;
                      if (d.mounted) avisar(d, 'Foto do grupo trocada.');
                    } catch (e) {
                      if (d.mounted) avisar(d, erroChat(e), erro: true);
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Foto'),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Text(souAdmin ? 'Membros (${membros.length})' : 'Membros (${membros.length}) — só administradores do grupo mudam a lista',
                style: TextStyle(color: d.pal.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Expanded(
              child: souAdmin
                  ? _ListaPessoas(
                      pessoas: todos,
                      marcados: membros,
                      admins: admins,
                      alternar: (pid) => set(() {
                        if (membros.contains(pid)) {
                          membros.remove(pid);
                          admins.remove(pid);
                        } else {
                          membros.add(pid);
                        }
                      }),
                      alternarAdmin: (pid) => set(() => admins.contains(pid) ? admins.remove(pid) : admins.add(pid)),
                    )
                  : ListView(children: [
                      for (final x in (info['participants'] as List? ?? []))
                        ListTile(
                          dense: true,
                          title: Text('${x['name']}'),
                          trailing: admins.contains((x['id'] as num).toInt()) ? Text('Administrador', style: TextStyle(color: d.pal.primary, fontSize: 12.5)) : null,
                        ),
                    ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(souAdmin ? 'Cancelar' : 'Fechar')),
          if (souAdmin)
            FilledButton(
              onPressed: () async {
                try {
                  if (nome.text.trim().isNotEmpty && nome.text.trim() != (info['name'] ?? '').toString()) {
                    await chat.renomear(id, nome.text.trim());
                  }
                  await chat.definirMembros(id, membros.where((x) => x != meuId).toList(), admins.toList());
                  mudou = true;
                  if (d.mounted) Navigator.pop(d);
                } catch (e) {
                  if (d.mounted) avisar(d, erroChat(e), erro: true);
                }
              },
              child: const Text('Salvar'),
            ),
        ],
      );
    }),
  );
  nome.dispose();
  return mudou;
}

/// Encaminhar: até 10 destinos (conversas recentes ou pessoas). Devolve true se foi.
Future<bool> encaminhar(BuildContext context, ChatApi chat, List<int> mensagens, List<Conversa> recentes) async {
  final pessoas = await _pessoas(chat);
  if (!context.mounted) return false;
  final destinos = <String>{};
  var q = '';
  var foi = false;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, set) {
      final pal = d.pal;
      final busca = semAcento(q.trim());
      final convs = recentes.where((c) => busca.isEmpty || semAcento(c.titulo).contains(busca)).take(30).toList();
      final gente = busca.length < 2 ? <Map<String, dynamic>>[] : pessoas.where((x) => semAcento('${x['name']}').contains(busca)).take(20).toList();
      void alternar(String k) => set(() {
            if (destinos.contains(k)) {
              destinos.remove(k);
            } else if (destinos.length < 10) {
              destinos.add(k);
            } else {
              avisar(d, 'No máximo 10 destinos.', erro: true);
            }
          });
      return AlertDialog(
        title: Text('Encaminhar ${mensagens.length} ${mensagens.length == 1 ? 'mensagem' : 'mensagens'}'),
        content: SizedBox(
          width: 480,
          height: 520,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar conversa ou pessoa'),
              onChanged: (v) => set(() => q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                if (convs.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 4), child: Text('Conversas', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12.5))),
                for (final c in convs)
                  CheckboxListTile(
                    dense: true,
                    value: destinos.contains('c${c.id}'),
                    onChanged: (_) => alternar('c${c.id}'),
                    secondary: Avatar(url: c.avatar, nome: c.titulo, tam: 30),
                    title: Text(c.titulo),
                    subtitle: c.grupo ? const Text('Grupo') : null,
                  ),
                if (gente.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text('Pessoas', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12.5))),
                for (final x in gente)
                  CheckboxListTile(
                    dense: true,
                    value: destinos.contains('u${x['id']}'),
                    onChanged: (_) => alternar('u${x['id']}'),
                    secondary: Avatar(url: x['avatar']?.toString(), nome: '${x['name']}', tam: 30),
                    title: Text('${x['name']}'),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          Text('${destinos.length} de 10', style: TextStyle(color: pal.muted)),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: destinos.isEmpty
                ? null
                : () async {
                    try {
                      final r = await chat.encaminhar(mensagens, destinos.toList());
                      foi = true;
                      if (d.mounted) Navigator.pop(d);
                      final avisos = (r['avisos'] is List ? (r['avisos'] as List) : const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
                      final n = (r['enviadas'] as num?)?.toInt() ?? 0;
                      if (context.mounted) {
                        avisar(context, [n > 0 ? 'Encaminhado ($n ${n == 1 ? 'mensagem' : 'mensagens'}).' : 'Nada foi encaminhado.', ...avisos].join('\n'), erro: n == 0);
                      }
                    } catch (e) {
                      if (d.mounted) avisar(d, erroChat(e), erro: true);
                    }
                  },
            child: const Text('Encaminhar'),
          ),
        ],
      );
    }),
  );
  return foi;
}

/// Nova enquete (só em grupo).
Future<bool> novaEnquete(BuildContext context, ChatApi chat, int conversa) async {
  final pergunta = TextEditingController();
  final opcoes = [TextEditingController(), TextEditingController()];
  var multi = false;
  var criou = false;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, set) {
      return AlertDialog(
        title: const Text('Nova enquete'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: pergunta, autofocus: true, decoration: const InputDecoration(labelText: 'Pergunta')),
              const SizedBox(height: 10),
              for (var i = 0; i < opcoes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: TextField(controller: opcoes[i], decoration: InputDecoration(labelText: 'Opção ${i + 1}'))),
                    if (opcoes.length > 2)
                      IconButton(onPressed: () => set(() => opcoes.removeAt(i).dispose()), icon: const Icon(Icons.close_rounded), tooltip: 'Tirar'),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: opcoes.length >= 10 ? null : () => set(() => opcoes.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Acrescentar opção'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: multi,
                onChanged: (v) => set(() => multi = v ?? false),
                title: const Text('Permitir marcar mais de uma opção'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final ops = opcoes.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
              if (pergunta.text.trim().isEmpty || ops.length < 2) {
                avisar(d, 'Escreva a pergunta e ao menos 2 opções.', erro: true);
                return;
              }
              try {
                await chat.criarEnquete(conversa, pergunta.text.trim(), ops, multi);
                criou = true;
                if (d.mounted) Navigator.pop(d);
              } catch (e) {
                if (d.mounted) avisar(d, erroChat(e), erro: true);
              }
            },
            child: const Text('Criar enquete'),
          ),
        ],
      );
    }),
  );
  pergunta.dispose();
  for (final c in opcoes) {
    c.dispose();
  }
  return criou;
}

Future<void> quemVotou(BuildContext context, ChatApi chat, int pollId) async {
  Map<String, dynamic> r;
  try {
    r = await chat.votos(pollId);
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text((r['question'] ?? 'Enquete').toString()),
      content: SizedBox(
        width: 440,
        child: ListView(shrinkWrap: true, children: [
          for (final o in (r['options'] as List? ?? [])) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text('${o['text']} · ${(o['voters'] as List? ?? []).length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if ((o['voters'] as List? ?? []).isEmpty) Text('Ninguém votou nesta.', style: TextStyle(color: d.pal.muted)),
            for (final v in (o['voters'] as List? ?? [])) Text('• ${v['name']}'),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fechar'))],
    ),
  );
}

Future<void> quemLeu(BuildContext context, ChatApi chat, int msgId) async {
  Map<String, dynamic> r;
  try {
    r = await chat.leituras(msgId);
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return;
  }
  if (!context.mounted) return;
  Widget bloco(String titulo, List l, IconData i, Color cor, {bool comHora = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Row(children: [Icon(i, size: 16, color: cor), const SizedBox(width: 6), Text('$titulo (${l.length})', style: const TextStyle(fontWeight: FontWeight.w700))])),
        if (l.isEmpty) Text('—', style: TextStyle(color: context.pal.muted)),
        for (final x in l) Text('${x['name']}${comHora && x['read_at'] != null ? ' · ${x['read_at']}' : ''}'),
      ]);
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Quem leu'),
      content: SizedBox(
        width: 400,
        child: ListView(shrinkWrap: true, children: [
          bloco('Lida', r['reads'] as List? ?? [], Icons.done_all_rounded, const Color(0xFF2563EB), comHora: true),
          bloco('Entregue', r['delivered'] as List? ?? [], Icons.done_all_rounded, d.pal.muted),
          bloco('Ainda não recebeu', r['pending'] as List? ?? [], Icons.check_rounded, d.pal.muted),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fechar'))],
    ),
  );
}

/// Os arquivos da conversa (imagens em miniatura, o resto em lista).
Future<void> arquivosDaConversa(BuildContext context, Api api, ChatApi chat, int id) async {
  List<Map<String, dynamic>> r;
  try {
    r = await chat.arquivos(id);
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return;
  }
  if (!context.mounted) return;
  final anexos = r.map(Anexo.de).toList();
  final imagens = anexos.where((a) => a.imagem).toList();
  final outros = anexos.where((a) => !a.imagem).toList();
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Arquivos da conversa (${anexos.length})'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: anexos.isEmpty
            ? const Vazio(Icons.folder_open_outlined, 'Nenhum arquivo foi enviado nesta conversa.')
            : ListView(children: [
                if (imagens.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < imagens.length; i++)
                      InkWell(
                        onTap: () => abrirImagens(d, api, imagens, i),
                        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ImagemApi(api, imagens[i].miniatura ?? imagens[i].url, largura: 140, altura: 105)),
                      ),
                  ]),
                if (outros.isNotEmpty) const SizedBox(height: 12),
                for (var i = 0; i < outros.length; i++)
                  ListTile(
                    dense: true,
                    leading: Icon(outros[i].audio ? Icons.audiotrack_rounded : Icons.insert_drive_file_outlined, color: d.pal.primary),
                    title: Text(outros[i].nome),
                    subtitle: Text([tamanhoLegivel(outros[i].tamanho), '${r[anexos.indexOf(outros[i])]['author'] ?? ''}', '${r[anexos.indexOf(outros[i])]['at'] ?? ''}'].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: const Icon(Icons.download_rounded),
                    onTap: () => baixarEAbrir(d, api, outros[i]),
                  ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fechar'))],
    ),
  );
}

/// Confirmação simples (sair do grupo, excluir).
Future<bool> confirmar(BuildContext context, String titulo, String texto, String acao, {bool perigo = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(
          style: perigo ? FilledButton.styleFrom(backgroundColor: d.pal.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(acao),
        ),
      ],
    ),
  );
  return r == true;
}

/* ======================== reuniões do Google Meet ======================== */

const duracoesReuniao = [15, 30, 45, 60, 90, 120, 180, 240];
String rotuloDuracao(int min) => min < 60 ? '$min min' : (min % 60 == 0 ? '${min ~/ 60} h' : '${(min / 60).toString().replaceAll('.', ',')} h');

/// Criar a reunião do Meet (agora ou agendada). Devolve a reunião e a mensagem
/// com o cartão, ou null se a pessoa desistiu. No "agora", o Meet já abre no
/// navegador. Sem o Google pronto, a janela explica e leva ao Perfil do site.
Future<(Reuniao?, Mensagem?)?> novaReuniao(BuildContext context, ChatApi chat, int conversa, {required String tituloPadrao}) {
  return showDialog<(Reuniao?, Mensagem?)>(
    context: context,
    builder: (_) => _DialogoReuniao(chat: chat, conversa: conversa, tituloPadrao: tituloPadrao),
  );
}

/// O controller de texto é do PRÓPRIO diálogo (descartado no `dispose`): criado
/// fora e descartado logo depois do `showDialog`, quebraria a animação de saída.
class _DialogoReuniao extends StatefulWidget {
  final ChatApi chat;
  final int conversa;
  final String tituloPadrao;
  const _DialogoReuniao({required this.chat, required this.conversa, required this.tituloPadrao});
  @override
  State<_DialogoReuniao> createState() => _DialogoReuniaoState();
}

class _DialogoReuniaoState extends State<_DialogoReuniao> {
  final _titulo = TextEditingController();
  final _desc = TextEditingController();
  Map<String, dynamic>? _st;
  String? _msgGoogle, _erro;
  bool _checando = true, _agendar = false, _convidar = true, _enviando = false, _mexeuDur = false;
  int _dur = 30;
  late DateTime _dia;
  late TimeOfDay _hora;

  @override
  void initState() {
    super.initState();
    // Sugestão para agendar: a próxima hora cheia; fora do expediente (19h às 7h), 9h.
    var d = DateTime.now();
    d = DateTime(d.year, d.month, d.day, d.hour + 1);
    if (d.hour >= 19 || d.hour < 7) {
      d = DateTime(d.year, d.month, d.day + (d.hour >= 19 ? 1 : 0), 9);
    }
    _dia = DateTime(d.year, d.month, d.day);
    _hora = TimeOfDay(hour: d.hour, minute: 0);
    _checar();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _pode => _st?['pode_criar'] == true && _st?['disponivel'] != false && _msgGoogle == null;

  Future<void> _checar() async {
    setState(() {
      _checando = true;
      _msgGoogle = null;
    });
    try {
      final st = await widget.chat.statusGoogle();
      if (!mounted) return;
      setState(() {
        _st = st;
        _checando = false;
        if (st['disponivel'] == false) {
          _msgGoogle = 'As reuniões do Meet ainda não estão disponíveis no servidor.';
        } else if (st['pode_criar'] != true) {
          _msgGoogle = st['configurado'] == false
              ? 'A integração com o Google ainda não foi configurada pelo administrador (Sistema → Google).'
              : st['conectado'] == true
                  ? 'Sua conta Google está conectada só para ler a agenda. Reconecte no NN Conecta para liberar a criação de reuniões do Meet.'
                  : 'Para criar reuniões do Meet, conecte sua conta Google no seu perfil do NN Conecta.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _checando = false;
          _msgGoogle = e is ApiErro && e.status == 404
              ? 'As reuniões do Meet ainda não estão disponíveis no servidor.'
              : 'Não consegui conferir a conexão com o Google agora. Tente de novo.';
        });
      }
    }
  }

  void _modo(bool agendar) => setState(() {
        _agendar = agendar;
        if (!_mexeuDur) _dur = agendar ? 60 : 30;
      });

  Future<void> _escolherDia() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() => _dia = d);
  }

  Future<void> _escolherHora() async {
    final h = await showTimePicker(
      context: context,
      initialTime: _hora,
      builder: (c, filho) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: filho!),
    );
    if (h != null && mounted) setState(() => _hora = h);
  }

  String _dois(int n) => n.toString().padLeft(2, '0');

  Future<void> _criar() async {
    if (!_pode || _enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final r = await widget.chat.criarReuniao(
        widget.conversa,
        agendar: _agendar,
        titulo: _titulo.text.trim(),
        descricao: _desc.text.trim(),
        data: '${_dia.year}-${_dois(_dia.month)}-${_dois(_dia.day)}',
        hora: '${_dois(_hora.hour)}:${_dois(_hora.minute)}',
        duracao: _dur,
        convidar: _convidar,
      );
      if (!_agendar && r.$1 != null && r.$1!.urlOk) {
        await abrirNoNavegador(r.$1!.url);
      }
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        if (e is ApiErro && e.status == 428) {
          _msgGoogle = e.mensagem;
        } else {
          _erro = erroChat(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final conectarUrl = (_st?['conectar_url'] ?? '').toString();
    final mostrarConectar = _st?['configurado'] != false && _st?['disponivel'] != false && conectarUrl.isNotEmpty;
    return AlertDialog(
      title: const Text('Reunião do Google Meet'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (_checando) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
            if (!_checando && _msgGoogle != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.cardBorder)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_msgGoogle!),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (mostrarConectar)
                      FilledButton.icon(
                        onPressed: () => abrirNoNavegador(conectarUrl),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Conectar no NN Conecta'),
                      ),
                    OutlinedButton(onPressed: _checar, child: const Text('Já conectei')),
                  ]),
                ]),
              ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Agora'), icon: Icon(Icons.videocam_outlined)),
                ButtonSegment(value: true, label: Text('Agendar'), icon: Icon(Icons.event_outlined)),
              ],
              selected: {_agendar},
              onSelectionChanged: (s) => _modo(s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titulo,
              maxLength: 200,
              decoration: InputDecoration(labelText: 'Título', hintText: widget.tituloPadrao, counterText: ''),
            ),
            if (_agendar) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherDia,
                    icon: const Icon(Icons.calendar_today_outlined, size: 17),
                    label: Text('${_dois(_dia.day)}/${_dois(_dia.month)}/${_dia.year}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherHora,
                    icon: const Icon(Icons.schedule_rounded, size: 17),
                    label: Text('${_dois(_hora.hour)}:${_dois(_hora.minute)}'),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            // `initialValue` só vale na criação: a chave refaz o campo quando a
            // duração padrão muda com o modo (Agora 30 min, Agendar 1 h).
            DropdownButtonFormField<int>(
              key: ValueKey('dur$_dur'),
              initialValue: _dur,
              decoration: const InputDecoration(labelText: 'Duração'),
              items: [for (final d in duracoesReuniao) DropdownMenuItem(value: d, child: Text(rotuloDuracao(d)))],
              onChanged: (v) => setState(() {
                _dur = v ?? _dur;
                _mexeuDur = true;
              }),
            ),
            if (_agendar) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descrição (opcional)', hintText: 'Pauta, link de documento…', counterText: ''),
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _convidar,
              onChanged: (v) => setState(() => _convidar = v ?? true),
              title: const Text('Convidar os participantes desta conversa'),
              subtitle: const Text('O Google manda o convite por e-mail.'),
            ),
            Text(
              'A reunião entra na sua Agenda Google. O vídeo abre no navegador — o Google não permite abrir o Meet dentro do app.',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 10),
              Text(_erro!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _pode && !_enviando && !_checando ? _criar : null,
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_agendar ? 'Agendar reunião' : 'Iniciar reunião'),
        ),
      ],
    );
  }
}

/// Confirma e cancela. Devolve a reunião já cancelada (para redesenhar o cartão)
/// ou null se a pessoa desistiu ou o servidor recusou (o motivo aparece).
Future<Reuniao?> cancelarReuniaoConfirmando(BuildContext context, ChatApi chat, Reuniao r) async {
  final ok = await confirmar(context, 'Cancelar a reunião?', '“${r.titulo}” — ${r.quando}.\nOs convidados recebem o cancelamento do Google.', 'Cancelar reunião', perigo: true);
  if (!ok || !context.mounted) return null;
  try {
    final (nova, aviso) = await chat.cancelarReuniao(r.id);
    if (context.mounted) avisar(context, aviso.isNotEmpty ? aviso : 'Reunião cancelada.');
    return nova;
  } catch (e) {
    if (context.mounted) avisar(context, erroChat(e), erro: true);
    return null;
  }
}

/// As reuniões da conversa (as próximas e a que está acontecendo primeiro).
Future<void> listaReunioes(BuildContext context, ChatApi chat, int conversa, {required int meuId, required VoidCallback aoNova, void Function(Reuniao r)? aoMudar}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ListaReunioes(chat: chat, conversa: conversa, meuId: meuId, aoNova: aoNova, aoMudar: aoMudar),
  );
}

class _ListaReunioes extends StatefulWidget {
  final ChatApi chat;
  final int conversa, meuId;
  final VoidCallback aoNova;
  final void Function(Reuniao r)? aoMudar;
  const _ListaReunioes({required this.chat, required this.conversa, required this.meuId, required this.aoNova, this.aoMudar});
  @override
  State<_ListaReunioes> createState() => _ListaReunioesState();
}

class _ListaReunioesState extends State<_ListaReunioes> {
  List<Reuniao>? _lista;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final l = await widget.chat.reunioes(widget.conversa);
      if (mounted) setState(() => _lista = l);
    } catch (e) {
      if (mounted) setState(() => _erro = erroChat(e));
    }
  }

  Future<void> _cancelar(Reuniao r) async {
    final nova = await cancelarReuniaoConfirmando(context, widget.chat, r);
    if (nova == null || !mounted) return;
    setState(() => _lista = [for (final x in _lista ?? <Reuniao>[]) x.id == nova.id ? nova : x]);
    widget.aoMudar?.call(nova);
  }

  @override
  Widget build(BuildContext context) {
    final l = _lista;
    return AlertDialog(
      title: const Text('Reuniões da conversa'),
      content: SizedBox(
        width: 520,
        child: _erro != null
            ? Vazio(Icons.cloud_off_outlined, _erro!)
            : l == null
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : l.isEmpty
                    ? const Vazio(Icons.event_busy_outlined, 'Nenhuma reunião nesta conversa ainda.')
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 460),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: l.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => CartaoReuniao(l[i], meuId: widget.meuId, largura: double.infinity, aoCancelar: () => _cancelar(l[i])),
                        ),
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.aoNova();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nova reunião'),
        ),
      ],
    );
  }
}

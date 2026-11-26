// NN News no app: lista com categorias e busca, e a matéria (corpo, galeria,
// vídeo, curtir e comentar). As regras são as do portal: só matéria publicada,
// curtidas e comentários respeitando o que está ligado no Sistema.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/comum.dart';
import '../widgets/html.dart';
import 'casca.dart';

class TelaNews extends StatefulWidget {
  final Controle c;
  final bool ativa;
  const TelaNews(this.c, {super.key, required this.ativa});

  static final _pedida = ValueNotifier<int?>(null);

  /// Abre uma matéria a partir de qualquer tela (o painel, por exemplo).
  static void abrir(Object? id) {
    final n = id is num ? id.toInt() : int.tryParse('$id') ?? 0;
    if (n <= 0) return;
    Casca.irPara(2);
    _pedida.value = n;
  }

  @override
  State<TelaNews> createState() => _TelaNewsState();
}

class _TelaNewsState extends State<TelaNews> {
  Map<String, dynamic>? _d;
  final List<Map<String, dynamic>> _materias = [];
  String _cat = '';
  final _busca = TextEditingController();
  String _q = '';
  int _pagina = 1;
  bool _carregando = false;
  String? _erro;
  int? _aberta;
  bool _iniciada = false;

  @override
  void initState() {
    super.initState();
    TelaNews._pedida.addListener(_pedido);
    _pedido();
  }

  @override
  void didUpdateWidget(covariant TelaNews old) {
    super.didUpdateWidget(old);
    if (widget.ativa && !_iniciada) _carregar();
  }

  @override
  void dispose() {
    TelaNews._pedida.removeListener(_pedido);
    _busca.dispose();
    super.dispose();
  }

  void _pedido() {
    final id = TelaNews._pedida.value;
    if (id == null) return;
    TelaNews._pedida.value = null;
    setState(() => _aberta = id);
  }

  Future<void> _carregar({bool mais = false}) async {
    if (_carregando) return;
    _iniciada = true;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pag = mais ? _pagina + 1 : 1;
      final r = (await widget.c.api.get('/v1/callapp/news', q: {
        if (_cat.isNotEmpty) 'categoria': _cat,
        if (_q.isNotEmpty) 'q': _q,
        'pagina': '$pag',
      }) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _d = r;
        _pagina = (r['pagina'] as num?)?.toInt() ?? pag;
        if (!mais) _materias.clear();
        _materias.addAll(((r['materias'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()));
      });
    } catch (e) {
      if (mounted) setState(() => _erro = erroDe(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _filtrar({String? cat, String? q}) {
    if (cat != null) _cat = cat;
    if (q != null) _q = q.trim();
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_aberta != null) {
      return Materia(widget.c, _aberta!, aoVoltar: () => setState(() => _aberta = null), aoAbrir: (id) => setState(() => _aberta = id));
    }
    if (!_iniciada && widget.ativa) WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
    final pal = context.pal;
    final d = _d;
    final cats = ((d?['categorias'] as List?) ?? const []).cast<Map>();
    final destaques = ((d?['destaques'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(28, 20, 28, 28), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1480),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _LogoNews(widget.c),
              const SizedBox(width: 14),
              if ((d?['slogan'] ?? '').toString().isNotEmpty)
                Expanded(child: Text(d!['slogan'].toString(), style: TextStyle(color: pal.muted)))
              else
                const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _busca,
                  decoration: InputDecoration(
                    hintText: 'Buscar matérias',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () {
                      _busca.clear();
                      _filtrar(q: '');
                    }),
                  ),
                  onSubmitted: (v) => _filtrar(q: v),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('Todas'), selected: _cat.isEmpty, onSelected: (_) => _filtrar(cat: '')),
              for (final c in cats)
                ChoiceChip(
                  label: Text('${c['nome']}'),
                  selected: _cat == c['slug'],
                  selectedColor: context.cores.corNews((c['cor'] as num?)?.toInt() ?? 0).withValues(alpha: .22),
                  onSelected: (_) => _filtrar(cat: c['slug'].toString()),
                ),
            ]),
            const SizedBox(height: 18),
            if (_erro != null) Vazio(Icons.cloud_off_outlined, _erro!),
            if (d == null && _erro == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (destaques.isNotEmpty) ...[
              LayoutBuilder(builder: (_, cons) {
                final n = cons.maxWidth > 1000 ? 3 : (cons.maxWidth > 640 ? 2 : 1);
                return Wrap(spacing: 16, runSpacing: 16, children: [
                  for (final m in destaques)
                    SizedBox(width: (cons.maxWidth - 16 * (n - 1)) / n, child: CartaoMateria(widget.c, m, grande: true, onTap: () => setState(() => _aberta = m['id']))),
                ]);
              }),
              const SizedBox(height: 22),
              const Text('Últimas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
            ],
            if (d != null && _materias.isEmpty && destaques.isEmpty)
              Vazio(Icons.article_outlined, _q.isNotEmpty ? 'Nenhuma matéria com “$_q”.' : 'Nenhuma matéria publicada ainda.'),
            LayoutBuilder(builder: (_, cons) {
              final n = cons.maxWidth > 1100 ? 4 : (cons.maxWidth > 800 ? 3 : (cons.maxWidth > 520 ? 2 : 1));
              final ids = destaques.map((x) => x['id']).toSet();
              final lista = _materias.where((m) => !ids.contains(m['id'])).toList();
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final m in lista)
                  SizedBox(width: (cons.maxWidth - 16 * (n - 1)) / n, child: CartaoMateria(widget.c, m, onTap: () => setState(() => _aberta = m['id']))),
              ]);
            }),
            if (d != null && _pagina < ((d['paginas'] as num?)?.toInt() ?? 1))
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Center(child: OutlinedButton(onPressed: _carregando ? null : () => _carregar(mais: true), child: Text(_carregando ? 'Carregando…' : 'Carregar mais'))),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _LogoNews extends StatelessWidget {
  final Controle c;
  const _LogoNews(this.c);
  @override
  Widget build(BuildContext context) {
    final n = (c.aparencia?['news'] as Map?) ?? const {};
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final url = ((escuro ? n['logo_escura'] : null) ?? n['logo'])?.toString();
    if (url != null && url.isNotEmpty) {
      return Image.network(url, height: 38, errorBuilder: (_, __, ___) => _nome(context, n));
    }
    return _nome(context, n);
  }

  Widget _nome(BuildContext context, Map n) => Text((n['nome'] ?? 'NN News').toString(),
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: context.pal.primary, letterSpacing: -.3));
}

class _SeloCategoria extends StatelessWidget {
  final Map cat;
  const _SeloCategoria(this.cat);
  @override
  Widget build(BuildContext context) {
    final cor = context.cores.corNews((cat['cor'] as num?)?.toInt() ?? 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(6)),
      child: Text((cat['nome'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

Widget _capa(Controle c, Map<String, dynamic> m, {double? altura, bool mini = true}) {
  final k = m['capa_chave']?.toString();
  final yt = m['youtube_id']?.toString();
  if (k != null && k.isNotEmpty) return ImagemApi(c.api, midiaNews(k, mini: mini), altura: altura, largura: double.infinity);
  if (yt != null && yt.isNotEmpty) {
    return Image.network('https://i.ytimg.com/vi/$yt/hqdefault.jpg', height: altura, width: double.infinity, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
  return Builder(builder: (context) {
    final cor = context.cores.corNews(((m['categoria'] as Map?)?['cor'] as num?)?.toInt() ?? 0);
    return Container(
      height: altura,
      decoration: BoxDecoration(gradient: LinearGradient(colors: [cor, Color.lerp(cor, Colors.black, .45)!])),
      alignment: Alignment.center,
      child: Text((m['titulo'] ?? '?').toString().characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
    );
  });
}

class CartaoMateria extends StatelessWidget {
  final Controle c;
  final Map<String, dynamic> m;
  final bool grande;
  final VoidCallback onTap;
  const CartaoMateria(this.c, this.m, {super.key, this.grande = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            _capa(c, m, altura: grande ? 230 : 150, mini: !grande),
            if (m['tipo'] == 'video')
              const Positioned(right: 10, bottom: 10, child: CircleAvatar(radius: 16, backgroundColor: Colors.black54, child: Icon(Icons.play_arrow_rounded, color: Colors.white))),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _SeloCategoria((m['categoria'] as Map?) ?? const {}),
                const SizedBox(width: 8),
                Text((m['data'] ?? '').toString(), style: TextStyle(color: pal.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Text((m['titulo'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: grande ? 19 : 15.5, height: 1.25)),
              if (grande && (m['resumo'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(m['resumo'].toString(), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, height: 1.4)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.visibility_outlined, size: 15, color: pal.muted),
                const SizedBox(width: 4),
                Text('${m['leituras'] ?? 0}', style: TextStyle(color: pal.muted, fontSize: 12)),
                const SizedBox(width: 12),
                Icon(Icons.favorite_border_rounded, size: 15, color: pal.muted),
                const SizedBox(width: 4),
                Text('${m['curtidas'] ?? 0}', style: TextStyle(color: pal.muted, fontSize: 12)),
                const SizedBox(width: 12),
                Icon(Icons.mode_comment_outlined, size: 15, color: pal.muted),
                const SizedBox(width: 4),
                Text('${m['comentarios'] ?? 0}', style: TextStyle(color: pal.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class LinhaMateria extends StatelessWidget {
  final Controle c;
  final Map<String, dynamic> m;
  final VoidCallback onTap;
  const LinhaMateria(this.c, this.m, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 92, height: 62, child: _capa(c, m, altura: 62))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SeloCategoria((m['categoria'] as Map?) ?? const {}),
              const SizedBox(height: 4),
              Text((m['titulo'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text((m['data'] ?? '').toString(), style: TextStyle(color: pal.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A matéria aberta.
class Materia extends StatefulWidget {
  final Controle c;
  final int id;
  final VoidCallback aoVoltar;
  final void Function(int id) aoAbrir;
  const Materia(this.c, this.id, {super.key, required this.aoVoltar, required this.aoAbrir});
  @override
  State<Materia> createState() => _MateriaState();
}

class _MateriaState extends State<Materia> {
  Map<String, dynamic>? _m;
  String? _erro;
  final _comentario = TextEditingController();
  bool _enviando = false;
  bool _baixandoVideo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant Materia old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _carregar();
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _m = null;
      _erro = null;
    });
    try {
      final r = (await widget.c.api.get('/v1/callapp/news/materia', q: {'id': '${widget.id}'}) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _m = r);
    } catch (e) {
      if (mounted) setState(() => _erro = erroDe(e));
    }
  }

  Future<void> _curtir() async {
    try {
      final r = await widget.c.api.post('/v1/callapp/news/curtir', {'post_id': widget.id}) as Map;
      setState(() {
        _m!['curtiu'] = r['curtiu'];
        _m!['curtidas'] = r['total'];
      });
    } catch (e) {
      if (mounted) avisar(context, erroDe(e), erro: true);
    }
  }

  Future<void> _comentar() async {
    final t = _comentario.text.trim();
    if (t.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final r = await widget.c.api.post('/v1/callapp/news/comentar', {'post_id': widget.id, 'texto': t}) as Map;
      setState(() {
        (_m!['comentarios_lista'] as List).add(r['comentario']);
        _m!['comentarios'] = r['total'];
        _comentario.clear();
      });
    } catch (e) {
      if (mounted) avisar(context, erroDe(e), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _excluirComentario(Map cm) async {
    try {
      final r = await widget.c.api.post('/v1/callapp/news/comentario/excluir', {'id': cm['id']}) as Map;
      setState(() {
        (_m!['comentarios_lista'] as List).removeWhere((x) => (x as Map)['id'] == cm['id']);
        _m!['comentarios'] = r['total'];
      });
    } catch (e) {
      if (mounted) avisar(context, erroDe(e), erro: true);
    }
  }

  Future<void> _verVideo(Map v) async {
    if (v['tipo'] == 'youtube') {
      await abrirLink(context, v['link'].toString());
      return;
    }
    // Vídeo do próprio NN News: baixa (com o token) e abre no reprodutor do sistema.
    setState(() => _baixandoVideo = true);
    try {
      final dir = await getTemporaryDirectory();
      final ext = (v['mime'] ?? '').toString().contains('webm') ? 'webm' : 'mp4';
      final f = await widget.c.api.baixar(midiaNews(v['chave'].toString()), File(p.join(dir.path, 'nnnews-${v['chave']}.$ext')));
      await launchUrl(Uri.file(f.path));
    } catch (e) {
      if (mounted) avisar(context, erroDe(e), erro: true);
    } finally {
      if (mounted) setState(() => _baixandoVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final m = _m;
    return ListView(padding: const EdgeInsets.fromLTRB(28, 18, 28, 40), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: widget.aoVoltar, icon: const Icon(Icons.arrow_back), label: const Text('Voltar ao NN News'))),
            if (_erro != null) Vazio(Icons.article_outlined, _erro!),
            if (m == null && _erro == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (m != null) ...[
              const SizedBox(height: 8),
              Row(children: [_SeloCategoria((m['categoria'] as Map?) ?? const {}), const SizedBox(width: 10), Text('${m['data_longa']} · ${m['minutos']} min de leitura', style: TextStyle(color: pal.muted))]),
              const SizedBox(height: 12),
              Text(m['titulo'].toString(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1.15)),
              if ((m['resumo'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(m['resumo'].toString(), style: TextStyle(fontSize: 17, color: pal.muted, height: 1.4)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Avatar(url: m['autor_avatar']?.toString(), nome: (m['autor'] ?? '').toString(), tam: 30),
                const SizedBox(width: 8),
                Text((m['autor'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 18),
              if ((m['capa_chave'] ?? '').toString().isNotEmpty)
                ClipRRect(borderRadius: BorderRadius.circular(14), child: ImagemApi(widget.c.api, midiaNews(m['capa_chave'].toString()), fit: BoxFit.cover)),
              if (m['video'] != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _baixandoVideo ? null : () => _verVideo(m['video'] as Map),
                  icon: Icon(m['video']['tipo'] == 'youtube' ? Icons.smart_display_outlined : Icons.play_circle_outline),
                  label: Text(_baixandoVideo ? 'Baixando o vídeo…' : (m['video']['tipo'] == 'youtube' ? 'Assistir no YouTube' : 'Assistir ao vídeo')),
                ),
              ],
              const SizedBox(height: 18),
              HtmlConteudo(widget.c.api, (m['corpo'] ?? '').toString(), tamanho: 16.5),
              if (((m['galeria'] as List?) ?? const []).isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final g in (m['galeria'] as List))
                    InkWell(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(child: ImagemApi(widget.c.api, midiaNews(g['chave'].toString()), fit: BoxFit.contain))),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ImagemApi(widget.c.api, midiaNews(g['chave'].toString(), mini: true), largura: 200, altura: 140)),
                    ),
                ]),
              ],
              const SizedBox(height: 24),
              Row(children: [
                if (m['curtidas_on'] == true)
                  OutlinedButton.icon(
                    onPressed: _curtir,
                    style: OutlinedButton.styleFrom(foregroundColor: m['curtiu'] == true ? const Color(0xFFC2255C) : null),
                    icon: Icon(m['curtiu'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    label: Text('${m['curtidas'] ?? 0} ${((m['curtidas'] ?? 0) as num) == 1 ? 'curtida' : 'curtidas'}'),
                  ),
                const SizedBox(width: 12),
                Text('${m['leituras'] ?? 0} leituras', style: TextStyle(color: pal.muted)),
              ]),
              if (m['comenta_on'] == true) ...[
                const SizedBox(height: 26),
                Text('Comentários (${m['comentarios'] ?? 0})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 10),
                for (final cm in (m['comentarios_lista'] as List).cast<Map>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Avatar(url: cm['avatar']?.toString(), nome: (cm['nome'] ?? '').toString(), tam: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(cm['nome'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text(cm['data'].toString(), style: TextStyle(color: pal.muted, fontSize: 12)),
                              const Spacer(),
                              if (cm['excluir'] == true)
                                IconButton(tooltip: 'Excluir o comentário', visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _excluirComentario(cm)),
                            ]),
                            const SizedBox(height: 4),
                            SelectableText(cm['texto'].toString()),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 6),
                TextField(
                  controller: _comentario,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(hintText: 'Escreva um comentário'),
                ),
                Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _enviando ? null : _comentar, child: Text(_enviando ? 'Publicando…' : 'Comentar'))),
              ],
              if (((m['mais'] as List?) ?? const []).isNotEmpty) ...[
                const SizedBox(height: 30),
                const Text('Mais nesta categoria', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                for (final o in (m['mais'] as List).cast<Map>())
                  LinhaMateria(widget.c, o.cast<String, dynamic>(), onTap: () => widget.aoAbrir((o['id'] as num).toInt())),
              ],
            ],
          ]),
        ),
      ),
    ]);
  }
}

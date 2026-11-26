// O painel inicial: boas-vindas (o bloco da data do site), NN News (destaque +
// últimas), aniversariantes do mês e o quadro de avisos (o mais recente inteiro).
// Cada bloco vem do `/v1/callapp/inicio`; o que falhar no servidor some sozinho.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/comum.dart';
import '../widgets/html.dart';
import 'casca.dart';
import 'news.dart';

class TelaInicio extends StatefulWidget {
  final Controle c;
  const TelaInicio(this.c, {super.key});
  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  Map<String, dynamic>? _d;
  String? _erro;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _carregar();
    _t = Timer.periodic(const Duration(minutes: 5), (_) => _carregar());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = (await widget.c.api.get('/v1/callapp/inicio') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _d = r;
        _erro = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = erroDe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Center(child: _erro == null ? const CircularProgressIndicator() : Vazio(Icons.cloud_off_outlined, _erro!));
    }
    final news = (d['news'] as Map?)?.cast<String, dynamic>();
    final avisos = ((d['avisos'] as List?) ?? const []).cast<Map>();
    final anivs = ((d['aniversariantes'] as List?) ?? const []).cast<Map>();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: LayoutBuilder(builder: (_, cons) {
        final largo = cons.maxWidth >= 1100;
        final noticias = news == null ? null : _BlocoNews(widget.c, news);
        final aniversarios = _BlocoAniversariantes(anivs.map((m) => m.cast<String, dynamic>()).toList());
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1480),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _BoasVindas(widget.c),
                  const SizedBox(height: 18),
                  if (largo)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (noticias != null) Expanded(flex: 8, child: noticias),
                      if (noticias != null) const SizedBox(width: 18),
                      Expanded(flex: 4, child: aniversarios),
                    ])
                  else ...[
                    if (noticias != null) ...[noticias, const SizedBox(height: 18)],
                    aniversarios,
                  ],
                  const SizedBox(height: 18),
                  _BlocoAvisos(widget.c, avisos.map((m) => m.cast<String, dynamic>()).toList()),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _BoasVindas extends StatelessWidget {
  final Controle c;
  const _BoasVindas(this.c);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final agora = DateTime.now();
    final h = agora.hour;
    final saud = h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
    final dia = DateFormat("EEEE", 'pt_BR').format(agora);
    final mes = DateFormat("MMMM 'de' y", 'pt_BR').format(agora);
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 132,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: escuro ? null : const LinearGradient(colors: [Color(0xFF1552D0), Color(0xFF0B7A44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: escuro ? const Color(0xFF323232) : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${agora.day}', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 6),
              Text(mes, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${dia[0].toUpperCase()}${dia.substring(1)}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$saud, ${c.primeiroNome}!', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('As novidades da empresa, os avisos e os aniversariantes do mês — e as conversas na aba ao lado.',
                    style: TextStyle(color: p.muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BlocoNews extends StatelessWidget {
  final Controle c;
  final Map<String, dynamic> news;
  const _BlocoNews(this.c, this.news);
  @override
  Widget build(BuildContext context) {
    final destaques = ((news['destaques'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final ultimas = ((news['ultimas'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final todas = [...destaques, ...ultimas];
    return CartaoSecao(
      titulo: (news['nome'] ?? 'NN News').toString(),
      icone: Icons.newspaper_outlined,
      acao: TextButton(onPressed: () => Casca.irPara(2), child: const Text('Ver todas')),
      child: todas.isEmpty
          ? const Vazio(Icons.article_outlined, 'Nenhuma matéria publicada ainda.')
          : LayoutBuilder(builder: (_, cons) {
              final principal = todas.first;
              final resto = todas.skip(1).take(5).toList();
              final lado = cons.maxWidth > 760;
              final grande = CartaoMateria(c, principal, grande: true, onTap: () => TelaNews.abrir(principal['id']));
              final lista = Column(children: [for (final m in resto) LinhaMateria(c, m, onTap: () => TelaNews.abrir(m['id']))]);
              return lado
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 6, child: grande),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: lista),
                    ])
                  : Column(children: [grande, const SizedBox(height: 12), lista]);
            }),
    );
  }
}

class _BlocoAniversariantes extends StatelessWidget {
  final List<Map<String, dynamic>> lista;
  const _BlocoAniversariantes(this.lista);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mes = DateFormat('MMMM', 'pt_BR').format(DateTime.now());
    return CartaoSecao(
      titulo: 'Aniversariantes de $mes',
      icone: Icons.cake_outlined,
      child: lista.isEmpty
          ? const Vazio(Icons.cake_outlined, 'Ninguém faz aniversário este mês.')
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, children: [
                for (final a in lista)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: a['hoje'] == true ? p.primary.withValues(alpha: .10) : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Avatar(url: a['avatar']?.toString(), nome: (a['nome'] ?? '').toString(), tam: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${a['nome']}${a['eu'] == true ? ' (você)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          if ((a['cargo'] ?? '').toString().isNotEmpty) Text(a['cargo'].toString(), style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      a['hoje'] == true
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(99)),
                              child: Text('Hoje 🎉', style: TextStyle(color: tintaSobre(p.primary), fontSize: 12, fontWeight: FontWeight.w700)),
                            )
                          : Text('dia ${a['dia']}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
    );
  }
}

class _BlocoAvisos extends StatelessWidget {
  final Controle c;
  final List<Map<String, dynamic>> avisos;
  const _BlocoAvisos(this.c, this.avisos);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return CartaoSecao(
      titulo: 'Quadro de avisos',
      icone: Icons.campaign_outlined,
      acao: TextButton(onPressed: () => Casca.irPara(3), child: const Text('Ver o mural')),
      child: avisos.isEmpty
          ? const Vazio(Icons.campaign_outlined, 'Nenhum aviso no momento.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: avisos.first['destaque'] == true ? p.primary.withValues(alpha: .07) : p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: p.primary, width: 4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(avisos.first['titulo'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  Text(dataCurta(avisos.first['data']?.toString()), style: TextStyle(color: p.muted, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  HtmlConteudo(c.api, (avisos.first['corpo'] ?? '').toString(), tamanho: 14.5),
                ]),
              ),
              for (final a in avisos.skip(1))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(a['destaque'] == true ? Icons.priority_high_rounded : Icons.notes_rounded, color: p.primary),
                  title: Text(a['titulo'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(a['resumo'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(dataCurta(a['data']?.toString()), style: TextStyle(color: p.muted, fontSize: 12)),
                  onTap: () => Casca.irPara(3),
                ),
            ]),
    );
  }
}

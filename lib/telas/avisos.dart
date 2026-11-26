// O Quadro de avisos (o mural do site): o mais recente primeiro, os destacados
// com a faixa colorida. Abrir um aviso mostra o corpo inteiro.
import 'package:flutter/material.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/comum.dart';
import '../widgets/html.dart';

class TelaAvisos extends StatefulWidget {
  final Controle c;
  final bool ativa;
  const TelaAvisos(this.c, {super.key, required this.ativa});
  @override
  State<TelaAvisos> createState() => _TelaAvisosState();
}

class _TelaAvisosState extends State<TelaAvisos> {
  List<Map<String, dynamic>>? _lista;
  String? _erro;
  final Set<int> _abertos = {};
  bool _iniciada = false;

  @override
  void didUpdateWidget(covariant TelaAvisos old) {
    super.didUpdateWidget(old);
    if (widget.ativa && (!_iniciada || !old.ativa)) _carregar();
  }

  Future<void> _carregar() async {
    _iniciada = true;
    try {
      final r = (await widget.c.api.get('/v1/callapp/avisos') as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (!mounted) return;
      setState(() {
        _lista = r;
        _erro = null;
        if (_abertos.isEmpty && r.isNotEmpty) _abertos.add((r.first['id'] as num).toInt());
      });
    } catch (e) {
      if (mounted) setState(() => _erro = erroDe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_iniciada && widget.ativa) WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
    final p = context.pal;
    final l = _lista;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: const EdgeInsets.fromLTRB(28, 22, 28, 28), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Quadro de avisos', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (_erro != null) Vazio(Icons.cloud_off_outlined, _erro!),
              if (l == null && _erro == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (l != null && l.isEmpty) const Vazio(Icons.campaign_outlined, 'Nenhum aviso no momento.'),
              for (final a in l ?? const <Map<String, dynamic>>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: a['destaque'] == true ? p.primary : p.cardBorder, width: 5))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        InkWell(
                          onTap: () => setState(() {
                            final id = (a['id'] as num).toInt();
                            _abertos.contains(id) ? _abertos.remove(id) : _abertos.add(id);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                            child: Row(children: [
                              if (a['destaque'] == true) ...[Icon(Icons.push_pin_rounded, size: 18, color: p.primary), const SizedBox(width: 8)],
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(a['titulo'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                                  Text(dataCurta(a['data']?.toString()), style: TextStyle(color: p.muted, fontSize: 12.5)),
                                ]),
                              ),
                              Icon(_abertos.contains((a['id'] as num).toInt()) ? Icons.expand_less : Icons.expand_more),
                            ]),
                          ),
                        ),
                        if (_abertos.contains((a['id'] as num).toInt()))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: HtmlConteudo(widget.c.api, (a['corpo'] ?? '').toString()),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                            child: Text(a['resumo'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
                          ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

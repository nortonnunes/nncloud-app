// Atendimento — a busca do devedor e a ficha, iguais às do portal do Tele
// Atendimento (`/atendimento`). A busca também fica no alto da tela, na barra do
// menu (`BuscaDevedor`), como no portal.
import 'package:flutter/material.dart';

import '../../servicos/controle.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import 'atendimento_api.dart';
import 'ficha.dart';
import 'ui.dart';

/// Um pedido vindo de fora da tela (a busca do topo): buscar um texto ou abrir uma ficha.
class PedidoAtendimento {
  final String? q;
  final int? id;
  const PedidoAtendimento.busca(String this.q) : id = null;
  const PedidoAtendimento.ficha(int this.id) : q = null;
}

class Atendimento {
  static final pedido = ValueNotifier<PedidoAtendimento?>(null);
}

class TelaAtendimento extends StatefulWidget {
  final Controle c;
  const TelaAtendimento(this.c, {super.key});
  @override
  State<TelaAtendimento> createState() => _TelaAtendimentoState();
}

class _TelaAtendimentoState extends State<TelaAtendimento> {
  late final AtendimentoApi _api = AtendimentoApi(widget.c.api);
  String _q = '';
  int _page = 1;
  Map<String, dynamic>? _res;
  bool _carregando = false;
  String? _erro;
  int? _fichaId;
  int _pedido = 0;
  final _campo = TextEditingController();
  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    Atendimento.pedido.addListener(_pedidoDeFora);
    _pedidoDeFora();
  }

  @override
  void dispose() {
    Atendimento.pedido.removeListener(_pedidoDeFora);
    _campo.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  void _pedidoDeFora() {
    final p = Atendimento.pedido.value;
    if (p == null) return;
    Atendimento.pedido.value = null;
    if (p.id != null) {
      setState(() => _fichaId = p.id);
    } else if (p.q != null) {
      _buscar(p.q!);
    }
  }

  Future<void> _buscar(String q, {int page = 1}) async {
    q = q.trim();
    final meu = ++_pedido;
    setState(() {
      _q = q;
      _page = page;
      _fichaId = null;
      _carregando = q.isNotEmpty;
      _erro = null;
      if (q.isEmpty) _res = null;
    });
    if (q.isEmpty) return;
    try {
      final r = await _api.busca(q, page: page);
      if (!mounted || meu != _pedido) return;
      setState(() {
        _res = r;
        _carregando = false;
      });
      if (_rolagem.hasClients) _rolagem.jumpTo(0);
    } catch (e) {
      if (!mounted || meu != _pedido) return;
      setState(() {
        _erro = erroDe(e);
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fichaId != null) {
      return FichaDevedor(
        key: ValueKey(_fichaId),
        api: _api,
        id: _fichaId!,
        aoVoltar: () {
          setState(() => _fichaId = null);
          // A lista volta atualizada (o último acionamento muda).
          if (_q.isNotEmpty) {
            _buscar(_q, page: _page);
          }
        },
      );
    }
    final p = context.pal;
    final res = _res;
    final itens = ((res?['itens'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final total = (res?['total'] as num?)?.toInt() ?? 0;
    final pages = (res?['pages'] as num?)?.toInt() ?? 1;

    return Scrollbar(
      controller: _rolagem,
      child: ListView(
        controller: _rolagem,
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        children: [
          Text(_q.isEmpty ? 'Atendimento' : 'Resultados da busca',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            _q.isEmpty
                ? 'Use a busca no alto da tela — nome, CPF/CNPJ, telefone ou número do contrato.'
                : 'Buscando por “$_q” em nome, e-mail, CPF/CNPJ, telefone e contrato.',
            style: TextStyle(color: p.muted, fontSize: 15),
          ),
          const SizedBox(height: 20),
          if (_erro != null) ...[
            Alerta(Text(_erro!), tom: 'perigo'),
            const SizedBox(height: 14)
          ],
          if (res?['indisponivel'] != null) ...[
            Alerta(Text(res!['indisponivel'].toString()), tom: 'perigo'),
            const SizedBox(height: 14)
          ],
          if (_q.isEmpty)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
                child: Column(children: [
                  const Text('Nenhuma busca ainda.',
                      style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _campo,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                              hintText: 'Nome, CPF, telefone ou contrato'),
                          onSubmitted: (v) => _buscar(v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () => _buscar(_campo.text),
                          child: const Text('Buscar')),
                    ]),
                  ),
                ]),
              ),
            )
          else if (_carregando && res == null)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()))
          else if (res?['curta'] == true)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                        child:
                            Text('Digite ao menos 3 caracteres para buscar.'))))
          else if (res != null && res['indisponivel'] == null && itens.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  Text('Nenhum devedor encontrado para “$_q”.',
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                      'CPF e telefone podem ser digitados com ou sem pontuação. Contrato precisa ser o número completo.',
                      style: TextStyle(color: p.muted)),
                ]),
              ),
            )
          else if (itens.isNotEmpty) ...[
            Text('${_milhar(total)} resultado${total == 1 ? '' : 's'}',
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _carregando ? .5 : 1,
              child: Column(children: [
                for (final it in itens)
                  _Resultado(
                      it, () => setState(() => _fichaId = it['id'] as int))
              ]),
            ),
            if (pages > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton(
                      onPressed: _page > 1 && !_carregando
                          ? () => _buscar(_q, page: _page - 1)
                          : null,
                      child: const Text('Anterior')),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Página $_page de $pages',
                          style: TextStyle(color: p.muted))),
                  OutlinedButton(
                      onPressed: _page < pages && !_carregando
                          ? () => _buscar(_q, page: _page + 1)
                          : null,
                      child: const Text('Próxima')),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

String _milhar(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Um resultado da busca (`.cb-res` do portal).
class _Resultado extends StatelessWidget {
  final Map<String, dynamic> d;
  final VoidCallback abrir;
  const _Resultado(this.d, this.abrir);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final atraso = (d['atraso'] as num?)?.toInt() ?? 0;
    final ult = d['ultimo'] as Map?;
    Widget chip(String? rot, String valor, {String? tom}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: tom != null ? fundoTom(context, tom) : p.surface,
              borderRadius: BorderRadius.circular(6)),
          child: Text.rich(
            TextSpan(children: [
              if (rot != null)
                TextSpan(text: '$rot ', style: TextStyle(color: p.muted)),
              TextSpan(text: valor),
            ]),
            style: TextStyle(
                fontSize: 12.5,
                color: tom != null ? tinta(context, tom) : p.text),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CartaoFaixa(
        cor: atraso > 0 ? p.danger : p.primary,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: LinkTexto((d['nome'] ?? '').toString(), abrir,
                    tam: 17, sublinhado: false)),
            Text((d['total'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 2),
          Text((d['credor'] ?? '').toString(),
              style: TextStyle(color: p.muted, fontSize: 13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            chip('CPF/CNPJ', (d['doc'] ?? '').toString()),
            chip('Títulos', '${d['titulos'] ?? 0}'),
            if (atraso > 0)
              chip('Atraso', '${_milhar(atraso)} dias', tom: 'perigo')
            else if (d['em_dia'] == true)
              chip(null, 'Em dia', tom: 'ok'),
            if ((d['local'] ?? '').toString().isNotEmpty)
              chip(null, d['local'].toString()),
          ]),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: p.cardBorder)),
          Row(children: [
            Expanded(
              child: ult != null
                  ? Row(children: [
                      PontoClasse((ult['classe'] ?? '').toString()),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Último acionamento: '),
                            TextSpan(
                                text: (ult['tipo'] ?? '').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            TextSpan(
                                text:
                                    ' em ${ult['quando']}${(ult['autor'] ?? '').toString().isNotEmpty ? ' · ${ult['autor']}' : ''}'),
                          ]),
                          style: TextStyle(color: p.muted, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ])
                  : Row(children: [
                      PontoClasse(''),
                      Text('Dívida sem acionamento',
                          style: TextStyle(color: p.muted, fontSize: 13))
                    ]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              onPressed: abrir,
              child: const Text('Ver ficha'),
            ),
          ]),
        ]),
      ),
    );
  }
}

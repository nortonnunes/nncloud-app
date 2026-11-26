// A busca do devedor no alto da tela, na barra do menu — como no portal do Tele
// Atendimento (`atend-busca.js`): a partir de 3 letras mostra sugestões (clicar
// abre a ficha); Enter faz a busca completa na aba Atendimento.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../servicos/controle.dart';
import '../../tema.dart';
import 'atendimento.dart';
import 'atendimento_api.dart';

class BuscaDevedor extends StatefulWidget {
  final Controle c;

  /// Leva a casca para a aba Atendimento.
  final VoidCallback irParaAtendimento;
  const BuscaDevedor(this.c, {super.key, required this.irParaAtendimento});
  @override
  State<BuscaDevedor> createState() => _BuscaDevedorState();
}

class _BuscaDevedorState extends State<BuscaDevedor> {
  late final AtendimentoApi _api = AtendimentoApi(widget.c.api);
  final _ctl = TextEditingController();
  final _foco = FocusNode();

  static const _min = 3;
  static const _atraso = Duration(milliseconds: 250);

  @override
  void dispose() {
    _ctl.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<Iterable<Map<String, dynamic>>> _opcoes(TextEditingValue v) async {
    final q = v.text.trim();
    if (q.length < _min) return const [];
    await Future<void>.delayed(_atraso);
    if (_ctl.text.trim() != q) return const []; // a pessoa continuou digitando
    try {
      final r = await _api.sugestoes(q);
      return _ctl.text.trim() == q ? r : const [];
    } catch (_) {
      return const [];
    }
  }

  void _buscar(String q) {
    if (q.trim().isEmpty) return;
    widget.irParaAtendimento();
    Atendimento.pedido.value = PedidoAtendimento.busca(q.trim());
    _foco.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 340,
      child: RawAutocomplete<Map<String, dynamic>>(
        textEditingController: _ctl,
        focusNode: _foco,
        displayStringForOption: (_) => '',
        optionsBuilder: _opcoes,
        onSelected: (m) {
          _ctl.clear();
          _foco.unfocus();
          widget.irParaAtendimento();
          Atendimento.pedido.value = PedidoAtendimento.ficha(m['id'] as int);
        },
        fieldViewBuilder: (context, ctl, foco, _) => SizedBox(
          height: 38,
          child: TextField(
            controller: ctl,
            focusNode: foco,
            textInputAction: TextInputAction.search,
            onSubmitted: _buscar,
            style: TextStyle(
                fontSize: 14, color: escuro ? p.text : const Color(0xFF1F2937)),
            decoration: InputDecoration(
              hintText: 'Nome, CPF, telefone ou contrato',
              hintStyle: TextStyle(
                  color: escuro ? p.muted : const Color(0xFF6B7280),
                  fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 19, color: escuro ? p.muted : const Color(0xFF6B7280)),
              filled: true,
              fillColor: escuro ? p.card : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: p.primary, width: 1.6)),
            ),
          ),
        ),
        optionsViewBuilder: (context, escolher, opcoes) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 8,
              color: p.card,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 420, maxHeight: 380),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final o in opcoes)
                      InkWell(
                        onTap: () => escolher(o),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text((o['nome'] ?? '').toString(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis),
                                    Text('${o['doc']} · ${o['credor']}',
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                  ]),
                            ),
                            const SizedBox(width: 10),
                            Text((o['total'] ?? '').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                        ),
                      ),
                    InkWell(
                      onTap: () => _buscar(_ctl.text),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        child: Text(
                            'Ver todos os resultados para “${_ctl.text.trim()}”',
                            style: TextStyle(
                                color: p.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

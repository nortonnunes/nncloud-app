// As dez abas da ficha — as mesmas do portal (`call/_ficha_<aba>.php`), com os
// mesmos campos: cada ação manda exatamente o que o formulário de lá manda.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tema.dart';
import 'ficha.dart';
import 'ui.dart';

Widget corpoDaAba(String aba, FichaCtx ctx) {
  final k = ValueKey('${ctx.id}-$aba');
  return switch (aba) {
    'acionamento' => AbaAcionamento(ctx, key: k),
    'digital' => AbaDigital(ctx, key: k),
    'agenda' => AbaAgenda(ctx, key: k),
    'localizacao' => AbaLocalizacao(ctx, key: k),
    'referencias' => AbaReferencias(ctx, key: k),
    'cadastro' => AbaCadastro(ctx, key: k),
    'documentos' => AbaDocumentos(ctx, key: k),
    'propostas' => AbaPropostas(ctx, key: k),
    'financeiro' => AbaFinanceiro(ctx, key: k),
    'whatsapp' => AbaWhatsapp(ctx, key: k),
    _ => const SizedBox.shrink(),
  };
}

List<Map<String, dynamic>> _lista(dynamic v) => ((v as List?) ?? const [])
    .map((e) => (e as Map).cast<String, dynamic>())
    .toList();
Map<String, String> _mapa(dynamic v) => ((v as Map?) ?? const {})
    .map((k, x) => MapEntry(k.toString(), x.toString()));
String _s(dynamic v) => (v ?? '').toString();

/// Botão principal das abas (o `.btn` do portal), travado enquanto envia.
class _Enviar extends StatelessWidget {
  final String rotulo;
  final bool enviando;
  final VoidCallback onPressed;
  const _Enviar(this.rotulo, this.enviando, this.onPressed);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
            onPressed: enviando ? null : onPressed,
            child: Text(enviando ? 'Enviando…' : rotulo)),
      );
}

/// Item de lista com borda (`.cb-lista-item`).
class _Item extends StatelessWidget {
  final Widget child;
  final List<Widget> acoes;
  final bool apagado;
  const _Item(
      {required this.child, this.acoes = const [], this.apagado = false});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: apagado ? .65 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border: Border.all(color: context.pal.cardBorder),
              borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: child),
            if (acoes.isNotEmpty) Wrap(spacing: 6, children: acoes),
          ]),
        ),
      );
}

Widget _mudo(BuildContext context, String s, {double tam = 12.5}) =>
    Text(s, style: TextStyle(color: context.pal.muted, fontSize: tam));

/* ============================== Acionamento ============================== */

class AbaAcionamento extends StatefulWidget {
  final FichaCtx ctx;
  const AbaAcionamento(this.ctx, {super.key});
  @override
  State<AbaAcionamento> createState() => _AbaAcionamentoState();
}

class _AbaAcionamentoState extends State<AbaAcionamento> {
  final _texto = TextEditingController();
  final _foco = FocusNode();
  int? _tipo;
  bool _enviando = false;
  String? _hash; // o "#" sendo digitado (sem o #)

  Map<String, dynamic> get c => widget.ctx.conteudo;
  List<Map<String, dynamic>> get _tipos => _lista(c['tipos']);

  @override
  void initState() {
    super.initState();
    _texto.addListener(_olharHash);
  }

  @override
  void dispose() {
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  /// O "#" que está sendo digitado: o último antes do cursor, no início ou
  /// depois de espaço — como o `atend-ficha.js`.
  void _olharHash() {
    final sel = _texto.selection;
    final ate = sel.isValid ? sel.baseOffset : _texto.text.length;
    final antes = _texto.text.substring(0, ate.clamp(0, _texto.text.length));
    final m = RegExp(r'(?:^|\s)#([^\s#]*)$').firstMatch(antes);
    final novo = m?.group(1);
    if (novo != _hash) setState(() => _hash = novo);
  }

  void _escolher(Map<String, dynamic> t) {
    final sel = _texto.selection;
    final ate = sel.isValid ? sel.baseOffset : _texto.text.length;
    final antes = _texto.text.substring(0, ate);
    final i = antes.lastIndexOf('#');
    final novo = _texto.text.substring(0, i) + _texto.text.substring(ate);
    _texto.value = TextEditingValue(
        text: novo, selection: TextSelection.collapsed(offset: i));
    setState(() {
      _tipo = t['id'] as int;
      _hash = null;
    });
    _foco.requestFocus();
  }

  Future<void> _registrar() async {
    if (_tipo == null) {
      avisarTipo();
      return;
    }
    setState(() => _enviando = true);
    final ok = await widget.ctx.executar('/acionamento',
        widget.ctx.campos({'texto': _texto.text, 'tipo_id': '$_tipo'}));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _texto.clear();
        _tipo = null;
      }
    });
  }

  void avisarTipo() =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text(
              'Escolha o tipo do acionamento (digite # na caixa ou use a lista).'),
          behavior: SnackBarBehavior.floating,
          width: 520));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final filtrados = _hash == null
        ? const <Map<String, dynamic>>[]
        : _tipos
            .where((t) =>
                _s(t['nome']).toLowerCase().contains(_hash!.toLowerCase()))
            .take(8)
            .toList();
    final contagem = ((c['contagem'] as Map?) ?? const {});
    final fClasse = _s(c['f_classe']);
    final fMeus = c['f_meus'] == true;
    final eventos = _lista(c['eventos']);
    final classes = _mapa(c['classes']);

    Widget filtro(String rotulo, bool ativo, VoidCallback onTap,
            {IconData? icone, String? tom}) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ativo ? p.primary.withValues(alpha: .12) : null,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ativo ? p.primary : p.cardBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icone != null)
                  Icon(icone, size: 15, color: tinta(context, tom ?? 'neutro')),
                if (icone != null) const SizedBox(width: 5),
                Text(rotulo,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ativo
                            ? p.primary
                            : (tom != null ? tinta(context, tom) : p.text))),
              ]),
            ),
          ),
        );

    final linhas = <Widget>[];
    var diaAnterior = '';
    for (final ev in eventos) {
      if (ev['dia'] != diaAnterior) {
        diaAnterior = _s(ev['dia']);
        linhas.add(Padding(
            padding: const EdgeInsets.fromLTRB(36, 10, 0, 6),
            child: _mudo(context, _s(ev['dia_rotulo']), tam: 12)));
      }
      final classe = _s(ev['classe']);
      final tom = tomDaClasse(classe);
      linhas.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.card,
                border: Border.all(color: tinta(context, tom), width: 1.6)),
            child: Icon(iconeDaClasse(classe),
                size: 14, color: tinta(context, tom)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.cardBorder)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(_s(ev['tipo']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                      _mudo(context, _s(ev['hora'])),
                    ]),
                    if (_s(ev['texto']).isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(_s(ev['texto']))),
                    const SizedBox(height: 4),
                    Row(children: [
                      _mudo(context, _s(ev['autor'])),
                      if (ev['meu'] == true) const Etiqueta('você'),
                      if (ev['automatico'] == true)
                        const Etiqueta('automático'),
                    ]),
                  ]),
            ),
          ),
        ]),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _registrar,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _registrar,
        },
        child: TextField(
          controller: _texto,
          focusNode: _foco,
          minLines: 3,
          maxLines: 8,
          maxLength: (c['max_texto'] as num?)?.toInt(),
          decoration: const InputDecoration(
              hintText:
                  'O que está acontecendo? Digite # para escolher o tipo do evento.',
              counterText: ''),
        ),
      ),
      if (filtrados.isNotEmpty)
        Card(
          margin: const EdgeInsets.only(top: 4),
          elevation: 3,
          child: Column(children: [
            for (final t in filtrados)
              ListTile(
                dense: true,
                leading: PontoClasse(_s(t['classe'])),
                minLeadingWidth: 10,
                title: Text(_s(t['nome'])),
                onTap: () => _escolher(t),
              ),
          ]),
        ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: CampoForm(
            'Tipo do evento',
            DropdownButtonFormField<int>(
              initialValue: _tipo,
              key: ValueKey(_tipo),
              isExpanded: true,
              hint: const Text('— escolha ou digite # —'),
              items: [
                for (final t in _tipos)
                  DropdownMenuItem(
                      value: t['id'] as int,
                      child:
                          Text(_s(t['nome']), overflow: TextOverflow.ellipsis))
              ],
              onChanged: (v) => setState(() => _tipo = v),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
            onPressed: _enviando ? null : _registrar,
            child: Text(_enviando ? 'Registrando…' : 'Registrar evento')),
      ]),
      if (_tipos.isEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _mudo(context,
                'Nenhum tipo de acionamento ativo. A coordenação cadastra os tipos em Sistema → Tele Atendimento.')),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(
            child: Text('Linha do tempo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        filtro('Todos ${contagem['total'] ?? 0}', fClasse.isEmpty,
            () => widget.ctx.filtrar('', fMeus)),
        for (final k in ['positivo', 'negativo', 'neutro'])
          Tooltip(
            message: classes[k] ?? k,
            child: filtro('${contagem[k] ?? 0}', fClasse == k,
                () => widget.ctx.filtrar(k, fMeus),
                icone: iconeDaClasse(k), tom: tomDaClasse(k)),
          ),
        filtro('Só os meus', fMeus, () => widget.ctx.filtrar(fClasse, !fMeus)),
      ]),
      const SizedBox(height: 10),
      if (eventos.isEmpty)
        CaixaVazia((contagem['total'] ?? 0) == 0
            ? 'Dívida sem acionamento. O primeiro registro aparece aqui.'
            : 'Nenhum evento com este filtro.')
      else ...[
        ...linhas,
        if (c['cortado'] == true)
          _mudo(context, 'Mostrando os 300 eventos mais recentes.'),
      ],
    ]);
  }
}

/* ============================== Digital ============================== */

class AbaDigital extends StatefulWidget {
  final FichaCtx ctx;
  const AbaDigital(this.ctx, {super.key});
  @override
  State<AbaDigital> createState() => _AbaDigitalState();
}

class _AbaDigitalState extends State<AbaDigital> {
  late final Map<String, String> _canais = _mapa(widget.ctx.conteudo['canais']);
  late final Map<String, String> _direcoes =
      _mapa(widget.ctx.conteudo['direcoes']);
  late String _canal =
      _canais.keys.isNotEmpty ? _canais.keys.first : 'whatsapp';
  late String _direcao =
      _direcoes.keys.isNotEmpty ? _direcoes.keys.first : 'enviado';
  late final _destino =
      TextEditingController(text: _s(widget.ctx.conteudo['destino']));
  final _assunto = TextEditingController();
  final _conteudo = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _destino.dispose();
    _assunto.dispose();
    _conteudo.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    setState(() => _enviando = true);
    final ok = await widget.ctx.executar(
        '/digital',
        widget.ctx.campos({
          'canal': _canal,
          'direcao': _direcao,
          'destino': _destino.text,
          'assunto': _assunto.text,
          'conteudo': _conteudo.text,
        }));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _assunto.clear();
        _conteudo.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final itens = _lista(widget.ctx.conteudo['itens']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Alerta(Text.rich(TextSpan(children: [
        TextSpan(
            text:
                'Registre aqui o contato feito por fora (WhatsApp, e-mail, SMS). A mensagem '),
        TextSpan(
            text: 'não é enviada',
            style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(
            text:
                ' pelo sistema — fica só o registro, que também entra na linha do tempo.'),
      ]))),
      const SizedBox(height: 14),
      LinhaForm([
        (
          3,
          CampoForm(
              'Canal',
              DropdownButtonFormField<String>(
                initialValue: _canal,
                isExpanded: true,
                items: [
                  for (final e in _canais.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value))
                ],
                onChanged: (v) => setState(() => _canal = v ?? _canal),
              ))
        ),
        (
          4,
          CampoForm(
              'Direção',
              DropdownButtonFormField<String>(
                initialValue: _direcao,
                isExpanded: true,
                items: [
                  for (final e in _direcoes.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value))
                ],
                onChanged: (v) => setState(() => _direcao = v ?? _direcao),
              ))
        ),
        (
          5,
          CampoForm(
              'Número / e-mail',
              TextField(
                  controller: _destino,
                  maxLength: 190,
                  decoration: const InputDecoration(counterText: '')))
        ),
      ]),
      LinhaForm([
        (
          12,
          CampoForm(
              'Assunto',
              TextField(
                  controller: _assunto,
                  maxLength: 190,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: boleto de setembro', counterText: '')))
        )
      ]),
      LinhaForm([
        (
          12,
          CampoForm(
              'Conteúdo',
              TextField(
                  controller: _conteudo,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      hintText:
                          'O que foi enviado ou o que o devedor respondeu')))
        )
      ]),
      _Enviar('Registrar contato', _enviando, _registrar),
      TituloSecao('Histórico digital (${itens.length})'),
      if (itens.isEmpty) const CaixaVazia('Nenhum contato digital registrado.'),
      for (final d in itens)
        _Item(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_s(d['canal']),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Etiqueta(d['recebido'] == true ? 'recebido' : 'enviado'),
              if (_s(d['destino']).isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _mudo(context, _s(d['destino']))),
            ]),
            if (_s(d['assunto']).isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_s(d['assunto']),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
            if (_s(d['conteudo']).isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(_s(d['conteudo']))),
            const SizedBox(height: 4),
            _mudo(context, '${_s(d['autor'])} · ${_s(d['quando'])}'),
          ]),
        ),
    ]);
  }
}

/* ============================== Agenda ============================== */

class AbaAgenda extends StatefulWidget {
  final FichaCtx ctx;
  const AbaAgenda(this.ctx, {super.key});
  @override
  State<AbaAgenda> createState() => _AbaAgendaState();
}

class _AbaAgendaState extends State<AbaAgenda> {
  late String _data = _s(widget.ctx.conteudo['amanha']);
  TimeOfDay _hora = const TimeOfDay(hour: 10, minute: 0);
  final _motivo = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  String get _horaTxt =>
      '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}';

  Future<void> _agendar() async {
    setState(() => _enviando = true);
    final ok = await widget.ctx.executar(
        '/agenda',
        widget.ctx
            .campos({'data': _data, 'hora': _horaTxt, 'motivo': _motivo.text}));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) _motivo.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final itens = _lista(widget.ctx.conteudo['itens']);
    final hoje =
        DateTime.tryParse(_s(widget.ctx.conteudo['hoje'])) ?? DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Agendar retorno'),
      LinhaForm([
        (
          3,
          CampoForm(
              'Data *',
              CampoData(
                  valor: _data,
                  minimo: hoje,
                  aoMudar: (v) => setState(() => _data = v)))
        ),
        (
          2,
          CampoForm(
              'Hora *',
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final h = await showTimePicker(
                      context: context, initialTime: _hora);
                  if (h != null) setState(() => _hora = h);
                },
                child: InputDecorator(
                    decoration: const InputDecoration(
                        suffixIcon: Icon(Icons.schedule_rounded, size: 18)),
                    child: Text(_horaTxt)),
              ))
        ),
        (
          7,
          CampoForm(
              'Motivo',
              TextField(
                  controller: _motivo,
                  maxLength: 255,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: confirmar pagamento do boleto',
                      counterText: '')))
        ),
      ]),
      _Enviar('Agendar', _enviando, _agendar),
      const TituloSecao('Retornos'),
      if (itens.isEmpty)
        const CaixaVazia('Nenhum retorno agendado para esta dívida.'),
      for (final a in itens)
        _Item(
          apagado: a['status'] != 'pendente',
          acoes: a['status'] == 'pendente'
              ? [
                  FilledButton(
                    onPressed: () => widget.ctx.executar(
                        '/agenda/status',
                        widget.ctx.campos(
                            {'agenda_id': '${a['id']}', 'status': 'feito'})),
                    child: const Text('Feito'),
                  ),
                  OutlinedButton(
                    onPressed: () => widget.ctx.executar(
                        '/agenda/status',
                        widget.ctx.campos({
                          'agenda_id': '${a['id']}',
                          'status': 'cancelado'
                        })),
                    child: const Text('Cancelar'),
                  ),
                ]
              : const [],
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(_s(a['quando']),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Pilula(_s(a['rotulo']),
                      tom: a['atrasado'] == true
                          ? 'perigo'
                          : (a['status'] == 'feito'
                              ? 'ok'
                              : (a['status'] == 'pendente'
                                  ? 'info'
                                  : 'neutro'))),
                ]),
            if (_s(a['motivo']).isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_s(a['motivo']))),
            const SizedBox(height: 4),
            _mudo(context,
                'Agendado por ${_s(a['autor'])} em ${_s(a['criado'])}'),
          ]),
        ),
    ]);
  }
}

/* ============================== Localização ============================== */

class AbaLocalizacao extends StatefulWidget {
  final FichaCtx ctx;
  const AbaLocalizacao(this.ctx, {super.key});
  @override
  State<AbaLocalizacao> createState() => _AbaLocalizacaoState();
}

class _AbaLocalizacaoState extends State<AbaLocalizacao> {
  final _numero = TextEditingController();
  final _obs = TextEditingController();
  String _tipo = '';
  bool _enviando = false;
  final Map<int, String> _marca = {}; // telefone → situação escolhida

  @override
  void dispose() {
    _numero.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _incluir() async {
    setState(() => _enviando = true);
    final ok = await widget.ctx.executar(
        '/telefone',
        widget.ctx.campos(
            {'numero': _numero.text, 'tipo': _tipo, 'observacao': _obs.text}));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _numero.clear();
        _obs.clear();
        _tipo = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = widget.ctx.conteudo;
    final arquivo = _lista(c['arquivo_fones']);
    final tels = _lista(c['telefones']);
    final opcoes = _mapa(c['opcoes']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Endereço'),
      if (c['tem_endereco'] != true)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          _mudo(
              context, 'Nenhum endereço na planilha. Dá para completar na aba ',
              tam: 13.5),
          LinkTexto('Cadastro', () => widget.ctx.irPara('cadastro')),
          _mudo(context, '.', tam: 13.5),
        ])
      else ...[
        SelectableText(_s(c['endereco']).isEmpty ? '—' : _s(c['endereco'])),
        if (_s(c['cidade_cep']).isNotEmpty)
          _mudo(context, _s(c['cidade_cep']), tam: 13.5),
      ],
      if (_s(c['email']).isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText('E-mail: ${_s(c['email'])}',
                style: TextStyle(color: p.muted))),
      if (arquivo.isNotEmpty) ...[
        const SizedBox(height: 14),
        Alerta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Telefones no arquivo, fora da lista de discagem:',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final t in arquivo)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SelectableText(_s(t['fone']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_s(t['rotulo']),
                        style: const TextStyle(fontSize: 11.5))),
                BotaoUsar(widget.ctx, _s(t['numero']), _s(t['rotulo'])),
              ]),
            ),
        ])),
      ],
      TituloSecao('Telefones (${tels.length})'),
      if (tels.isNotEmpty) ...[
        _mudo(context, 'Todos'),
        Row(children: [
          Expanded(child: SelectableText(_s(c['todos']))),
          BotaoCopiar(_s(c['todos'])),
        ]),
        const SizedBox(height: 10),
      ],
      if (tels.isEmpty)
        const CaixaVazia(
            'Nenhum telefone. Inclua abaixo o número que o devedor informar.')
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              border: Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            _cabecalhoTabela(context, const [
              'Número',
              'Tipo',
              'Situação',
              'Tentativas',
              'Última',
              'Marcar resultado'
            ], const [
              3,
              2,
              2,
              1,
              2,
              4
            ]),
            for (final t in tels)
              Opacity(
                opacity:
                    t['status'] == 'invalido' || t['status'] == 'nao_perturbe'
                        ? .6
                        : 1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: p.cardBorder))),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(_s(t['fone']),
                                  style: TextStyle(
                                      color: p.primary,
                                      fontWeight: FontWeight.w700)),
                              if (_s(t['observacao']).isNotEmpty)
                                _mudo(context, _s(t['observacao']), tam: 11.5),
                            ])),
                    Expanded(
                        flex: 2,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_s(t['tipo'])),
                              if (t['informado'] == true)
                                _mudo(context, 'informado na ligação',
                                    tam: 11.5),
                            ])),
                    Expanded(
                        flex: 2,
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Pilula(_s(t['rotulo']),
                                tom: _tomTel(_s(t['status']))))),
                    Expanded(
                        flex: 1,
                        child: Text('${t['tentativas']}',
                            textAlign: TextAlign.right)),
                    Expanded(
                        flex: 2,
                        child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(_s(t['ultima']),
                                style: const TextStyle(fontSize: 12.5)))),
                    Expanded(
                        flex: 4,
                        child: Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _marca[t['id']] ??
                                  (opcoes.containsKey(_s(t['status']))
                                      ? _s(t['status'])
                                      : opcoes.keys.first),
                              isExpanded: true,
                              items: [
                                for (final e in opcoes.entries)
                                  DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value,
                                          style: const TextStyle(fontSize: 13)))
                              ],
                              onChanged: (v) => setState(
                                  () => _marca[t['id'] as int] = v ?? ''),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => widget.ctx.executar(
                                '/telefone/marcar',
                                widget.ctx.campos({
                                  'telefone_id': '${t['id']}',
                                  'status': _marca[t['id']] ??
                                      (opcoes.containsKey(_s(t['status']))
                                          ? _s(t['status'])
                                          : opcoes.keys.first),
                                })),
                            child: const Text('Marcar'),
                          ),
                        ])),
                  ]),
                ),
              ),
          ]),
        ),
      const TituloSecao('Incluir telefone'),
      LinhaForm([
        (
          4,
          CampoForm(
              'Número com DDD *',
              TextField(
                  controller: _numero,
                  maxLength: 20,
                  decoration: const InputDecoration(
                      hintText: '(21) 99999-9999', counterText: '')))
        ),
        (
          3,
          CampoForm(
              'Tipo',
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '', child: Text('Detectar')),
                  DropdownMenuItem(value: 'celular', child: Text('Celular')),
                  DropdownMenuItem(value: 'fixo', child: Text('Fixo')),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? ''),
              ))
        ),
        (
          5,
          CampoForm(
              'Observação',
              TextField(
                  controller: _obs,
                  maxLength: 190,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: número do trabalho, após 18h',
                      counterText: '')))
        ),
      ]),
      _Enviar('Incluir telefone', _enviando, _incluir),
    ]);
  }
}

String _tomTel(String st) => switch (st) {
      'valido' => 'ok',
      'invalido' || 'nao_perturbe' => 'perigo',
      _ => 'neutro',
    };

Widget _cabecalhoTabela(
        BuildContext context, List<String> titulos, List<int> flex,
        {Set<int> direita = const {}}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: context.pal.surface,
      child: Row(children: [
        for (var i = 0; i < titulos.length; i++)
          Expanded(
            flex: flex[i],
            child: Padding(
              padding:
                  EdgeInsets.only(left: i == 4 && titulos.length == 6 ? 12 : 0),
              child: Text(titulos[i],
                  textAlign: direita.contains(i) || (titulos[i] == 'Tentativas')
                      ? TextAlign.right
                      : TextAlign.left,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.pal.muted)),
            ),
          ),
      ]),
    );

/* ============================== Referências ============================== */

class AbaReferencias extends StatefulWidget {
  final FichaCtx ctx;
  const AbaReferencias(this.ctx, {super.key});
  @override
  State<AbaReferencias> createState() => _AbaReferenciasState();
}

class _AbaReferenciasState extends State<AbaReferencias> {
  final _nome = TextEditingController();
  final _relacao = TextEditingController();
  final _tel = TextEditingController();
  final _email = TextEditingController();
  final _obs = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    for (final c in [_nome, _relacao, _tel, _email, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _incluir() async {
    setState(() => _enviando = true);
    final ok = await widget.ctx.executar(
        '/referencia',
        widget.ctx.campos({
          'nome': _nome.text,
          'relacao': _relacao.text,
          'telefone': _tel.text,
          'email': _email.text,
          'observacao': _obs.text,
        }));
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        for (final c in [_nome, _relacao, _tel, _email, _obs]) {
          c.clear();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final itens = _lista(widget.ctx.conteudo['itens']);
    final relacoes = ((widget.ctx.conteudo['relacoes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TituloSecao('Referências (${itens.length})'),
      if (itens.isEmpty) const CaixaVazia('Nenhuma referência cadastrada.'),
      for (final r in itens)
        _Item(
          acoes: [
            OutlinedButton(
              style:
                  OutlinedButton.styleFrom(foregroundColor: context.pal.danger),
              onPressed: () async {
                if (await confirmarAcao(
                    context, 'Excluir a referência "${_s(r['nome'])}"?',
                    sim: 'Excluir')) {
                  widget.ctx.executar('/referencia/excluir',
                      widget.ctx.campos({'referencia_id': '${r['id']}'}));
                }
              },
              child: const Text('Excluir'),
            ),
          ],
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_s(r['nome']),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_s(r['relacao']).isNotEmpty) Etiqueta(_s(r['relacao'])),
            ]),
            const SizedBox(height: 4),
            SelectableText([
              if (_s(r['fone']).isNotEmpty) _s(r['fone']),
              if (_s(r['email']).isNotEmpty) _s(r['email'])
            ].join(' · ')),
            if (_s(r['observacao']).isNotEmpty)
              _mudo(context, _s(r['observacao'])),
          ]),
        ),
      const TituloSecao('Incluir referência'),
      LinhaForm([
        (
          6,
          CampoForm(
              'Nome *',
              TextField(
                  controller: _nome,
                  maxLength: 190,
                  decoration: const InputDecoration(counterText: '')))
        ),
        (
          6,
          CampoForm(
              'Relação',
              TextField(
                controller: _relacao,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: 'Mãe, trabalho, vizinho…',
                  counterText: '',
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: 'Sugestões',
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    onSelected: (v) => _relacao.text = v,
                    itemBuilder: (_) => [
                      for (final r in relacoes)
                        PopupMenuItem(value: r, child: Text(r))
                    ],
                  ),
                ),
              ))
        ),
      ]),
      LinhaForm([
        (
          4,
          CampoForm(
              'Telefone',
              TextField(
                  controller: _tel,
                  maxLength: 20,
                  decoration: const InputDecoration(
                      hintText: '(21) 99999-9999', counterText: '')))
        ),
        (
          4,
          CampoForm(
              'E-mail',
              TextField(
                  controller: _email,
                  maxLength: 190,
                  decoration: const InputDecoration(counterText: '')))
        ),
        (
          4,
          CampoForm(
              'Observação',
              TextField(
                  controller: _obs,
                  maxLength: 255,
                  decoration: const InputDecoration(counterText: '')))
        ),
      ]),
      _Enviar('Incluir referência', _enviando, _incluir),
    ]);
  }
}

/* ============================== Cadastro ============================== */

class AbaCadastro extends StatefulWidget {
  final FichaCtx ctx;
  const AbaCadastro(this.ctx, {super.key});
  @override
  State<AbaCadastro> createState() => _AbaCadastroState();
}

class _AbaCadastroState extends State<AbaCadastro> {
  static const _chaves = [
    'nome',
    'cep',
    'rua',
    'numero',
    'complemento',
    'bairro',
    'cidade',
    'uf',
    'email'
  ];
  late final Map<String, TextEditingController> _c = {
    for (final k in _chaves)
      k: TextEditingController(
          text: _mapa(widget.ctx.conteudo['campos'])[k] ?? ''),
  };
  bool _enviando = false;
  String _cepSt = 'Digite o CEP para preencher o endereço.';
  late String _cepOriginal = _c['cep']!.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _c['cep']!.addListener(_olharCep);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Só consulta quando o CEP MUDA (abrir a ficha não pode sobrescrever o endereço conferido à mão).
  Future<void> _olharCep() async {
    final d = _c['cep']!.text.replaceAll(RegExp(r'\D'), '');
    if (d.length != 8 || d == _cepOriginal) return;
    _cepOriginal = d;
    setState(() => _cepSt = 'Buscando o endereço…');
    try {
      final r = await widget.ctx.api.cep(d);
      if (!mounted) return;
      if (r == null) {
        setState(
            () => _cepSt = 'CEP não encontrado. Preencha o endereço à mão.');
        return;
      }
      setState(() {
        if (_s(r['endereco']).isNotEmpty) _c['rua']!.text = _s(r['endereco']);
        if (_s(r['bairro']).isNotEmpty) _c['bairro']!.text = _s(r['bairro']);
        if (_s(r['cidade']).isNotEmpty) _c['cidade']!.text = _s(r['cidade']);
        if (_s(r['uf']).isNotEmpty) _c['uf']!.text = _s(r['uf']);
        _cepSt = 'Endereço preenchido. Confira e informe o número.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _cepSt = 'Não foi possível consultar o CEP agora.');
      }
    }
  }

  Future<void> _salvar() async {
    setState(() => _enviando = true);
    await widget.ctx.executar('/cadastro',
        widget.ctx.campos({for (final e in _c.entries) e.key: e.value.text}));
    if (mounted) setState(() => _enviando = false);
  }

  Widget _campo(String k, {int max = 120}) => TextField(
      controller: _c[k],
      maxLength: max,
      decoration: const InputDecoration(counterText: ''));

  @override
  Widget build(BuildContext context) {
    final c = widget.ctx.conteudo;
    final extras = _lista(c['extras']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Dados do devedor'),
      _mudo(context,
          'A correção vale para a ficha e vira evento na linha do tempo. A próxima planilha da operadora só sobrescreve o campo que trouxer preenchido.'),
      const SizedBox(height: 12),
      LinhaForm([
        (
          6,
          CampoForm(
              'CPF / CNPJ',
              Text(_s(c['doc']),
                  style: const TextStyle(fontWeight: FontWeight.w700)))
        ),
        (
          6,
          CampoForm(
              'Credor',
              Text(_s(c['credor']),
                  style: const TextStyle(fontWeight: FontWeight.w700)))
        ),
      ]),
      LinhaForm([
        (8, CampoForm('Nome *', _campo('nome', max: 190))),
        (4, CampoForm('CEP', _campo('cep', max: 9), dica: _cepSt)),
      ]),
      LinhaForm([
        (8, CampoForm('Logradouro', _campo('rua', max: 190))),
        (4, CampoForm('Número', _campo('numero', max: 20)))
      ]),
      LinhaForm([
        (4, CampoForm('Complemento', _campo('complemento'))),
        (4, CampoForm('Bairro', _campo('bairro'))),
        (3, CampoForm('Cidade', _campo('cidade'))),
        (1, CampoForm('UF', _campo('uf', max: 2))),
      ]),
      LinhaForm([
        (8, CampoForm('E-mail', _campo('email', max: 190))),
        (4, const SizedBox.shrink())
      ]),
      _Enviar('Salvar cadastro', _enviando, _salvar),
      if (extras.isNotEmpty) ...[
        const TituloSecao('Outras colunas da planilha'),
        _mudo(context,
            'O que a operadora mandou além dos campos padrão. Só leitura.'),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 10, children: [
          for (final x in extras)
            SizedBox(
              width: 260,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mudo(context, _s(x['rotulo']), tam: 11.5),
                    SelectableText(_s(x['valor']),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
            ),
        ]),
      ],
    ]);
  }
}

/* ============================== Documentos ============================== */

class AbaDocumentos extends StatefulWidget {
  final FichaCtx ctx;
  const AbaDocumentos(this.ctx, {super.key});
  @override
  State<AbaDocumentos> createState() => _AbaDocumentosState();
}

class _AbaDocumentosState extends State<AbaDocumentos> {
  File? _arquivo;
  final _titulo = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  List<String> get _ext =>
      ((widget.ctx.conteudo['extensoes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();

  Future<void> _escolher() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: _ext);
    final caminho = r?.files.single.path;
    if (caminho != null) setState(() => _arquivo = File(caminho));
  }

  Future<void> _anexar() async {
    if (_arquivo == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Escolha um arquivo.'),
          behavior: SnackBarBehavior.floating,
          width: 520));
      return;
    }
    setState(() => _enviando = true);
    // ⚠️ O devedor vai na URL (`?id=`), como no portal: num envio acima do limite o corpo chega vazio.
    final ok = await widget.ctx.executar('/documento', {'titulo': _titulo.text},
        arquivo: _arquivo, query: '?id=${widget.ctx.id}');
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _arquivo = null;
        _titulo.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final itens = _lista(widget.ctx.conteudo['itens']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Anexar documento'),
      LinhaForm([
        (
          6,
          CampoForm(
              'Arquivo *',
              Row(children: [
                OutlinedButton.icon(
                    onPressed: _escolher,
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: const Text('Escolher arquivo')),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        _arquivo == null
                            ? 'Nenhum arquivo escolhido'
                            : _arquivo!.uri.pathSegments.last,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted))),
              ]),
              dica:
                  'PDF, imagem, Word, Excel ou texto. Até ${_s(widget.ctx.conteudo['limite'])}.')
        ),
        (
          6,
          CampoForm(
              'Descrição',
              TextField(
                  controller: _titulo,
                  maxLength: 190,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: comprovante de pagamento',
                      counterText: '')))
        ),
      ]),
      _Enviar('Anexar', _enviando, _anexar),
      TituloSecao('Documentos (${itens.length})'),
      if (itens.isEmpty) const CaixaVazia('Nenhum documento anexado.'),
      for (final d in itens)
        _Item(
          acoes: [
            OutlinedButton(
              onPressed: () => salvarEAbrir(
                  context,
                  _s(d['original']),
                  (dest) => widget.ctx.api
                      .baixarDocumento(widget.ctx.id, d['id'] as int, dest)),
              child: const Text('Baixar'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: p.danger),
              onPressed: () async {
                if (await confirmarAcao(context,
                    'Excluir "${_s(d['titulo'])}"? O arquivo é apagado.',
                    sim: 'Excluir')) {
                  widget.ctx.executar('/documento/excluir',
                      widget.ctx.campos({'documento_id': '${d['id']}'}));
                }
              },
              child: const Text('Excluir'),
            ),
          ],
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_s(d['titulo']),
                style:
                    TextStyle(fontWeight: FontWeight.w700, color: p.primary)),
            if (_s(d['titulo']) != _s(d['original']))
              _mudo(context, _s(d['original'])),
            const SizedBox(height: 4),
            _mudo(context,
                '${_s(d['tamanho'])} · ${_s(d['autor'])} · ${_s(d['quando'])}'),
          ]),
        ),
    ]);
  }
}

/* ============================== Propostas ============================== */

/// "1.234,56" → 1234.56 (a mesma leitura do `atend-ficha.js`).
double numeroBr(String v) {
  var s = v.trim();
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  s = s.replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(s) ?? 0;
}

String brl(double v) {
  final neg = v < 0;
  final c = (v.abs() * 100).round();
  final inteiro = (c ~/ 100)
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '-' : ''}R\$ $inteiro,${(c % 100).toString().padLeft(2, '0')}';
}

/// A prévia da proposta, igual à do portal.
String previaProposta(
    {required double total,
    required double valor,
    required double entrada,
    required int parcelas}) {
  if (valor <= 0) return '';
  if (entrada > valor) return 'A entrada é maior que o valor proposto.';
  final n = parcelas < 1 ? 1 : parcelas;
  final partes = <String>[
    if (entrada > 0) 'Entrada de ${brl(entrada)}',
    '$n× de ${brl((valor - entrada) / n)}',
  ];
  if (total > 0 && valor < total) {
    final pct = ((1 - valor / total) * 100);
    var t = pct.toStringAsFixed(1).replaceAll('.', ',');
    if (t.endsWith(',0')) t = t.substring(0, t.length - 2);
    partes.add('$t% de desconto');
  }
  return partes.join(' · ');
}

class AbaPropostas extends StatefulWidget {
  final FichaCtx ctx;
  const AbaPropostas(this.ctx, {super.key});
  @override
  State<AbaPropostas> createState() => _AbaPropostasState();
}

class _AbaPropostasState extends State<AbaPropostas> {
  late List<Map<String, dynamic>> _titulos =
      _lista(widget.ctx.conteudo['titulos']);
  late Set<int> _marcados = {for (final t in _titulos) t['id'] as int};
  final _valor = TextEditingController();
  final _entrada = TextEditingController();
  final _parcelas = TextEditingController(text: '1');
  final _obs = TextEditingController();
  String _venc = '';
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_valor, _entrada, _parcelas]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(covariant AbaPropostas old) {
    super.didUpdateWidget(old);
    final novos = _lista(widget.ctx.conteudo['titulos']);
    if (novos.map((e) => e['id']).join(',') !=
        _titulos.map((e) => e['id']).join(',')) {
      _titulos = novos;
      _marcados = {for (final t in _titulos) t['id'] as int};
    }
  }

  @override
  void dispose() {
    for (final c in [_valor, _entrada, _parcelas, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _soma => _titulos
      .where((t) => _marcados.contains(t['id']))
      .fold(0.0, (s, t) => s + (t['valor'] as num).toDouble());

  Future<void> _registrar() async {
    setState(() => _enviando = true);
    final campos = widget.ctx.campos({
      'valor_proposto': _valor.text,
      'entrada': _entrada.text,
      'parcelas': _parcelas.text,
      'primeiro_venc': _venc,
      'observacao': _obs.text,
    });
    var i = 0;
    for (final id in _marcados) {
      campos['titulos[${i++}]'] = '$id';
    }
    final ok = await widget.ctx.executar('/proposta', campos);
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (ok) {
        _valor.clear();
        _entrada.clear();
        _parcelas.text = '1';
        _obs.clear();
        _venc = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final itens = _lista(widget.ctx.conteudo['itens']);
    final hoje =
        DateTime.tryParse(_s(widget.ctx.conteudo['hoje'])) ?? DateTime.now();
    final previa = previaProposta(
        total: _soma,
        valor: numeroBr(_valor.text),
        entrada: numeroBr(_entrada.text),
        parcelas: int.tryParse(_parcelas.text) ?? 1);
    final todos = _marcados.length == _titulos.length
        ? true
        : (_marcados.isEmpty ? false : null);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Nova proposta'),
      if (_titulos.isEmpty)
        const CaixaVazia('Sem títulos para negociar.')
      else ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border: Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _mudo(context, 'Títulos incluídos'),
            CheckboxListTile(
              dense: true,
              tristate: true,
              value: todos,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Todos',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onChanged: (_) => setState(() => _marcados = todos == true
                  ? {}
                  : {for (final t in _titulos) t['id'] as int}),
            ),
            for (final t in _titulos)
              CheckboxListTile(
                dense: true,
                value: _marcados.contains(t['id']),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => v == true
                    ? _marcados.add(t['id'] as int)
                    : _marcados.remove(t['id'])),
                title: Row(children: [
                  Text(_s(t['contrato'])),
                  const SizedBox(width: 10),
                  Expanded(child: _mudo(context, _s(t['venc']))),
                  Text(_s(t['valor_txt']),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            Align(
                alignment: Alignment.centerRight,
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Dívida escolhida: '),
                  TextSpan(
                      text: _marcados.isEmpty ? '—' : brl(_soma),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]))),
          ]),
        ),
        const SizedBox(height: 12),
        LinhaForm([
          (
            3,
            CampoForm(
                'Valor proposto *',
                TextField(
                    controller: _valor,
                    decoration: const InputDecoration(hintText: '0,00')))
          ),
          (
            3,
            CampoForm(
                'Entrada',
                TextField(
                    controller: _entrada,
                    decoration: const InputDecoration(hintText: '0,00')))
          ),
          (
            3,
            CampoForm(
                'Parcelas',
                TextField(
                    controller: _parcelas,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly]))
          ),
          (
            3,
            CampoForm(
                '1º vencimento',
                CampoData(
                    valor: _venc,
                    minimo: hoje,
                    vazio: 'dd/mm/aaaa',
                    aoMudar: (v) => setState(() => _venc = v)))
          ),
        ]),
        if (previa.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: p.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8)),
            child: Text(previa),
          ),
        LinhaForm([
          (
            12,
            CampoForm(
                'Observação',
                TextField(
                    controller: _obs,
                    maxLength: 500,
                    decoration: const InputDecoration(
                        hintText: 'Condições combinadas, forma de pagamento…',
                        counterText: '')))
          )
        ]),
        _Enviar('Registrar proposta', _enviando, _registrar),
      ],
      TituloSecao('Propostas (${itens.length})'),
      if (itens.isEmpty) const CaixaVazia('Nenhuma proposta registrada.'),
      for (final pr in itens) _CartaoProposta(widget.ctx, pr),
    ]);
  }
}

class _CartaoProposta extends StatelessWidget {
  final FichaCtx ctx;
  final Map<String, dynamic> p;
  const _CartaoProposta(this.ctx, this.p);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final st = _s(p['status']);
    final borda = switch (st) {
      'aceita' || 'quitada' => pal.success,
      'recusada' || 'quebrada' => pal.danger,
      _ => pal.primary,
    };
    Widget numero(String rotulo, String valor, [String? sub]) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _mudo(context, rotulo, tam: 11.5),
            Text(valor,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (sub != null) _mudo(context, sub, tam: 11.5),
          ]),
        );
    final trans = _lista(p['transicoes']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CartaoFaixa(
        cor: borda,
        raio: 10,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_s(p['rotulo']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                _mudo(context, '${_s(p['quando'])} · ${_s(p['autor'])}'),
                Etiqueta(_s(p['origem'])),
              ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            numero('Dívida', _s(p['divida'])),
            numero('Proposta', _s(p['proposta']), p['desconto'] as String?),
            numero('Pagamento', _s(p['pagamento']), p['primeiro'] as String?),
          ]),
          if (_s(p['observacao']).isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_s(p['observacao']))),
          const SizedBox(height: 6),
          _mudo(context, 'Títulos: ${_s(p['titulos'])}'),
          if (trans.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final t in trans)
                t['estilo'] == 'primario'
                    ? FilledButton(
                        onPressed: () => _mudar(context, t),
                        child: Text(_s(t['rotulo'])))
                    : OutlinedButton(
                        style: t['estilo'] == 'perigo'
                            ? OutlinedButton.styleFrom(
                                foregroundColor: pal.danger)
                            : null,
                        onPressed: () => _mudar(context, t),
                        child: Text(_s(t['rotulo'])),
                      ),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _mudar(BuildContext context, Map<String, dynamic> t) async {
    if (!await confirmarAcao(
        context, '${_s(t['rotulo'])}? A mudança entra na linha do tempo.')) {
      return;
    }
    ctx.executar('/proposta/status',
        ctx.campos({'proposta_id': '${p['id']}', 'status': _s(t['para'])}));
  }
}

/* ============================== Financeiro ============================== */

class AbaFinanceiro extends StatelessWidget {
  final FichaCtx ctx;
  const AbaFinanceiro(this.ctx, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = ctx.conteudo;
    final aging = _lista(c['aging']);
    final titulos = _lista(c['titulos']);
    final corFaixa = {
      'a_vencer': p.success,
      'ate30': tinta(context, 'alerta'),
      'ate90': p.danger,
      'mais90': p.danger
    };
    const flex = [3, 2, 2, 2, 1, 2, 2];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TituloSecao('Envelhecimento da dívida'),
      Row(children: [
        for (var i = 0; i < aging.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: CartaoFaixa(
              cor: corFaixa[aging[i]['chave']] ?? p.cardBorder,
              topo: true,
              largura: 3,
              raio: 10,
              fundo: p.surface,
              comBorda: false,
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mudo(context, _s(aging[i]['rotulo']), tam: 11.5),
                    Text(_s(aging[i]['valor']),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
            ),
          ),
        ],
      ]),
      TituloSecao(
          'Títulos (${c['n_titulos'] ?? 0})${(c['fora'] ?? 0) > 0 ? ' + ${c['fora']} fora da carteira' : ''}'),
      if (titulos.isEmpty)
        const CaixaVazia('Nenhum título importado para esta pessoa.')
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              border: Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            _cabecalhoTabela(
                context,
                const [
                  'Contrato',
                  'Título',
                  'Competência',
                  'Vencimento',
                  'Atraso',
                  'Situação',
                  'Valor'
                ],
                flex,
                direita: const {4, 6}),
            for (final t in titulos)
              Opacity(
                opacity: t['fora_desde'] != null ? .6 : 1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: p.cardBorder))),
                  child: Row(children: [
                    Expanded(
                        flex: flex[0],
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(_s(t['contrato'])),
                              if (t['fora_desde'] != null)
                                Tooltip(
                                  message:
                                      'Não veio na última carga completa da operadora (paga ou retirada). Não entra nos totais.',
                                  child: Pilula(
                                      'Fora da carteira desde ${t['fora_desde']}'),
                                ),
                            ])),
                    Expanded(flex: flex[1], child: Text(_s(t['titulo']))),
                    Expanded(flex: flex[2], child: Text(_s(t['competencia']))),
                    Expanded(flex: flex[3], child: Text(_s(t['vencimento']))),
                    Expanded(
                        flex: flex[4],
                        child: Text(
                            (t['atraso'] as num? ?? 0) > 0
                                ? '${t['atraso']} d'
                                : '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: (t['atraso'] as num? ?? 0) > 0
                                    ? tinta(context, 'perigo')
                                    : null))),
                    Expanded(
                        flex: flex[5],
                        child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(_s(t['situacao'])))),
                    Expanded(
                        flex: flex[6],
                        child: Text(_s(t['valor']),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()]))),
                  ]),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.cardBorder))),
              child: Row(children: [
                const Expanded(
                    child: Text('Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 16),
                Text(_s(c['total']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/* ============================== WhatsApp ============================== */

class AbaWhatsapp extends StatelessWidget {
  final FichaCtx ctx;
  const AbaWhatsapp(this.ctx, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = ctx.conteudo;
    final negs = _lista(c['negs']);
    final convs = _lista(c['conversas']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c['aviso'] != null) Alerta(Text(_s(c['aviso']))),
      TituloSecao('Negociações (${negs.length})'),
      if (negs.isEmpty)
        const CaixaVazia('Nenhuma negociação pelo WhatsApp com esta pessoa.'),
      for (final n in negs)
        _Item(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Pilula(_s(n['rotulo']), tom: _s(n['tom'])),
                  Etiqueta(_s(n['quem'])),
                  _mudo(context, _s(n['quando'])),
                ]),
            if (n['acordo'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_s(n['acordo']),
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            if (_s(n['motivo']).isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _mudo(context, _s(n['motivo']))),
          ]),
        ),
      TituloSecao('Conversas (${convs.length})'),
      if (convs.isEmpty)
        const CaixaVazia('Nenhuma conversa do WhatsApp ligada a esta ficha.'),
      for (var i = 0; i < convs.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              border: Border.all(color: p.cardBorder),
              borderRadius: BorderRadius.circular(10)),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            shape: const Border(),
            title: Text(_s(convs[i]['wa_id']),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: _mudo(
                context,
                [
                  _s(convs[i]['modo']),
                  if (_s(convs[i]['agente']).isNotEmpty) _s(convs[i]['agente']),
                  if (_s(convs[i]['ultima']).isNotEmpty)
                    'última mensagem ${_s(convs[i]['ultima'])}',
                ].join(' · ')),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (_lista(convs[i]['mensagens']).isEmpty)
                _mudo(context, 'Sem mensagens.'),
              for (final m in _lista(convs[i]['mensagens']))
                Align(
                  alignment: m['saida'] == true
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: m['saida'] == true
                          ? p.primary.withValues(alpha: .12)
                          : p.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m['saida'] == true && _s(m['autor']).isNotEmpty)
                            Text(_s(m['autor']),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: p.primary)),
                          SelectableText(_s(m['texto'])),
                          Align(
                              alignment: Alignment.centerRight,
                              child: _mudo(context, _s(m['hora']), tam: 11)),
                        ]),
                  ),
                ),
            ],
          ),
        ),
    ]);
  }
}

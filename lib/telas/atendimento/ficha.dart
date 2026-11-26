// A ficha do devedor — igual à do portal do Tele Atendimento: as ABAS à
// esquerda e o PAINEL da dívida à direita, fixo em todas as abas (o atendente
// está com o devedor na linha e não pode perder de vista quanto ele deve e a quem).
//
// ⚠️ Só a aba aberta vai ao servidor (como os links `?aba=` do portal): o banco
// de cobrança é remoto e cada aba é mais uma ida a ele.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../tema.dart';
import '../../widgets/comum.dart';
import 'abas.dart';
import 'atendimento_api.dart';
import 'ui.dart';

/// O que as abas recebem da ficha: os dados da aba aberta e como agir.
class FichaCtx {
  final int id;
  final Map<String, dynamic> dados; // a resposta inteira da ficha
  final AtendimentoApi api;
  final Future<bool> Function(String caminho, Map<String, String> campos,
      {File? arquivo, String query}) executar;
  final void Function(String aba) irPara;
  final void Function(String classe, bool meus) filtrar;
  const FichaCtx(
      {required this.id,
      required this.dados,
      required this.api,
      required this.executar,
      required this.irPara,
      required this.filtrar});

  Map<String, dynamic> get conteudo =>
      ((dados['conteudo'] as Map?) ?? const {}).cast<String, dynamic>();
  Map<String, dynamic> get painel =>
      ((dados['painel'] as Map?) ?? const {}).cast<String, dynamic>();

  /// Os campos fixos de toda ação: o devedor.
  Map<String, String> campos([Map<String, String> extra = const {}]) =>
      {'devedor_id': '$id', ...extra};
}

class FichaDevedor extends StatefulWidget {
  final AtendimentoApi api;
  final int id;
  final String abaInicial;
  final VoidCallback aoVoltar;
  const FichaDevedor(
      {super.key,
      required this.api,
      required this.id,
      this.abaInicial = 'acionamento',
      required this.aoVoltar});

  @override
  State<FichaDevedor> createState() => _FichaDevedorState();
}

class _FichaDevedorState extends State<FichaDevedor> {
  late String _aba = widget.abaInicial;
  String _classe = '';
  bool _meus = false;
  Map<String, dynamic>? _dados;
  String? _erro;
  bool _carregando = true;
  int _pedido = 0;
  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final meu = ++_pedido;
    setState(() => _carregando = true);
    try {
      final d =
          await widget.api.ficha(widget.id, _aba, classe: _classe, meus: _meus);
      // Resposta velha (trocou de aba no meio): descartada.
      if (!mounted || meu != _pedido) return;
      setState(() {
        _dados = d;
        _erro = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || meu != _pedido) return;
      setState(() {
        _erro = erroDe(e);
        _carregando = false;
      });
    }
  }

  void _irPara(String aba) {
    if (aba == _aba && _dados != null) return;
    setState(() {
      _aba = aba;
      if (aba != 'acionamento') {
        _classe = '';
        _meus = false;
      }
    });
    _carregar();
  }

  Future<bool> _executar(String caminho, Map<String, String> campos,
      {File? arquivo, String query = ''}) async {
    try {
      final r = await widget.api
          .acao(caminho, campos, arquivo: arquivo, query: query);
      if (!mounted) return r.ok;
      if (r.mensagem != null && r.mensagem!.isNotEmpty) {
        avisar(context, r.mensagem!, erro: !r.ok);
      }
      // A aba de volta é a que o SERVIDOR decidiu para esta ação.
      if (r.aba.isNotEmpty && r.aba != _aba) {
        setState(() => _aba = r.aba);
      }
      await _carregar();
      return r.ok;
    } catch (e) {
      if (mounted) avisar(context, erroDe(e), erro: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = _dados;
    if (d == null) {
      return Center(
        child: _carregando
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_erro ?? 'Não foi possível abrir a ficha.',
                    style: TextStyle(color: p.danger)),
                const SizedBox(height: 12),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  OutlinedButton(
                      onPressed: widget.aoVoltar,
                      child: const Text('Voltar à busca')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: _carregar,
                      child: const Text('Tentar de novo')),
                ]),
              ]),
      );
    }
    final cab = ((d['cabecalho'] as Map?) ?? const {}).cast<String, dynamic>();
    final ctx = FichaCtx(
      id: widget.id,
      dados: d,
      api: widget.api,
      executar: _executar,
      irPara: _irPara,
      filtrar: (classe, meus) {
        setState(() {
          _classe = classe;
          _meus = meus;
        });
        _carregar();
      },
    );
    final abas = ((d['abas'] as List?) ?? const []).cast<Map>();

    return Scrollbar(
      controller: _rolagem,
      child: SingleChildScrollView(
        controller: _rolagem,
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Cabeçalho: voltar, nome, credor · documento e o valor da dívida.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: widget.aoVoltar,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.arrow_back_rounded,
                            size: 15, color: p.muted),
                        const SizedBox(width: 4),
                        Text('Buscar outro devedor',
                            style: TextStyle(color: p.muted, fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    SelectableText((cab['nome'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    SelectableText(
                        '${cab['credor'] ?? ''} · ${cab['doc'] ?? ''}',
                        style: TextStyle(color: p.muted, fontSize: 14)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Valor da dívida',
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
              Text((cab['total'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
              if (cab['atraso'] != null)
                Text(cab['atraso'].toString(),
                    style: TextStyle(
                        color: tinta(context, 'perigo'),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final corpo = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BarraAbas(abas: abas, ativa: _aba, aoTocar: _irPara),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                          topRight: Radius.circular(14)),
                      side: BorderSide(color: p.cardBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _carregando ? .55 : 1,
                        child: AbsorbPointer(
                            absorbing: _carregando,
                            child: corpoDaAba(_aba, ctx)),
                      ),
                    ),
                  ),
                ]);
            final painel = PainelDevedor(ctx);
            // Abaixo de 1100 px o painel desce para baixo das abas (como no portal).
            if (c.maxWidth < 1100) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [corpo, const SizedBox(height: 16), painel]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: corpo),
              const SizedBox(width: 18),
              SizedBox(width: 380, child: painel),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _BarraAbas extends StatelessWidget {
  final List<Map> abas;
  final String ativa;
  final void Function(String) aoTocar;
  const _BarraAbas(
      {required this.abas, required this.ativa, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final a in abas)
          InkWell(
            onTap: () => aoTocar(a['chave'].toString()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: a['chave'] == ativa
                            ? p.primary
                            : Colors.transparent,
                        width: 2.5)),
              ),
              child: Text(a['rotulo'].toString(),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: a['chave'] == ativa ? p.primary : p.muted)),
            ),
          ),
      ]),
    );
  }
}

/// O painel lateral da dívida (`.cb-painel`).
class PainelDevedor extends StatelessWidget {
  final FichaCtx ctx;
  const PainelDevedor(this.ctx, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = ctx.painel;
    final fones = ((v['fones'] as List?) ?? const []).cast<Map>();
    final doArquivo = ((v['arquivo_fones'] as List?) ?? const []).cast<Map>();
    final emails =
        ((v['emails'] as List?) ?? const []).map((e) => e.toString()).toList();
    final proximo = v['proximo'] as Map?;
    final ultimo = v['ultimo'] as Map?;

    Widget campo(String rotulo, Widget valor, {Widget? acao}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.cardBorder))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rotulo,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: p.muted,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    valor,
                  ]),
            ),
            if (acao != null) acao,
          ]),
        );
    Widget txt(String s, {bool grande = false, Color? cor}) => SelectableText(s,
        style: TextStyle(
            fontSize: grande ? 17 : 14,
            fontWeight: FontWeight.w700,
            color: cor,
            fontFeatures: const [FontFeature.tabularFigures()]));
    Widget duas(Widget a, Widget b) =>
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b)
        ]);
    Widget so(String rotulo, Widget valor) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo,
              style: TextStyle(
                  fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          valor,
        ]);
    Widget linha(Widget filho) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.cardBorder))),
          child: filho,
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          campo('Nome', txt((v['nome'] ?? '').toString(), grande: true),
              acao: BotaoCopiar((v['nome'] ?? '').toString())),
          campo('CPF / CNPJ', txt((v['doc'] ?? '').toString(), grande: true),
              acao: BotaoCopiar((v['doc'] ?? '').toString())),
          linha(duas(so('Credor', txt((v['credor'] ?? '').toString())),
              so('Títulos', txt((v['titulos'] ?? '').toString())))),
          linha(duas(
            so('Valor da dívida', txt((v['total'] ?? '').toString())),
            so(
                'Vencido',
                txt((v['vencido'] ?? '').toString(),
                    cor: v['vencido_alerta'] == true
                        ? tinta(context, 'perigo')
                        : null)),
          )),
          linha(duas(
              so('Atraso original', txt((v['atraso'] ?? '').toString())),
              so('Vencimento mais antigo',
                  txt((v['venc_mais_antigo'] ?? '—').toString())))),
          if (v['contratos'] != null)
            campo((v['contratos_rot'] ?? 'Contrato').toString(),
                txt(v['contratos'].toString())),
          if (v['situacoes'] != null)
            campo('Situação do contrato', txt(v['situacoes'].toString())),
          linha(duas(
              so('Data de entrada', txt((v['entrada'] ?? '—').toString())),
              so('UF / Cidade', txt((v['uf_cidade'] ?? '—').toString())))),
          campo(
            'Telefones para ligar',
            fones.isEmpty
                ? Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                        Text('Nenhum válido. ',
                            style: TextStyle(
                                color: p.muted, fontWeight: FontWeight.w600)),
                        LinkTexto(
                            'Ver localização', () => ctx.irPara('localizacao')),
                      ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        for (final t in fones)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(children: [
                              SelectableText(t['fone'].toString(),
                                  style: TextStyle(
                                      color: p.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Pilula(t['rotulo'].toString(),
                                  tom: t['status'] == 'valido'
                                      ? 'ok'
                                      : 'neutro'),
                            ]),
                          ),
                      ]),
          ),
          if (doArquivo.isNotEmpty)
            campo(
              'Outros telefones do arquivo',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in doArquivo)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      SelectableText(t['fone'].toString(),
                          style: TextStyle(
                              color: p.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t['rotulo'].toString(),
                              style: TextStyle(color: p.muted, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis)),
                      BotaoUsar(
                          ctx, t['numero'].toString(), t['rotulo'].toString()),
                    ]),
                  ),
              ]),
            ),
          if (emails.isNotEmpty)
            campo(
                emails.length > 1 ? 'E-mails' : 'E-mail',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  txt(emails.join(', ')),
                  const SizedBox(height: 4),
                  BotaoCopiar(emails.join(', ')),
                ])),
          campo(
            'Próximo retorno',
            proximo != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(proximo['quando'].toString(),
                            style: TextStyle(
                                color: p.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        if ((proximo['motivo'] ?? '').toString().isNotEmpty)
                          Text(proximo['motivo'].toString(),
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ])
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                        Text('Nenhum agendado. ',
                            style: TextStyle(
                                color: p.primary, fontWeight: FontWeight.w600)),
                        LinkTexto('Agendar', () => ctx.irPara('agenda')),
                      ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: so(
              'Último acionamento',
              ultimo != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(children: [
                            PontoClasse(ultimo['classe'].toString()),
                            Flexible(
                                child: Text(ultimo['tipo'].toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                          ]),
                          Text(
                              '${ultimo['quando']}${(ultimo['autor'] ?? '').toString().isNotEmpty ? ' · ${ultimo['autor']}' : ''}',
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ])
                  : Text('Dívida sem acionamento',
                      style: TextStyle(
                          color: p.muted, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A bolinha colorida da classe do acionamento (`.cb-ponto-*`).
class PontoClasse extends StatelessWidget {
  final String classe;
  const PontoClasse(this.classe, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cor = switch (classe) {
      'positivo' => p.success,
      'negativo' => p.danger,
      'neutro' => tinta(context, 'info'),
      _ => p.muted,
    };
    return Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(right: 7),
        decoration: BoxDecoration(color: cor, shape: BoxShape.circle));
  }
}

/// "Usar" um telefone que veio no arquivo: põe na lista de discagem (origem informado).
class BotaoUsar extends StatelessWidget {
  final FichaCtx ctx;
  final String numero;
  final String rotulo;
  const BotaoUsar(this.ctx, this.numero, this.rotulo, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 26,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              // Do tema (senão o texto perde a família da fonte do app).
              textStyle: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700)),
          onPressed: () => ctx.executar(
              '/telefone',
              ctx.campos(
                  {'numero': numero, 'observacao': 'Do arquivo: $rotulo'})),
          child: const Text('Usar'),
        ),
      );
}

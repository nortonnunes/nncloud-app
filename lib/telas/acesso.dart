// As telas antes da sessão: carregando, o LOGIN (igual ao do site, em etapas) e o
// bloqueio (app desligado no NN Conecta, sem conexão).
//
//   senha → [Política de uso] → verificação em duas etapas | configurar o app
//   autenticador → Conversas
//   QR code (lido com o app NN Conecta do celular) → [Política] → Conversas
//
// Quem decide a etapa é o SERVIDOR (`Controle.etapa`); estas telas só desenham.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/comum.dart';
import '../widgets/rodape.dart';

/// A logo do NN Conecta (a do tema sazonal, se houver), ou o ícone do app.
class LogoConecta extends StatelessWidget {
  final Controle c;
  final double altura;
  const LogoConecta(this.c, {super.key, this.altura = 44});
  @override
  Widget build(BuildContext context) {
    final url = c.aparencia?['logo']?.toString();
    final reserva = Image.asset('assets/icone.png', height: altura);
    if (url == null || url.isEmpty) return reserva;
    return Image.network(url, height: altura, fit: BoxFit.contain, errorBuilder: (_, __, ___) => reserva);
  }
}

class _Moldura extends StatelessWidget {
  final Controle c;
  final List<Widget> filhos;
  final double largura;
  const _Moldura(this.c, this.filhos, {this.largura = 460});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [p.topoIni, p.topoFim], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: largura),
            child: Card(
              elevation: 8,
              shadowColor: Colors.black38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 32, 36, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: LogoConecta(c, altura: 52)),
                    const SizedBox(height: 22),
                    ...filhos,
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

TextStyle? _titulo(BuildContext context) => Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);

Widget _texto(BuildContext context, String t) =>
    Text(t, textAlign: TextAlign.center, style: TextStyle(color: context.pal.muted, height: 1.45));

Widget _linhaErro(BuildContext context, String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(e, textAlign: TextAlign.center, style: TextStyle(color: context.pal.danger, height: 1.4)),
      );

/// O aviso no topo do login ("Sua sessão expirou…").
Widget _aviso(BuildContext context, String? a) => a == null || a.isEmpty
    ? const SizedBox.shrink()
    : Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.pal.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.pal.cardBorder),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: context.pal.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(a, style: TextStyle(color: context.pal.text, height: 1.35))),
        ]),
      );

/// O campo dos 6 dígitos (app autenticador ou e-mail).
class _CampoCodigo extends StatelessWidget {
  final TextEditingController controle;
  final VoidCallback aoEnviar;
  final String rotulo;
  const _CampoCodigo(this.controle, this.aoEnviar, {this.rotulo = 'Código de 6 dígitos'});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controle,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()], color: context.pal.text),
        decoration: InputDecoration(labelText: rotulo, counterText: ''),
        onChanged: (v) {
          if (v.length == 6) aoEnviar();
        },
        onSubmitted: (_) => aoEnviar(),
      );
}

class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icone.png', height: 72),
            const SizedBox(height: 22),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ]),
        ),
      );
}

/// O login: escolhe a tela pela etapa que o servidor deu.
class TelaLogin extends StatelessWidget {
  final Controle c;
  const TelaLogin(this.c, {super.key});
  @override
  Widget build(BuildContext context) => switch (c.etapa) {
        EtapaLogin.senha => _TelaSenha(c, key: const ValueKey('senha')),
        EtapaLogin.politica => _TelaPolitica(c, key: ValueKey('politica-${c.ticket}')),
        EtapaLogin.doisFatores => _TelaDoisFatores(c, key: ValueKey('2fa-${c.ticket}')),
        EtapaLogin.setup => _TelaSetup(c, key: ValueKey('setup-${c.ticket}')),
        EtapaLogin.qr => _TelaQr(c, key: const ValueKey('qr')),
      };
}

/* ======================= e-mail e senha ======================= */

class _TelaSenha extends StatefulWidget {
  final Controle c;
  const _TelaSenha(this.c, {super.key});
  @override
  State<_TelaSenha> createState() => _TelaSenhaState();
}

class _TelaSenhaState extends State<_TelaSenha> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _ver = false;
  bool _entrando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _email.text = widget.c.emailDigitado;
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_entrando) return;
    if (_email.text.trim().isEmpty || _senha.text.isEmpty) {
      setState(() => _erro = 'Informe o e-mail e a senha.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    final e = await widget.c.entrar(_email.text, _senha.text);
    if (!mounted) return;
    setState(() {
      _entrando = false;
      _erro = e;
      if (e != null) _senha.clear();
    });
  }

  Future<void> _qr() async {
    setState(() => _erro = null);
    final e = await widget.c.iniciarQr();
    if (e != null && mounted) setState(() => _erro = e);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final site = (widget.c.aparencia?['site_url'] ?? '').toString();
    return _Moldura(widget.c, [
      _aviso(context, widget.c.avisoLogin),
      Text('Entrar', style: _titulo(context), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      _texto(context, 'Use o e-mail e a senha do NN Conecta.'),
      const SizedBox(height: 22),
      AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _email,
            autofocus: _email.text.isEmpty,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-mail'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _senha,
            autofocus: _email.text.isNotEmpty,
            obscureText: !_ver,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                tooltip: _ver ? 'Esconder a senha' : 'Mostrar a senha',
                icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _ver = !_ver),
              ),
            ),
            onSubmitted: (_) => _entrar(),
          ),
        ]),
      ),
      _linhaErro(context, _erro),
      const SizedBox(height: 20),
      FilledButton(onPressed: _entrando ? null : _entrar, child: Text(_entrando ? 'Entrando…' : 'Entrar')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _entrando ? null : _qr,
        icon: const Icon(Icons.qr_code_2_rounded, size: 20),
        label: const Text('Entrar com QR code'),
      ),
      const SizedBox(height: 12),
      if (site.isNotEmpty)
        Center(
          child: TextButton(
            onPressed: () => abrirLink(context, '$site/esqueci-senha'),
            child: const Text('Esqueci minha senha'),
          ),
        ),
      const SizedBox(height: 4),
      LinhaDenuncia(widget.c.aparencia),
      const SizedBox(height: 4),
      Text('${AppConfig.nome} ${AppConfig.versao}', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 11.5)),
    ]);
  }
}

/* ======================= política de uso ======================= */

class _TelaPolitica extends StatefulWidget {
  final Controle c;
  const _TelaPolitica(this.c, {super.key});
  @override
  State<_TelaPolitica> createState() => _TelaPoliticaState();
}

class _TelaPoliticaState extends State<_TelaPolitica> {
  final _cpf = TextEditingController();
  // ⚠️ A barra de rolagem sempre visível EXIGE um controlador próprio (sem ele, erro).
  final _rolagem = ScrollController();
  bool _aceite = false;
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _cpf.text = _mascaraCpf((widget.c.passo['cpf'] ?? '').toString());
  }

  @override
  void dispose() {
    _cpf.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    if (!_aceite) {
      setState(() => _erro = 'Marque "Li e aceito" para continuar.');
      return;
    }
    if (_cpf.text.replaceAll(RegExp(r'\D'), '').length != 11) {
      setState(() => _erro = 'Informe o seu CPF, com os 11 dígitos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final e = await widget.c.aceitarPolitica(_cpf.text);
    if (mounted) {
      setState(() {
        _enviando = false;
        _erro = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ps = widget.c.passo;
    return _Moldura(widget.c, largura: 720, [
      Text((ps['titulo'] ?? 'Política de uso').toString(), style: _titulo(context), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      _texto(context, 'Versão ${ps['versao'] ?? ''} — para continuar, leia e aceite a política de uso dos sistemas.'),
      const SizedBox(height: 16),
      Container(
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.cardBorder)),
        child: Scrollbar(
          controller: _rolagem,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _rolagem,
            padding: const EdgeInsets.all(18),
            child: SelectableText((ps['conteudo'] ?? '').toString(), style: TextStyle(color: p.text, height: 1.55, fontSize: 14)),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Nome: ${ps['nome'] ?? ''}   ·   E-mail: ${ps['email'] ?? ''}', style: TextStyle(color: p.muted, fontSize: 13)),
      const SizedBox(height: 12),
      TextField(
        controller: _cpf,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11), _FormatoCpf()],
        decoration: const InputDecoration(labelText: 'CPF (assinatura)'),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        value: _aceite,
        onChanged: (v) => setState(() => _aceite = v ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Li e aceito a política de uso.'),
      ),
      Text((ps['aviso'] ?? '').toString(), style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
      _linhaErro(context, _erro),
      const SizedBox(height: 18),
      FilledButton(onPressed: _enviando ? null : _continuar, child: Text(_enviando ? 'Registrando…' : 'Aceitar e continuar')),
      const SizedBox(height: 6),
      TextButton(onPressed: _enviando ? null : () => widget.c.voltarParaSenha(), child: const Text('Voltar')),
    ]);
  }
}

String _mascaraCpf(String v) {
  final d = v.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return d;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

class _FormatoCpf extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue antes, TextEditingValue depois) {
    final d = depois.text.replaceAll(RegExp(r'\D'), '');
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/* ======================= verificação em duas etapas ======================= */

/// O botão "Enviar código por e-mail", com o "reenviar em N s".
class _BotaoEmail extends StatefulWidget {
  final Controle c;
  final void Function(String msg, bool ok) aoResponder;
  /// O texto antes do primeiro envio (padrão: "Enviar código por e-mail para …").
  final String? rotulo;
  const _BotaoEmail(this.c, this.aoResponder, {this.rotulo});
  @override
  State<_BotaoEmail> createState() => _BotaoEmailState();
}

class _BotaoEmailState extends State<_BotaoEmail> {
  Timer? _t;
  int _espera = 0;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final pend = ((widget.c.passo['email'] as Map?)?['pendente'] as Map?);
    _contar((pend?['reenviar_em'] as num?)?.toInt() ?? 0);
  }

  void _contar(int s) {
    _t?.cancel();
    _espera = s;
    if (s <= 0) return;
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _espera--);
      if (_espera <= 0) _t?.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final r = await widget.c.pedirCodigoEmail();
    if (!mounted) return;
    setState(() => _enviando = false);
    final pend = ((widget.c.passo['email'] as Map?)?['pendente'] as Map?);
    if (r.ok) _contar((pend?['reenviar_em'] as num?)?.toInt() ?? 60);
    widget.aoResponder(r.msg, r.ok);
  }

  @override
  Widget build(BuildContext context) {
    final destino = ((widget.c.passo['email'] as Map?)?['destino'] ?? '').toString();
    final jaMandou = ((widget.c.passo['email'] as Map?)?['pendente']) != null;
    final rotulo = _enviando
        ? 'Enviando…'
        : _espera > 0
            ? 'Reenviar o código em $_espera s'
            : (jaMandou ? 'Reenviar o código para $destino' : (widget.rotulo ?? 'Enviar código por e-mail para $destino'));
    return OutlinedButton.icon(
      onPressed: _enviando || _espera > 0 ? null : _enviar,
      icon: const Icon(Icons.mail_outline_rounded, size: 19),
      label: Text(rotulo, textAlign: TextAlign.center),
    );
  }
}

class _TelaDoisFatores extends StatefulWidget {
  final Controle c;
  const _TelaDoisFatores(this.c, {super.key});
  @override
  State<_TelaDoisFatores> createState() => _TelaDoisFatoresState();
}

class _TelaDoisFatoresState extends State<_TelaDoisFatores> {
  final _codigo = TextEditingController();
  bool _enviando = false;
  String? _erro;
  String? _info;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    if (_codigo.text.length != 6) {
      setState(() => _erro = 'Digite os 6 dígitos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final e = await widget.c.enviarCodigo(_codigo.text);
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _erro = e;
      if (e != null) _codigo.clear();
    });
  }

  Future<void> _celular({bool reenviar = false}) async {
    setState(() {
      _erro = null;
      _info = null;
    });
    final e = await widget.c.pedirCelular(reenviar: reenviar);
    if (e != null && mounted) setState(() => _erro = e);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = context.pal;
    final email = c.passo['email'] as Map?;
    final cel = c.passo['celular'] as Map?;
    final suspenso = (cel?['suspenso'] as num?)?.toInt() ?? 0;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _Moldura(c, [
        Text('Verificação em duas etapas', style: _titulo(context), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        _texto(context, email != null
            ? 'Digite o código do app autenticador (Google Authenticator) ou o código que enviamos por e-mail.'
            : 'Digite o código do app autenticador (Google Authenticator).'),
        const SizedBox(height: 20),
        if (c.celularStatus == 'pendente' || c.celularStatus == 'aprovado')
          _EsperaCelular(c, aoCancelar: c.pararCelular, aoReenviar: () => _celular(reenviar: true))
        else ...[
          _CampoCodigo(_codigo, _confirmar),
          if (c.restamTentativas < 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                c.restamTentativas == 1 ? 'Resta 1 tentativa.' : 'Restam ${c.restamTentativas} tentativas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5),
              ),
            ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_info!, textAlign: TextAlign.center, style: TextStyle(color: p.success, height: 1.4)),
            ),
          _linhaErro(context, _erro),
          if (c.celularStatus == 'recusado')
            _linhaErro(context, 'O acesso foi recusado no celular. Se não foi você, troque a sua senha.'),
          if (c.celularStatus == 'expirado') _linhaErro(context, 'O pedido no celular expirou. Peça de novo ou use o código.'),
          const SizedBox(height: 18),
          FilledButton(onPressed: _enviando ? null : _confirmar, child: Text(_enviando ? 'Conferindo…' : 'Confirmar')),
          if (email != null) ...[
            const SizedBox(height: 10),
            _BotaoEmail(c, (msg, ok) => setState(() {
                  if (ok) {
                    _info = msg;
                    _erro = null;
                  } else {
                    _erro = msg;
                  }
                })),
          ],
          if (cel != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: suspenso > 0 ? null : () => _celular(),
              icon: const Icon(Icons.phone_iphone_rounded, size: 19),
              label: Text(suspenso > 0 ? 'Aprovação no celular suspensa por ${(suspenso / 60).ceil()} min' : 'Aprovar no celular (app NN Conecta)'),
            ),
          ],
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: () => c.voltarParaSenha(), child: const Text('Não sou eu / voltar')),
      ]),
    );
  }
}

class _EsperaCelular extends StatelessWidget {
  final Controle c;
  final VoidCallback aoCancelar;
  final VoidCallback aoReenviar;
  const _EsperaCelular(this.c, {required this.aoCancelar, required this.aoReenviar});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.cardBorder)),
      child: Column(children: [
        Icon(Icons.phone_iphone_rounded, size: 38, color: p.primary),
        const SizedBox(height: 10),
        Text(c.celularStatus == 'aprovado' ? 'Aprovado. Entrando…' : 'Toque em "Aprovar" no app NN Conecta do seu celular.',
            textAlign: TextAlign.center, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 8),
        if (c.celularStatus == 'pendente')
          Text('O pedido vale por mais ${c.celularRestam} s.', style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          TextButton(onPressed: aoReenviar, child: const Text('Reenviar notificação')),
          TextButton(onPressed: aoCancelar, child: const Text('Usar o código')),
        ]),
      ]),
    );
  }
}

/* ======================= configurar o app autenticador ======================= */

class _TelaSetup extends StatefulWidget {
  final Controle c;
  const _TelaSetup(this.c, {super.key});
  @override
  State<_TelaSetup> createState() => _TelaSetupState();
}

class _TelaSetupState extends State<_TelaSetup> {
  final _codigo = TextEditingController();
  final _codigoEmail = TextEditingController();
  bool _enviando = false;
  bool _peloEmail = false;
  String? _erro;
  String? _info;

  @override
  void dispose() {
    _codigo.dispose();
    _codigoEmail.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    final emailVez = _peloEmail;
    final cod = emailVez ? _codigoEmail.text : _codigo.text;
    if (cod.length != 6) {
      setState(() => _erro = 'Digite os 6 dígitos.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final e = emailVez ? await widget.c.entrarComCodigoDoEmail(cod) : await widget.c.confirmarSetup(cod);
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _erro = e;
      if (e != null) (emailVez ? _codigoEmail : _codigo).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = context.pal;
    final ps = c.passo;
    final segredo = (ps['segredo'] ?? '').toString();
    final uri = (ps['uri'] ?? '').toString();
    final email = ps['email'] as Map?;
    final agrupado = segredo.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim();
    return _Moldura(c, largura: 520, [
      Text('Configure o app autenticador', style: _titulo(context), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      _texto(context, 'A verificação em duas etapas é obrigatória. Abra o Google Authenticator (ou outro app autenticador) no celular e leia o QR code.'),
      const SizedBox(height: 18),
      if (!_peloEmail) ...[
        if (uri.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.cardBorder)),
              child: QrImageView(data: uri, size: 190, backgroundColor: Colors.white),
            ),
          ),
        const SizedBox(height: 12),
        Text('Não consegue ler? Digite esta chave no app:', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: SelectableText(agrupado,
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          IconButton(
            tooltip: 'Copiar a chave',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: segredo)),
          ),
        ]),
        const SizedBox(height: 14),
        _CampoCodigo(_codigo, _confirmar, rotulo: 'Código que o app mostra'),
      ] else ...[
        _texto(context, 'Desta vez você entra com o código do e-mail. No próximo login, o app autenticador será pedido de novo.'),
        const SizedBox(height: 14),
        _CampoCodigo(_codigoEmail, _confirmar, rotulo: 'Código do e-mail'),
      ],
      if (_info != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_info!, textAlign: TextAlign.center, style: TextStyle(color: p.success, height: 1.4)),
        ),
      _linhaErro(context, _erro),
      const SizedBox(height: 18),
      FilledButton(onPressed: _enviando ? null : _confirmar, child: Text(_enviando ? 'Conferindo…' : (_peloEmail ? 'Entrar' : 'Ativar e entrar'))),
      if (email != null) ...[
        const SizedBox(height: 10),
        if (!_peloEmail)
          _BotaoEmail(c, rotulo: 'Entrar desta vez com código por e-mail', (msg, ok) => setState(() {
                if (ok) {
                  _peloEmail = true;
                  _info = msg;
                  _erro = null;
                } else {
                  _erro = msg;
                }
              }))
        else
          TextButton(onPressed: () => setState(() => _peloEmail = false), child: const Text('Configurar o app autenticador agora')),
      ],
      const SizedBox(height: 6),
      TextButton(onPressed: () => c.voltarParaSenha(), child: const Text('Voltar')),
    ]);
  }
}

/* ======================= QR code ======================= */

class _TelaQr extends StatefulWidget {
  final Controle c;
  const _TelaQr(this.c, {super.key});
  @override
  State<_TelaQr> createState() => _TelaQrState();
}

class _TelaQrState extends State<_TelaQr> {
  Timer? _relogio;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _outro() async {
    setState(() => _erro = null);
    final e = await widget.c.iniciarQr();
    if (e != null && mounted) setState(() => _erro = e);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = context.pal;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final payload = (c.qr?['payload'] ?? '').toString();
        final restam = c.qrRestam;
        final expirou = c.qr == null || c.qrStatus == 'expired' || restam <= 0;
        final aprovado = c.qrStatus == 'approved';
        return _Moldura(c, [
          Text('Entrar com QR code', style: _titulo(context), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          _texto(context, 'No celular, abra o app NN Conecta, toque no ícone de QR code e aponte a câmera para o código abaixo.'),
          const SizedBox(height: 18),
          Center(
            child: Stack(alignment: Alignment.center, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.cardBorder)),
                child: payload.isEmpty
                    ? const SizedBox(width: 210, height: 210)
                    : Opacity(opacity: expirou ? 0.12 : 1, child: QrImageView(data: payload, size: 210, backgroundColor: Colors.white)),
              ),
              if (expirou && !aprovado) FilledButton.tonal(onPressed: _outro, child: const Text('Gerar outro QR code')),
              if (aprovado) const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            aprovado
                ? 'Aprovado no celular. Entrando…'
                : expirou
                    ? 'O QR code expirou.'
                    : 'Válido por mais $restam s.',
            textAlign: TextAlign.center,
            style: TextStyle(color: aprovado ? p.success : p.muted, fontWeight: aprovado ? FontWeight.w600 : FontWeight.normal),
          ),
          _linhaErro(context, _erro ?? c.avisoLogin),
          const SizedBox(height: 18),
          OutlinedButton(onPressed: () => c.voltarParaSenha(), child: const Text('Entrar com e-mail e senha')),
        ]);
      },
    );
  }
}

/* ======================= bloqueio ======================= */

class TelaBloqueio extends StatelessWidget {
  final Controle c;
  const TelaBloqueio(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cod = c.codigoBloqueio ?? '';
    final titulo = switch (cod) {
      'app_desligado' => 'App desligado',
      'app_indisponivel' => 'App ainda não instalado no servidor',
      'sem_rede' => 'Sem conexão',
      _ => 'Não foi possível conectar',
    };
    return _Moldura(c, [
      Icon(cod == 'sem_rede' ? Icons.wifi_off_rounded : Icons.lock_outline_rounded, size: 44, color: p.primary),
      const SizedBox(height: 12),
      Text(titulo, style: _titulo(context), textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(c.motivo ?? '', textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.45)),
      const SizedBox(height: 22),
      FilledButton(onPressed: c.tentarDeNovo, child: const Text('Tentar de novo')),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: '${AppConfig.nome} ${AppConfig.versao} · $titulo · ${c.motivo ?? ''}')),
        child: const Text('Copiar a mensagem para o suporte'),
      ),
    ]);
  }
}

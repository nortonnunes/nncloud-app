// As telas antes da sessão: carregando, o código do computador, o login e o
// bloqueio (fora da rede liberada, app desligado, sem conexão).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../servicos/controle.dart';
import '../tema.dart';
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
  const _Moldura(this.c, this.filhos);
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
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              elevation: 8,
              shadowColor: Colors.black38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
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

class TelaComputador extends StatefulWidget {
  final Controle c;
  const TelaComputador(this.c, {super.key});
  @override
  State<TelaComputador> createState() => _TelaComputadorState();
}

class _TelaComputadorState extends State<TelaComputador> {
  bool _enviando = false;
  String? _erro;

  Future<void> _pedir() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final e = await widget.c.pedirAutorizacao();
    if (mounted) {
      setState(() {
        _enviando = false;
        _erro = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = context.pal;
    final st = c.statusComputador;
    final titulo = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final List<Widget> corpo;
    if (st == 'pendente' && (c.codigo ?? '').isNotEmpty) {
      corpo = [
        Text('Aguardando a autorização', style: titulo, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Peça ao administrador para autorizar este computador em Sistema → NN Unifi, conferindo o código abaixo.',
            textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.45)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.cardBorder)),
          child: SelectableText(
            c.codigo!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 6, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(height: 12),
        Text('Computador: ${c.nomeComputador}', textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Esta tela muda sozinha quando for autorizado.', style: TextStyle(color: p.muted)),
        ]),
      ];
    } else if (st == 'recusado' || st == 'revogado') {
      corpo = [
        Text(st == 'recusado' ? 'Autorização recusada' : 'Autorização revogada', style: titulo, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          st == 'recusado'
              ? 'O administrador recusou o pedido deste computador.'
              : 'Este computador não pode mais usar o app.${(c.motivo ?? '').isNotEmpty ? '\nMotivo: ${c.motivo}' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, height: 1.45),
        ),
        const SizedBox(height: 22),
        FilledButton(onPressed: _enviando ? null : _pedir, child: const Text('Pedir autorização de novo')),
      ];
    } else {
      corpo = [
        Text('Autorizar este computador', style: titulo, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Antes do primeiro login, o administrador precisa autorizar este computador. Ao pedir, aparece um código para ele conferir.',
            textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.45)),
        const SizedBox(height: 22),
        FilledButton(onPressed: _enviando ? null : _pedir, child: Text(_enviando ? 'Pedindo…' : 'Pedir autorização')),
      ];
    }
    return _Moldura(c, [
      ...corpo,
      if (_erro != null) ...[
        const SizedBox(height: 14),
        Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: p.danger)),
      ],
    ]);
  }
}

class TelaLogin extends StatefulWidget {
  final Controle c;
  const TelaLogin(this.c, {super.key});
  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _ver = false;
  bool _entrando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _email.text = widget.c.arm.pref<String>('ultimo_email', '');
    _erro = widget.c.motivo;
    widget.c.motivo = null;
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
    widget.c.arm.definir('ultimo_email', _email.text.trim());
    final e = await widget.c.entrar(_email.text, _senha.text);
    if (!mounted) return;
    setState(() {
      _entrando = false;
      _erro = e;
      if (e != null) _senha.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return _Moldura(widget.c, [
      Text('Entrar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('Use o e-mail e a senha do Tele Atendimento.', textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
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
      if (_erro != null) ...[
        const SizedBox(height: 14),
        Text(_erro!, style: TextStyle(color: p.danger), textAlign: TextAlign.center),
      ],
      const SizedBox(height: 20),
      FilledButton(onPressed: _entrando ? null : _entrar, child: Text(_entrando ? 'Entrando…' : 'Entrar')),
      const SizedBox(height: 14),
      Text('Esqueceu a senha? Fale com o administrador.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
      const SizedBox(height: 10),
      LinhaDenuncia(widget.c.aparencia),
    ]);
  }
}

class TelaBloqueio extends StatelessWidget {
  final Controle c;
  const TelaBloqueio(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cod = c.codigoBloqueio ?? '';
    final titulo = switch (cod) {
      'ip_bloqueado' => 'Rede não liberada',
      'app_desligado' => 'App desligado',
      'app_indisponivel' => 'App ainda não instalado no servidor',
      'sem_rede' => 'Sem conexão',
      _ => 'Não foi possível conectar',
    };
    return _Moldura(c, [
      Icon(cod == 'sem_rede' ? Icons.wifi_off_rounded : Icons.lock_outline_rounded, size: 44, color: p.primary),
      const SizedBox(height: 12),
      Text(titulo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
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

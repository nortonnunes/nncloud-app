// "NN Cloud" no Explorador de Arquivos (Windows, Cloud Files API).
//
// A regra inteira mora no motor (`ProvedorSobDemanda`, testado sem Windows); aqui
// ficam a ponte com o C++ do runner (canal "nncloud/fp", windows/runner/nuvem_windows.cpp),
// o observador da pasta e o ciclo de vida (ligar, retomar ao abrir o app, desligar).
//
// ⚠️ Diferença para o Mac: no Windows quem entrega os arquivos é o APP — com o app
// fechado, o que não está no disco não abre (como no OneDrive). Por isso o app
// inicia com o Windows.
// ⚠️ Desligar NÃO apaga o que estava baixado: vira arquivo comum na mesma pasta. O
// que só estava na nuvem some do disco (continua na nuvem).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

const _canal = MethodChannel('nncloud/fp');

/// O NativoNuvem do Windows: cada operação é uma chamada ao C++ do runner.
class NativoWindows implements NativoNuvem {
  /// Onde vão as falhas do nativo (o registro `explorer.log`).
  void Function(String linha)? log;

  @override
  Future<List<EntradaLocal>> varrer(String raiz) async {
    final r = await _canal.invokeListMethod<Object?>('varrer', {'raiz': raiz}) ?? const [];
    return [
      for (final x in r)
        if (x is Map)
          EntradaLocal('${x['caminho']}',
              pasta: x['pasta'] == true, placeholder: x['placeholder'] == true, emDia: x['emDia'] == true),
    ];
  }

  @override
  Future<bool> marcarEmDia(String caminho) => _ok('marcarEmDia', {'caminho': caminho});

  @override
  Future<void> criarPlaceholders(String pasta, List<NovoPlaceholder> itens) async {
    if (itens.isEmpty) return;
    await _canal.invokeMethod('criarPlaceholders', {
      'pasta': pasta,
      'itens': [
        for (final i in itens)
          {
            'nome': i.nome,
            'identidade': i.identidade,
            'pasta': i.pasta,
            'tamanho': i.tamanho,
            'criado': i.criadoMs,
            'modificado': i.modificadoMs,
          },
      ],
    });
  }

  @override
  Future<EstadoLocal?> estado(String caminho) async {
    final r = await _canal.invokeMapMethod<String, dynamic>('estado', {'caminho': caminho});
    if (r == null) return null;
    return EstadoLocal(
      placeholder: r['placeholder'] == true,
      emDia: r['emDia'] == true,
      pasta: r['pasta'] == true,
      hidratado: r['hidratado'] != false,
      identidade: r['identidade'] as String?,
    );
  }

  Future<bool> _ok(String metodo, Map<String, Object?> args) async {
    try {
      await _canal.invokeMethod(metodo, args);
      return true;
    } on PlatformException catch (e) {
      log?.call('nativo $metodo ${args['caminho']}: ${e.message}');
      return false;
    }
  }

  @override
  Future<bool> atualizar(String caminho, String identidade, {int? tamanho, int? criadoMs, int? modificadoMs, bool desidratar = false}) =>
      _ok('atualizar', {
        'caminho': caminho,
        'identidade': identidade,
        if (tamanho != null) 'tamanho': tamanho,
        if (criadoMs != null) 'criado': criadoMs,
        if (modificadoMs != null) 'modificado': modificadoMs,
        'desidratar': desidratar,
      });

  @override
  Future<bool> converter(String caminho, String identidade, {bool desidratar = false}) =>
      _ok('converter', {'caminho': caminho, 'identidade': identidade, 'desidratar': desidratar});

  @override
  Future<bool> desidratar(String caminho) => _ok('desidratar', {'caminho': caminho});

  Future<bool> reverter(String caminho) => _ok('reverter', {'caminho': caminho});

  // Renomear/apagar a pedido da nuvem: o próprio app mexe no disco, e o nativo
  // aprova na hora (não pergunta de volta ao Dart).
  @override
  Future<void> mover(String de, String para) async {
    if (FileSystemEntity.isDirectorySync(de)) {
      Directory(de).renameSync(para);
    } else {
      File(de).renameSync(para);
    }
  }

  @override
  Future<void> apagar(String caminho) async {
    if (FileSystemEntity.isDirectorySync(caminho)) {
      Directory(caminho).deleteSync();
    } else {
      File(caminho).deleteSync();
    }
  }
}

class SobDemandaWindows {
  final NativoWindows nativo = NativoWindows();
  ProvedorSobDemanda? provedor;
  StreamSubscription<WatchEvent>? _observador;
  final Directory dados;
  final void Function(EventoSobDemanda e) aoEvento;
  int _baixando = 0;
  final List<Future<void> Function()> _esperando = [];

  SobDemandaWindows(this.dados, this.aoEvento) {
    _canal.setMethodCallHandler(_doWindows);
    nativo.log = registrar;
  }

  /// O registro do Explorador (`explorer.log`, ao lado das preferências): o que subiu,
  /// o que deu problema e as falhas do Windows. É o que se pede quando "não sincroniza"
  /// — sem ele, a única pista seria o que a pessoa lembra de ter feito.
  File get arquivoRegistro => File(p.join(dados.path, 'explorer.log'));

  void registrar(String linha) {
    debugPrint('NN Cloud (Explorer): $linha');
    try {
      final f = arquivoRegistro;
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        f.renameSync('${f.path}.1');   // guarda o anterior; o novo começa vazio
      }
      final agora = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      f.writeAsStringSync('$agora  $linha\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void _evento(EventoSobDemanda e) {
    registrar('${e.tipo} ${e.caminho}${e.detalhe == null ? '' : ' — ${e.detalhe}'}');
    aoEvento(e);
  }

  static Future<bool> suportado() async {
    if (!Platform.isWindows) return false;
    try {
      return await _canal.invokeMethod<bool>('suportado') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// A pasta registrada (null = não está ligado).
  static Future<String?> registrado() async {
    try {
      return await _canal.invokeMethod<String>('registrado');
    } catch (_) {
      return null;
    }
  }

  static String raizPadrao() => p.join(Platform.environment['USERPROFILE'] ?? Directory.current.path, 'NN Cloud');

  File get _estado => File(p.join(dados.path, 'explorer.json'));

  /// Registra a pasta no Explorer e começa (a árvore inteira desce como placeholders).
  Future<String?> ligar({required Api api, required String conta, required String computador, required bool liberar}) async {
    final raiz = raizPadrao();
    try {
      await _canal.invokeMethod('registrar', {'raiz': raiz, 'conta': conta});
    } on PlatformException catch (e) {
      registrar('registrar $raiz: ${e.message}');
      return 'O Windows recusou criar o NN Cloud no Explorador de Arquivos: ${e.message}';
    }
    registrar('registrado em $raiz');
    return iniciar(raiz, api: api, computador: computador, liberar: liberar);
  }

  /// Conecta (o app abriu e o NN Cloud já estava registrado) e põe em dia.
  Future<String?> iniciar(String raiz, {required Api api, required String computador, required bool liberar}) async {
    try {
      await _canal.invokeMethod('conectar', {'raiz': raiz});
    } on PlatformException catch (e) {
      registrar('conectar $raiz: ${e.message}');
      return 'Não foi possível conectar o NN Cloud ao Explorador de Arquivos: ${e.message}';
    }
    final pr = ProvedorSobDemanda(
      api: api,
      nativo: nativo,
      raiz: raiz,
      arquivoEstado: _estado,
      computador: computador,
      liberarAposEnviar: liberar,
      aoEvento: _evento,
    )..carregar();
    provedor = pr;
    registrar('conectado em $raiz');
    _observar(raiz);
    unawaited(_seguro(() async {
      await pr.sincronizar(completo: true);
      await _conferir(pr);
    }));
    return null;
  }

  /// O observador de pasta: o que muda no disco sobe em ~2 s. Se ele cair (o erro
  /// era engolido), volta sozinho — e a conferência do disco a cada ciclo cobre o
  /// intervalo. ⚠️ Ele só avisa de ARQUIVO; pasta nova é a conferência que pega.
  void _observar(String raiz) {
    _observador?.cancel();
    _observador = DirectoryWatcher(raiz).events.listen(
      (ev) => provedor?.localMudou([ev.path]),
      onError: (Object e) {
        registrar('observador de pasta caiu: $e');
        _religar(raiz);
      },
      onDone: () => _religar(raiz),
      cancelOnError: true,
    );
  }

  void _religar(String raiz) {
    Timer(const Duration(seconds: 5), () {
      if (provedor?.raiz == raiz && Directory(raiz).existsSync()) _observar(raiz);
    });
  }

  /// A cada ciclo do app: mudanças da nuvem, depois a conferência do disco (o que
  /// foi criado/editado aqui e o observador não pegou) e o que ficou pendente.
  Future<void> ciclo() async {
    final pr = provedor;
    if (pr == null) return;
    await _seguro(() => pr.sincronizar());
    await _seguro(() => _conferir(pr));
    if (pr.temPendentes) await _seguro(pr.processarLocais);
  }

  Future<void> _conferir(ProvedorSobDemanda pr) async {
    final n = await pr.conferirDisco();
    if (n > 0) registrar('conferência do disco: $n item(ns) para enviar');
  }

  set liberar(bool v) => provedor?.liberarAposEnviar = v;

  Future<void> abrir() async {
    final raiz = provedor?.raiz ?? await registrado();
    if (raiz != null) await Process.run('explorer.exe', [raiz]);
  }

  /// Tira o NN Cloud do Explorer. O que estava baixado vira arquivo comum e fica.
  Future<String?> desligar() async {
    final raiz = provedor?.raiz ?? await registrado();
    await _observador?.cancel();
    _observador = null;
    provedor?.encerrar();
    if (raiz != null && Directory(raiz).existsSync()) await _limpar(Directory(raiz));
    try {
      await _canal.invokeMethod('desconectar');
      await _canal.invokeMethod('desregistrar');
    } on PlatformException catch (e) {
      return 'Não foi possível tirar o NN Cloud do Explorador de Arquivos: ${e.message}';
    }
    provedor?.esquecer();
    provedor = null;
    return null;
  }

  /// Fica o que está no disco (vira arquivo comum); some o que só estava na nuvem.
  Future<void> _limpar(Directory d) async {
    for (final e in d.listSync(followLinks: false)) {
      final est = await nativo.estado(e.path);
      if (est == null) continue;
      if (est.pasta) {
        await _limpar(Directory(e.path));
        if (est.placeholder) {
          if (Directory(e.path).listSync().isEmpty) {
            try {
              Directory(e.path).deleteSync();
            } catch (_) {}
          } else {
            await nativo.reverter(e.path);
          }
        }
      } else if (est.placeholder) {
        if (est.hidratado) {
          await nativo.reverter(e.path);
        } else {
          try {
            File(e.path).deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  // ---------------------------------------------------------------- o Windows pede

  Future<Object?> _doWindows(MethodCall c) async {
    final a = (c.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    final pr = provedor;
    switch (c.method) {
      case 'buscar':
        _fila(() => _buscar(a['req'] as int, '${a['identidade']}', (a['tamanho'] as num?)?.toInt() ?? 0));
      // ⚠️ O Windows fica esperando a resposta (o Explorer trava até 60 s): ela sai
      // SEMPRE, inclusive quando algo dá errado no meio.
      case 'apagar':
        var ok = false;
        try {
          ok = pr != null && await pr.aoApagar('${a['identidade']}', '${a['caminho']}');
        } catch (e) {
          registrar('apagar ${a['caminho']}: $e');
        }
        await _responder(a['req'] as int, ok);
      case 'renomear':
        final dentro = a['dentro'] == true;
        var ok = false;
        try {
          ok = pr != null &&
              (dentro
                  ? await pr.aoRenomear('${a['identidade']}', '${a['de']}', '${a['para']}')
                  : await pr.aoApagar('${a['identidade']}', '${a['de']}'));
        } catch (e) {
          registrar('renomear ${a['de']}: $e');
        }
        await _responder(a['req'] as int, ok);
    }
    return null;
  }

  Future<void> _responder(int req, bool ok) async {
    try {
      await _canal.invokeMethod('responder', {'req': req, 'ok': ok});
    } catch (_) {}
  }

  /// No máximo 3 downloads ao mesmo tempo (abrir uma pasta de fotos pede várias).
  void _fila(Future<void> Function() tarefa) {
    _esperando.add(tarefa);
    _proximo();
  }

  void _proximo() {
    while (_baixando < 3 && _esperando.isNotEmpty) {
      final t = _esperando.removeAt(0);
      _baixando++;
      unawaited(t().whenComplete(() {
        _baixando--;
        _proximo();
      }));
    }
  }

  Future<void> _buscar(int req, String identidade, int tamanho) async {
    final pr = provedor;
    if (pr == null) {
      await _falhar(req);
      return;
    }
    final pasta = Directory(p.join(Directory.systemTemp.path, 'nncloud-explorer'))..createSync(recursive: true);
    final tmp = File(p.join(pasta.path, 'req-$req-${DateTime.now().microsecondsSinceEpoch}'));
    var entregue = 0;
    var ultimo = DateTime.now();
    var fila = Future<void>.value();
    try {
      await pr.baixar(identidade, tmp, aoReceber: (gravados) {
        // Entrega em blocos enquanto baixa (o Windows desiste em 60 s sem notícia).
        final agora = DateTime.now();
        if (gravados - entregue < 1024 * 1024 && agora.difference(ultimo) < const Duration(milliseconds: 500)) return;
        entregue = gravados;
        ultimo = agora;
        final ate = gravados;
        fila = fila.then((_) async {
          try {
            await _canal.invokeMethod('transferir', {'req': req, 'arquivo': tmp.path, 'ate': ate, 'fim': false});
            await _canal.invokeMethod('progresso', {'req': req, 'total': tamanho, 'feito': ate});
          } catch (_) {}
        });
      });
      await fila;
      if (tmp.lengthSync() != tamanho) {
        // O placeholder está com o tamanho de outra versão: falha esta abertura e
        // põe o disco em dia (a próxima abre a versão certa).
        await _falhar(req);
        unawaited(_seguro(() => pr.sincronizar()));
        return;
      }
      await _canal.invokeMethod('transferir', {'req': req, 'arquivo': tmp.path, 'ate': tamanho, 'fim': true});
    } catch (e) {
      await fila;
      await _falhar(req);
      if (e is ApiErro && e.status == 404) unawaited(_seguro(() => pr.sincronizar()));
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _falhar(int req) async {
    try {
      await _canal.invokeMethod('falhar', {'req': req});
    } catch (_) {}
  }

  Future<void> _seguro(Future<void> Function() f) async {
    try {
      await f();
    } on ApiErro catch (e) {
      registrar('servidor: ${e.status} ${e.mensagem}');
      if (!e.transitorio) aoEvento(EventoSobDemanda('problema', '', e.mensagem));
    } catch (e, s) {
      registrar('falha: $e\n${s.toString().split('\n').take(6).join('\n')}');
    }
  }

  void encerrar() {
    _observador?.cancel();
    provedor?.encerrar();
  }
}

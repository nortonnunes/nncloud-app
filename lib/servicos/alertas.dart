// Os avisos de MENSAGEM NOVA: o que fazer quando chega mensagem de outra pessoa.
//
//   app na frente (janela em foco), mas noutra conversa ou noutra aba
//        → o quadro no canto do app (com a prévia) + som
//   app minimizado, na bandeja ou atrás de outras janelas
//        → a notificação do sistema (sem o texto da mensagem) + som
//   a conversa está aberta na tela, com a janela em foco
//        → nada: a pessoa está lendo
//
// A bolinha no ícone ao lado do relógio não passa por aqui: ela acompanha o
// contador de não lidas (ver `Bandeja`, no main).
//
// Duas fontes chamam `chegou`: a lista de conversas (`DetectorConversas`, que
// compara uma leitura com a anterior) e a conversa aberta (que recebe as
// mensagens novas antes da lista). A mesma mensagem pode chegar pelas duas — o
// id da última mensagem avisada, por conversa, é o que impede o aviso em dobro.
//
// ⚠️ "Não perturbe" (o status escolhido nas Conversas) cala o som e a
// notificação do sistema; o quadro no canto e a bolinha continuam.
import 'package:flutter/foundation.dart';

import 'armazenamento.dart';

/// Um aviso de mensagem nova (o quadro no canto do app e a notificação).
class AvisoMensagem {
  final int conversa;
  final String titulo;     // nome da pessoa (direta) ou do grupo
  final bool grupo;
  final String autor;      // quem escreveu a última (pode vir vazio)
  final String previa;     // texto puro, já cortado
  final String? avatar;
  final int quantas;
  final int ultimoId;
  final int seq;           // muda a cada aviso (o quadro reinicia o tempo)

  const AvisoMensagem({
    required this.conversa,
    required this.titulo,
    this.grupo = false,
    this.autor = '',
    this.previa = '',
    this.avatar,
    this.quantas = 1,
    this.ultimoId = 0,
    this.seq = 0,
  });

  AvisoMensagem juntar(AvisoMensagem novo, int seq) => AvisoMensagem(
        conversa: conversa,
        titulo: novo.titulo.isNotEmpty ? novo.titulo : titulo,
        grupo: novo.grupo || grupo,
        autor: novo.autor.isNotEmpty ? novo.autor : autor,
        previa: novo.previa.isNotEmpty ? novo.previa : previa,
        avatar: novo.avatar ?? avatar,
        quantas: quantas + novo.quantas,
        ultimoId: novo.ultimoId > ultimoId ? novo.ultimoId : ultimoId,
        seq: seq,
      );

  /// O título da notificação do sistema (direta: a pessoa; grupo: o grupo).
  String get tituloNotificacao => titulo.isEmpty ? 'Conversas' : titulo;

  /// O texto da notificação do sistema — SEM o conteúdo da mensagem: ela
  /// aparece na tela bloqueada e na central de notificações.
  String get textoNotificacao {
    if (conversa < 0) return 'É assim que a notificação de mensagem nova aparece.';
    final n = quantas < 1 ? 1 : quantas;
    if (grupo && autor.isNotEmpty) {
      return n == 1 ? '$autor enviou uma nova mensagem' : '$n novas mensagens · a última de $autor';
    }
    return n == 1 ? 'Enviou uma nova mensagem' : 'Enviou $n novas mensagens';
  }
}

class Alertas extends ChangeNotifier {
  final Armazenamento? arm;
  Alertas([this.arm]) {
    final a = arm;
    if (a != null) {
      som = a.pref<bool>(prefSom, true);
      quadro = a.pref<bool>(prefQuadro, true);
      notificacao = a.pref<bool>(prefNotificacao, true);
    }
  }

  static const prefSom = 'som_mensagem';   // o mesmo nome da 1.0.0 (quem desligou continua desligado)
  static const prefQuadro = 'aviso_quadro';
  static const prefNotificacao = 'aviso_notificacao';
  static const maxQuadros = 3;

  // Escolhas da pessoa (menu da conta → "Avisos de mensagem nova").
  bool som = true;
  bool quadro = true;
  bool notificacao = true;

  /// A janela está à vista E em foco (a pessoa está olhando para o app).
  bool _janelaEmFoco = true;
  bool get janelaEmFoco => _janelaEmFoco;
  set janelaEmFoco(bool v) {
    if (v == _janelaEmFoco) return;
    _janelaEmFoco = v;
    notifyListeners();
  }

  /// A conversa aberta NA TELA (aba Conversas à vista), ou null.
  int? _conversaNaTela;
  int? get conversaNaTela => _conversaNaTela;
  set conversaNaTela(int? v) {
    if (v == _conversaNaTela) return;
    _conversaNaTela = v;
    notifyListeners();
  }

  /// "Não perturbe" escolhido nas Conversas (vem do `/eu`).
  bool naoPerturbe = false;

  /// A pessoa está lendo esta conversa agora? (aí a mensagem é marcada como lida
  /// e não há aviso)
  bool olhando(int conversa) => _janelaEmFoco && _conversaNaTela == conversa;

  // Para onde vão os avisos (ligados no main; os testes trocam por contadores).
  Future<void> Function()? tocarSom;
  Future<void> Function(AvisoMensagem a)? mostrarNotificacao;

  /// Os quadros no canto do app, o mais novo primeiro.
  final quadros = ValueNotifier<List<AvisoMensagem>>(const []);

  final Map<int, int> _avisadoAte = {};   // conversa => id da última mensagem avisada
  DateTime? _ultimoSom;
  int _seq = 0;

  /// Chegou mensagem de outra pessoa nesta conversa.
  /// Devolve o que foi feito: 'nada', 'quadro' ou 'notificacao'.
  String chegou(AvisoMensagem a, {DateTime? agora}) {
    if (a.conversa <= 0) return 'nada';
    // A mesma mensagem pela lista e pela conversa aberta: um aviso só.
    if (a.ultimoId > 0) {
      final antes = _avisadoAte[a.conversa] ?? 0;
      if (a.ultimoId <= antes) return 'nada';
      _avisadoAte[a.conversa] = a.ultimoId;
    }
    if (olhando(a.conversa)) return 'nada';

    final aviso = AvisoMensagem(
      conversa: a.conversa,
      titulo: a.titulo,
      grupo: a.grupo,
      autor: a.autor,
      previa: a.previa,
      avatar: a.avatar,
      quantas: a.quantas < 1 ? 1 : a.quantas,
      ultimoId: a.ultimoId,
      seq: ++_seq,
    );
    var feito = 'nada';
    if (_janelaEmFoco) {
      if (quadro) {
        _empilhar(aviso);
        feito = 'quadro';
      }
    } else if (notificacao && !naoPerturbe) {
      final f = mostrarNotificacao;
      if (f != null) {
        f(aviso).catchError((_) {});
        feito = 'notificacao';
      }
    }
    _talvezSom(agora ?? DateTime.now());
    return feito;
  }

  /// Uma rajada (várias conversas de uma vez) toca o som uma vez só.
  void _talvezSom(DateTime agora) {
    if (!som || naoPerturbe) return;
    final u = _ultimoSom;
    if (u != null && agora.difference(u) < const Duration(seconds: 2)) return;
    _ultimoSom = agora;
    final f = tocarSom;
    if (f != null) f().catchError((_) {});
  }

  void _empilhar(AvisoMensagem a) {
    final l = [...quadros.value];
    final i = l.indexWhere((x) => x.conversa == a.conversa);
    if (i >= 0) {
      final junto = l.removeAt(i).juntar(a, a.seq);
      l.insert(0, junto);
    } else {
      l.insert(0, a);
    }
    quadros.value = l.take(maxQuadros).toList();
  }

  void fecharQuadro(int conversa) {
    final l = quadros.value.where((x) => x.conversa != conversa).toList();
    if (l.length != quadros.value.length) quadros.value = l;
  }

  void fecharTodos() {
    if (quadros.value.isNotEmpty) quadros.value = const [];
  }

  /// Abriu a conversa: o quadro dela não tem mais o que dizer.
  void abriu(int conversa) => fecharQuadro(conversa);

  /// Escolhas da pessoa (gravadas neste computador).
  void definir({bool? som, bool? quadro, bool? notificacao}) {
    if (som != null) this.som = som;
    if (quadro != null) this.quadro = quadro;
    if (notificacao != null) this.notificacao = notificacao;
    final a = arm;
    if (a != null) {
      a.definir(prefSom, this.som);
      a.definir(prefQuadro, this.quadro);
      a.definir(prefNotificacao, this.notificacao);
    }
    if (!this.quadro) fecharTodos();
    notifyListeners();
  }

  /// Algum aviso ligado? (sem nenhum, o "Testar" não tem o que mostrar)
  bool get algumLigado => som || quadro || notificacao;

  /// "Testar": cada aviso LIGADO uma vez (ignora o "Não perturbe" — é um teste).
  Future<void> testar() async {
    final exemplo = AvisoMensagem(
      conversa: -1,
      titulo: 'Teste dos avisos',
      previa: 'É assim que uma mensagem nova aparece aqui no canto.',
      seq: ++_seq,
    );
    if (quadro) _empilhar(exemplo);
    final n = mostrarNotificacao;
    if (notificacao && n != null) {
      await n(exemplo).catchError((_) {});
    }
    final f = tocarSom;
    if (som && f != null) await f().catchError((_) {});
  }

  /// Saiu da conta: nada do que foi avisado vale para a próxima pessoa.
  void limpar() {
    _avisadoAte.clear();
    fecharTodos();
  }
}

/// A leitura anterior de uma conversa (para saber o que é novo).
class _Visto {
  final int naoLidas;
  final int ultimoId;
  const _Visto(this.naoLidas, this.ultimoId);
}

/// Os dados de uma conversa da lista que o detector precisa.
class ConversaLida {
  final int id;
  final int naoLidas;
  final int ultimoId;      // 0 = o servidor não informa (versão antiga)
  final String titulo;
  final bool grupo;
  final String autor;
  final String previa;
  final String? avatar;
  const ConversaLida({
    required this.id,
    required this.naoLidas,
    this.ultimoId = 0,
    this.titulo = '',
    this.grupo = false,
    this.autor = '',
    this.previa = '',
    this.avatar,
  });
}

/// Compara cada leitura da lista de conversas com a anterior. A PRIMEIRA leitura
/// só guarda o estado: ao abrir o app, as não lidas acendem a bolinha, mas não
/// disparam uma rajada de avisos.
class DetectorConversas {
  final Map<int, _Visto> _antes = {};
  bool _primeira = true;

  List<AvisoMensagem> comparar(List<ConversaLida> lista) {
    final novos = <AvisoMensagem>[];
    final agora = <int, _Visto>{};
    for (final c in lista) {
      agora[c.id] = _Visto(c.naoLidas, c.ultimoId);
      if (_primeira || c.naoLidas <= 0) continue;
      final a = _antes[c.id];
      int quantas;
      if (a == null) {
        quantas = c.naoLidas;   // conversa nova na lista (ou desarquivada pela mensagem)
      } else if (c.naoLidas > a.naoLidas) {
        quantas = c.naoLidas - a.naoLidas;
      } else if (c.ultimoId > 0 && c.ultimoId > a.ultimoId) {
        quantas = 1;            // leu uma e chegou outra entre as duas leituras
      } else {
        continue;
      }
      novos.add(AvisoMensagem(
        conversa: c.id,
        titulo: c.titulo,
        grupo: c.grupo,
        autor: c.autor,
        previa: c.previa,
        avatar: c.avatar,
        quantas: quantas,
        ultimoId: c.ultimoId,
      ));
    }
    // Conversas que saíram da lista (arquivadas) somem do retrato; voltando com
    // mensagem nova, contam como novas.
    _antes
      ..clear()
      ..addAll(agora);
    _primeira = false;
    return novos;
  }
}

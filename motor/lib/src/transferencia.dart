// Envio e download de CONTEÚDO, direto com o armazenamento (S3) — o ponto único
// do sincronizador de pastas e do "NN Cloud" sob demanda do Windows.
//
// ⚠️ O servidor nunca confia no cliente: cada URL de parte trava o sha256 daquela
// parte e o `concluir` confere tamanho e impressão no S3. Aqui só se manda certo.
// ⚠️ O download é conferido pela impressão ANTES de alguém usar o arquivo: um
// arquivo que não confere é apagado e vira erro (tenta-se de novo depois).
import 'dart:io';

import 'api.dart';
import 'impressao.dart';

/// Resultado de um envio concluído: o item (formato de `/v1/cloud`) e o evento
/// (`criado`, `versao`, `conflito`…).
class EnvioConcluido {
  final Map<String, dynamic> item;
  final String? evento;
  const EnvioConcluido(this.item, this.evento);
  bool get conflito => evento == 'conflito';
}

/// Envia [f] (cuja impressão [imp] foi calculada com o arquivo no estado [st]).
/// [corpo] traz o destino: `espaco_id`/`pasta_id` (arquivo novo) ou
/// `item_id` + `base_versao` (versão nova). Devolve null quando o arquivo mudou
/// durante o envio — o envio é cancelado e quem chamou tenta de novo depois.
Future<EnvioConcluido?> enviarConteudo(Api api, File f, Impressao imp, FileStat st, Map<String, dynamic> corpo,
    {void Function(int bytes)? aoEnviar}) async {
  final pedido = <String, dynamic>{
    'tamanho': imp.tamanho,
    'impressao': imp.hex,
    'partes': imp.partes,
    'mtime_ms': st.modified.millisecondsSinceEpoch,
    'mime': 'application/octet-stream',
    ...corpo,
  };
  var ini = await api.iniciarEnvio(pedido);
  if (ini['reaproveitado'] == true) {
    return EnvioConcluido((ini['item'] as Map).cast<String, dynamic>(), ini['evento'] as String?);
  }
  final envio = ini['envio'] as String;
  var urls = (ini['partes'] as List).cast<Map<String, dynamic>>();
  final n = ini['n_partes'] as int;
  final feitas = <int>{};
  var tentativas = 0;
  while (feitas.length < n) {
    if (urls.length < n - feitas.length || urls.isEmpty) {
      final e = await api.estadoEnvio(envio, de: 1);
      feitas.addAll(((e['recebidas'] as List?) ?? []).cast<int>());
      urls = ((e['partes'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (urls.isEmpty && feitas.length < n) throw const ApiErro(0, 'O servidor não devolveu os endereços de envio.');
    }
    var falhou = false;
    for (final u in urls) {
      final num = u['n'] as int;
      if (feitas.contains(num)) continue;
      final inicio = u['inicio'] as int, tam = u['tamanho'] as int;
      final cab = ((u['cabecalhos'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      final code = await api.putParte(u['url'] as String, cab, f.openRead(inicio, inicio + tam), tam);
      if (code == 200) {
        feitas.add(num);
        aoEnviar?.call(tam);
      } else {
        falhou = true;
        if (code == 400 || code == 403) break;   // URL vencida ou arquivo mudou: pede de novo
      }
    }
    if (falhou) {
      if (++tentativas > 6) throw const ApiErro(0, 'O envio direto ao armazenamento falhou várias vezes.');
      await Future<void>.delayed(Duration(seconds: 1 << (tentativas - 1)));
      urls = [];
    }
  }
  // Arquivo mudou enquanto subia? Então não conclui com conteúdo misturado.
  final st2 = f.statSync();
  if (st2.size != st.size || st2.modified != st.modified) {
    await api.cancelarEnvio(envio);
    return null;
  }
  Map<String, dynamic> fim;
  try {
    fim = await api.concluirEnvio(envio);
  } on ApiErro catch (e) {
    if (e.status != 409) rethrow;
    ini = await api.estadoEnvio(envio);
    fim = await api.concluirEnvio(envio);
  }
  return EnvioConcluido((fim['item'] as Map).cast<String, dynamic>(), fim['evento'] as String?);
}

/// Baixa o conteúdo do item [id] para [destino] (sobrescreve) e confere a
/// impressão. [aoReceber] recebe o TOTAL já gravado (e já entregue ao sistema
/// operacional — dá para ler do arquivo). Devolve a impressão conferida.
Future<Impressao> baixarConteudo(Api api, int id, File destino,
    {String? impressaoEsperada, void Function(int gravados)? aoReceber, int tentativasMax = 5}) async {
  final b = await api.baixar(id);
  final esperada = impressaoEsperada ?? b['impressao'] as String?;
  final tamanho = b['tamanho'] as int?;
  if (b['url'] == null) {
    destino.writeAsBytesSync(const []);
  } else {
    var tentativas = 0;
    while (true) {
      final raf = destino.openSync(mode: FileMode.write);
      var gravados = 0;
      int code;
      try {
        code = await api.baixarPara(b['url'] as String, raf, aoReceber: (n) {
          gravados += n;
          aoReceber?.call(gravados);
        });
      } finally {
        raf.closeSync();
      }
      if (code == 200) break;
      if (++tentativas > tentativasMax) {
        if (destino.existsSync()) destino.deleteSync();
        throw ApiErro(0, 'O download falhou (código $code).');
      }
      await Future<void>.delayed(Duration(seconds: 1 << (tentativas - 1)));
    }
  }
  final imp = await Impressao.deArquivo(destino);
  if (imp == null || (esperada != null && imp.hex != esperada) || (tamanho != null && imp.tamanho != tamanho)) {
    if (destino.existsSync()) destino.deleteSync();
    throw const ApiErro(422, 'O arquivo baixado não confere com a nuvem (vai tentar de novo).');
  }
  return imp;
}

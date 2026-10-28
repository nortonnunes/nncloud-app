// Roda UM ciclo de um par (para o teste de interrupção com kill -9).
//   dart run test/bin/um_ciclo.dart <api> <token> <dados> <raiz> <par> <espaco> <computador>
import 'dart:io';

import 'package:nncloud_motor/motor.dart';

Future<void> main(List<String> a) async {
  final s = Sincronizador(api: Api(a[0], token: a[1]), dados: Directory(a[2]), computador: a[6]);
  final r = await s.ciclo([ConfigPar(id: int.parse(a[4]), raiz: a[3], espacoId: int.parse(a[5]))]);
  stdout.writeln('${r.single.estado} enviados=${r.single.enviados} baixados=${r.single.baixados}');
  exit(0);
}

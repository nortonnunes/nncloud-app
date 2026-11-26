import 'package:conecta_callcenter/config.dart';
import 'package:conecta_callcenter/widgets/rodape.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('servidor novo: texto e links vêm do bloco rodape', () {
    final d = RodapeApp.dados({
      'site_url': 'https://nnconecta.com',
      'rodape': {'texto': 'Conecta · Norton Nunes', 'denuncia': 'https://nnconecta.com/denuncia', 'lgpd': 'https://nnconecta.com/lgpd'},
    }, ano: 2026);
    expect(d.texto, '© 2026 Conecta · Norton Nunes');
    expect(d.denuncia, 'https://nnconecta.com/denuncia');
    expect(d.lgpd, 'https://nnconecta.com/lgpd');
  });

  test('LGPD despublicada (null) some; endereço que não é https não vira link', () {
    final d = RodapeApp.dados({
      'rodape': {'texto': 'Conecta', 'denuncia': 'javascript:alert(1)', 'lgpd': null},
    }, ano: 2026);
    expect(d.denuncia, isNull);
    expect(d.lgpd, isNull);
  });

  test('servidor antigo (sem o bloco): marca e links pelo site_url', () {
    final d = RodapeApp.dados({'site_url': 'https://nnconecta.com/', 'sistema': 'Conecta', 'empresa': 'Norton Nunes'}, ano: 2026);
    expect(d.texto, '© 2026 Conecta · Norton Nunes');
    expect(d.denuncia, 'https://nnconecta.com/denuncia');
    expect(d.lgpd, 'https://nnconecta.com/lgpd');
  });

  test('sem aparência ainda: só o texto, sem links', () {
    final d = RodapeApp.dados(null, ano: 2026);
    expect(d.texto, '© 2026 Conecta');
    expect(d.denuncia, isNull);
  });

  test('a versão do rodapé é a do app', () {
    expect(AppConfig.versao, '1.0.3');
  });
}

// A formatação do chat: o que o compositor manda tem de ser exatamente o HTML
// que o `App\Core\ChatHtml` do site aceita (b, i, u, span.im-cor-N, <br>), e o
// que chega do servidor tem de voltar a ser editável sem perder nada.
import 'package:conecta_callcenter/telas/conversas/chat_api.dart';
import 'package:conecta_callcenter/telas/conversas/formato.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ControladorFormatado _escrever(String t) {
  final c = ControladorFormatado();
  c.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  return c;
}

void _selecionar(ControladorFormatado c, int a, int b) {
  c.value = c.value.copyWith(selection: TextSelection(baseOffset: a, extentOffset: b));
}

void main() {
  group('compositor → HTML', () {
    test('texto sem formatação sai escapado e sem tags', () {
      final c = _escrever('a < b & "c"');
      expect(c.formatado, isFalse);
      expect(c.paraHtml(), 'a &lt; b &amp; "c"');
    });

    test('negrito numa seleção vira <b> só ali', () {
      final c = _escrever('oi mundo');
      _selecionar(c, 3, 8);
      c.alternarNegrito();
      expect(c.formatado, isTrue);
      expect(c.paraHtml(), 'oi <b>mundo</b>');
    });

    test('alternar de novo tira o negrito', () {
      final c = _escrever('mundo');
      _selecionar(c, 0, 5);
      c.alternarNegrito();
      c.alternarNegrito();
      expect(c.paraHtml(), 'mundo');
    });

    test('cor usa a classe da paleta, nunca style=', () {
      final c = _escrever('alerta');
      _selecionar(c, 0, 6);
      c.definirCor(1);
      expect(c.paraHtml(), '<span class="im-cor-1">alerta</span>');
      expect(c.paraHtml(), isNot(contains('style')));
    });

    test('combinação aninha na ordem fixa (cor > b > i > u)', () {
      final c = _escrever('x');
      _selecionar(c, 0, 1);
      c.alternarSublinhado();
      c.alternarItalico();
      c.alternarNegrito();
      c.definirCor(4);
      expect(c.paraHtml(), '<span class="im-cor-4"><b><i><u>x</u></i></b></span>');
    });

    test('quebra de linha vira <br> (nunca \\n cru — sairia numa linha só no site)', () {
      final c = _escrever('linha 1\nlinha 2');
      expect(c.paraHtml(), 'linha 1<br>linha 2');
    });

    test('estilo escolhido sem seleção vale para o que se digita a seguir', () {
      final c = _escrever('a');
      c.alternarNegrito();
      c.value = const TextEditingValue(text: 'ab', selection: TextSelection.collapsed(offset: 2));
      expect(c.paraHtml(), 'a<b>b</b>');
    });

    test('apagar no meio mantém o estilo do resto', () {
      final c = _escrever('abcdef');
      _selecionar(c, 2, 4);
      c.alternarNegrito();
      // apaga o "a"
      c.value = const TextEditingValue(text: 'bcdef', selection: TextSelection.collapsed(offset: 0));
      expect(c.paraHtml(), 'b<b>cd</b>ef');
    });

    test('inserir (emoji, menção) entra no cursor', () {
      final c = _escrever('oi ');
      c.inserir('@Ana ');
      expect(c.text, 'oi @Ana ');
    });
  });

  group('HTML do servidor → trechos', () {
    test('tags permitidas viram estilo; menção é marcada', () {
      final p = partesDoHtml('<b>oi</b> <span class="im-cor-3">verde</span> <span class="im-mention">@Ana</span>');
      expect(p.map((x) => x.texto).join(), 'oi verde @Ana');
      expect(p.first.estilo.b, isTrue);
      expect(p.firstWhere((x) => x.texto == 'verde').estilo.cor, 3);
      expect(p.firstWhere((x) => x.texto == '@Ana').mencao, isTrue);
    });

    test('entidades e <br> são decodificados', () {
      final p = partesDoHtml('a &lt;b&gt; &amp; c<br>d&#39;e');
      expect(p.map((x) => x.texto).join(), "a <b> & c\nd'e");
    });

    test('tag desconhecida é ignorada, o texto fica', () {
      final p = partesDoHtml('<script>x</script><font color="red">y</font>');
      expect(p.map((x) => x.texto).join(), 'xy');
      expect(p.every((x) => x.estilo == Estilo.nada), isTrue);
    });

    test('ida e volta: editar uma mensagem formatada não perde a formatação', () {
      const html = 'oi <b>forte</b><br><span class="im-cor-2"><i>laranja</i></span>';
      final c = ControladorFormatado()..carregar(html, html: true);
      expect(c.text, 'oi forte\nlaranja');
      expect(c.paraHtml(), html);
    });
  });

  group('tiques de leitura', () {
    test('direta: enviada → entregue → lida', () {
      EstadoLeitura e(int lida, int entregue) => EstadoLeitura({1: (99, 99, 'Eu'), 2: (lida, entregue, 'Ana')});
      expect(e(0, 0).tique(10, 1), 0);
      expect(e(0, 10).tique(10, 1), 1);
      expect(e(10, 10).tique(10, 1), 2);
    });

    test('grupo: lida só quando TODOS leram', () {
      const e = EstadoLeitura({1: (99, 99, 'Eu'), 2: (10, 10, 'Ana'), 3: (5, 10, 'Bia')});
      expect(e.tique(10, 1), 1);
    });
  });

  test('busca sem acento', () {
    expect(semAcento('Conceição ÁGUA'), 'conceicao agua');
  });
}

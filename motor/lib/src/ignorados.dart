// O que o aplicativo nunca sincroniza: lixo do sistema, temporários do Office
// e do LibreOffice, downloads pela metade e os arquivos do próprio app.
// A lista padrão vem do servidor (`/v1/cloud/eu` → config.ignorados), igual à
// `Config::IGNORADOS_PADRAO`; a pessoa pode acrescentar padrões.
//
// Padrões aceitos: nome exato ("Thumbs.db"), prefixo ("~$*"), sufixo
// ("*.tmp") e prefixo+sufixo (".~lock.*#"). Valem para o NOME, em qualquer nível.
const List<String> ignoradosPadrao = [
  '.DS_Store', 'Thumbs.db', 'desktop.ini', '._*', r'~$*', '.~lock.*#', '*.tmp', //
  '*.crdownload', '*.part', 'Icon\r', r'$RECYCLE.BIN', 'System Volume Information',
  '.Trashes', '.Spotlight-V100', '.fseventsd', '.nncloud', '.nncloud-*',
];

class Ignorados {
  final List<String> _exatos = [];
  final List<(String, String)> _curingas = [];

  Ignorados([Iterable<String> padroes = ignoradosPadrao]) {
    for (final p in padroes) {
      final i = p.indexOf('*');
      if (i < 0) {
        _exatos.add(p.toLowerCase());
      } else {
        _curingas.add((p.substring(0, i).toLowerCase(), p.substring(i + 1).toLowerCase()));
      }
    }
  }

  bool nome(String nome) {
    final n = nome.toLowerCase();
    if (_exatos.contains(n)) return true;
    for (final (ini, fim) in _curingas) {
      if (n.length >= ini.length + fim.length && n.startsWith(ini) && n.endsWith(fim)) return true;
    }
    return false;
  }

  /// Algum trecho do caminho relativo é ignorado?
  bool caminho(String caminho) => caminho.split('/').any(nome);
}

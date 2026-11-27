import 'dart:io';

/// Configuração do NN Unifi (até a 1.0.3: "APP Operação UNIFI"; até a 1.0.2: "Conecta Callcenter").
///
/// ⚠️ `nome` é só o que se VÊ. Os nomes internos continuam "Conecta Callcenter"
/// (pasta de dados, conta do chaveiro, chave "Run" do Windows, `ProductName` do
/// Runner.rc, cabeçalho User-Agent): trocá-los faria o computador perder a chave
/// e a autorização.
///
/// ⚠️ `versao` anda junto do `version` do pubspec: é ela que vai no cabeçalho
/// `X-NN-App-Versao` e que o servidor compara para oferecer a atualização.
class AppConfig {
  static const String nome = 'NN Unifi';
  static const String versao = '1.0.4';

  /// A API do NN Conecta. Em produção é sempre https; `--dart-define=CALLAPP_API=…`
  /// troca o endereço (o de teste só aceita http com `CALLAPP_TESTE=true`).
  static const String _apiDefinida = String.fromEnvironment('CALLAPP_API', defaultValue: 'https://api.nortonnunes.com.br');
  static const bool modoTeste = bool.fromEnvironment('CALLAPP_TESTE');

  static String get api {
    final v = _apiDefinida.trim().replaceAll(RegExp(r'/+$'), '');
    if (v.startsWith('https://')) return v;
    // ⚠️ Nada de http fora do modo de teste: a senha e o token iriam abertos na rede.
    if (modoTeste && v.startsWith('http://')) return v;
    return 'https://api.nortonnunes.com.br';
  }

  /// O sistema operacional, no formato do servidor.
  static String get so => Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux');

  /// Intervalos de consulta (o tempo real, quando ligado, só antecipa).
  static const Duration cicloComunicados = Duration(seconds: 20);
  static const Duration cicloEu = Duration(seconds: 30);
  static const Duration cicloLista = Duration(seconds: 8);
  static const Duration cicloConversa = Duration(seconds: 4);
  static const Duration cicloConversaOculta = Duration(seconds: 15);
  static const Duration cicloAparencia = Duration(minutes: 10);
  /// Reserva do aviso de versão nova (o principal vem no `/eu`, a cada 30 s).
  static const Duration cicloVersao = Duration(minutes: 10);
}

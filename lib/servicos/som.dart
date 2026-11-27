// Os sons do app: os três toques do comunicado (o mesmo arpejo do site) e o aviso
// de mensagem nova. Embutidos no app (`assets/som/`): nada é baixado.
//
// ⚠️ Nunca lança — som é aviso; sem placa de som (ou sem GStreamer no Linux) o
// app segue mudo.
import 'package:audioplayers/audioplayers.dart';

class Som {
  static final AudioPlayer _player = AudioPlayer(playerId: 'avisos');
  static bool ligado = true;

  static Future<void> comunicado() => _tocar('som/comunicado.wav');

  static Future<void> mensagem() async {
    if (!ligado) return;
    await _tocar('som/mensagem.wav');
  }

  static Future<void> _tocar(String arquivo) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(arquivo), volume: 0.9);
    } catch (_) {
      // sem som
    }
  }
}

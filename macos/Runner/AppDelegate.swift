import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // O app vive na bandeja: fechar/minimizar só ESCONDE a janela. Sair é pelo menu
  // do ícone ao lado do relógio (com confirmação).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

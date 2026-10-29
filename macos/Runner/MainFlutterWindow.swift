import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // "nncloud/sistema": iniciar com o macOS pelo SMAppService (macOS 13+).
    // Em versões anteriores responde "indisponivel" e o Dart grava um LaunchAgent.
    let canal = FlutterMethodChannel(name: "nncloud/sistema", binaryMessenger: flutterViewController.engine.binaryMessenger)
    canal.setMethodCallHandler { chamada, resposta in
      guard #available(macOS 13.0, *) else {
        resposta("indisponivel")
        return
      }
      let servico = SMAppService.mainApp
      switch chamada.method {
      case "estadoInicio":
        switch servico.status {
        case .enabled: resposta("ativo")
        case .requiresApproval: resposta("aprovacao")
        default: resposta("inativo")
        }
      case "iniciarComSistema":
        let ligar = ((chamada.arguments as? [String: Any])?["ligar"] as? Bool) ?? false
        do {
          if ligar { try servico.register() } else { try servico.unregister() }
          resposta(servico.status == .requiresApproval ? "aprovacao" : "ok")
        } catch {
          resposta(FlutterError(code: "falha", message: error.localizedDescription, details: nil))
        }
      default:
        resposta(FlutterMethodNotImplemented)
      }
    }

    if #available(macOS 13.0, *) {
      SobDemanda.registrar(flutterViewController.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }
}

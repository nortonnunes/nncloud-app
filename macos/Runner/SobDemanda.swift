// "NN Cloud" no Finder (File Provider): o aplicativo liga e desliga o domínio, entrega
// à extensão o endereço e o token (contêiner do grupo) e a avisa de mudanças.
//
// Canal "nncloud/fp":
//   estado ........... {suportado, ligado, aprovado}
//   ajustes .......... abre Ajustes do Sistema → Itens de Início e Extensões
//   ligar {api, token, liberar} / desligar
//   credenciais {api, token, liberar} — atualiza sem religar (token novo, preferência)
//   sinalizar ........ pede à extensão as mudanças agora (o app consulta a cada ciclo)
//   abrir ............ abre o NN Cloud no Finder
//
// ⚠️ Desligar REMOVE o domínio: o que estava baixado sai deste Mac (está na nuvem) e o
// que ainda não tinha subido é guardado pelo macOS numa pasta à parte — a tela diz isso.
import FileProvider
import FlutterMacOS
import Foundation

@available(macOS 13.0, *)
enum SobDemanda {
    static let dominio = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier("nncloud"), displayName: "NN Cloud")
    static let grupo = "52YUD97UMR.br.com.nortonnunes.nncloud"
    static let arquivo = "nncloud-fp.json"

    static func registrar(_ mensageiro: FlutterBinaryMessenger) {
        let canal = FlutterMethodChannel(name: "nncloud/fp", binaryMessenger: mensageiro)
        canal.setMethodCallHandler { chamada, resposta in
            let args = chamada.arguments as? [String: Any] ?? [:]
            switch chamada.method {
            case "estado":
                guard pasta() != nil else { return resposta(["suportado": false, "ligado": false, "aprovado": false]) }
                // ⚠️ `userEnabled`: no macOS 15+ o domínio novo nasce DESLIGADO até a pessoa
                // aprovar em Ajustes do Sistema. Sem esta informação a tela diria "ligado" e o
                // Finder mostraria uma pasta vazia que nunca carrega.
                NSFileProviderManager.getDomainsWithCompletionHandler { dominios, _ in
                    let d = dominios.first { $0.identifier == dominio.identifier }
                    DispatchQueue.main.async {
                        resposta(["suportado": true, "ligado": d != nil, "aprovado": d?.userEnabled ?? false])
                    }
                }
            case "ajustes":
                let u = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                resposta(NSWorkspace.shared.open(u) ? "ok" : "falha")
            case "ligar":
                do { try gravar(args) } catch { return resposta(FlutterError(code: "credenciais", message: error.localizedDescription, details: nil)) }
                NSFileProviderManager.add(dominio) { erro in
                    DispatchQueue.main.async {
                        resposta(erro.map { FlutterError(code: "dominio", message: $0.localizedDescription, details: nil) } ?? "ok")
                    }
                }
            case "credenciais":
                do { try gravar(args); resposta("ok") } catch {
                    resposta(FlutterError(code: "credenciais", message: error.localizedDescription, details: nil))
                }
            case "desligar":
                // ⚠️ `.preserveDirtyUserData`: o que ainda não tinha subido NÃO se perde —
                // o macOS o guarda numa pasta, cujo caminho volta para a tela mostrar.
                NSFileProviderManager.remove(dominio, mode: .preserveDirtyUserData) { guardado, erro in
                    if let p = pasta() { try? FileManager.default.removeItem(at: p.appendingPathComponent(arquivo)) }
                    DispatchQueue.main.async {
                        if let erro { return resposta(FlutterError(code: "dominio", message: erro.localizedDescription, details: nil)) }
                        resposta(guardado?.path ?? "ok")
                    }
                }
            case "apagarCredenciais":
                if let p = pasta() { try? FileManager.default.removeItem(at: p.appendingPathComponent(arquivo)) }
                resposta("ok")
            case "sinalizar":
                NSFileProviderManager(for: dominio)?.signalEnumerator(for: .workingSet) { _ in }
                resposta("ok")
            case "abrir":
                guard let m = NSFileProviderManager(for: dominio) else { return resposta("desligado") }
                m.getUserVisibleURL(for: .rootContainer) { url, erro in
                    DispatchQueue.main.async {
                        if let url { NSWorkspace.shared.open(url) }
                        resposta(url?.path ?? erro?.localizedDescription ?? "")
                    }
                }
            default:
                resposta(FlutterMethodNotImplemented)
            }
        }
    }

    static func pasta() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo)
    }

    /// Mesmo formato de NNCloudKit/Credenciais.swift (arquivo 0600 no contêiner do grupo).
    static func gravar(_ a: [String: Any]) throws {
        guard let p = pasta() else { throw NSError(domain: "nncloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sem acesso à pasta compartilhada (assinatura)."]) }
        let j: [String: Any] = ["api": a["api"] as? String ?? "", "token": a["token"] as? String ?? "", "liberarAposEnviar": a["liberar"] as? Bool ?? false]
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        let tmp = p.appendingPathComponent(arquivo + ".tmp")
        try JSONSerialization.data(withJSONObject: j).write(to: tmp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        let alvo = p.appendingPathComponent(arquivo)
        try? FileManager.default.removeItem(at: alvo)
        try FileManager.default.moveItem(at: tmp, to: alvo)
    }
}

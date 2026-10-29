// O que o aplicativo e a extensão File Provider dividem: o endereço da API, o
// token do computador e as preferências do sob demanda.
//
// ⚠️ Mora no CONTÊINER DO GRUPO (App Group com o prefixo do time), que só apps
// assinados pelo mesmo time com o mesmo grupo alcançam. A extensão roda em
// sandbox e NÃO enxerga o chaveiro de login onde o app guarda o token — por isso
// o app grava uma cópia aqui (arquivo 0600) e a apaga ao desconectar.
import Foundation

public struct Credenciais: Codable, Equatable {
    public var api: String
    public var token: String
    /// Depois de um envio concluído, o arquivo sai do disco (fica só na nuvem).
    public var liberarAposEnviar: Bool

    public init(api: String, token: String, liberarAposEnviar: Bool = false) {
        self.api = api
        self.token = token
        self.liberarAposEnviar = liberarAposEnviar
    }

    public static let grupo = "52YUD97UMR.br.com.nortonnunes.nncloud"
    static let nomeArquivo = "nncloud-fp.json"

    /// Pasta do grupo (nil = o app não tem o direito do grupo — assinatura errada).
    public static func pasta(_ grupo: String = grupo) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo)
    }

    public static func ler(em pasta: URL? = pasta()) -> Credenciais? {
        guard let p = pasta, let d = try? Data(contentsOf: p.appendingPathComponent(nomeArquivo)) else { return nil }
        return try? JSONDecoder().decode(Credenciais.self, from: d)
    }

    public func gravar(em pasta: URL? = pasta()) throws {
        guard let p = pasta else { throw ErroAPI(0, "Sem acesso à pasta compartilhada do NN Cloud (assinatura do aplicativo).") }
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        let alvo = p.appendingPathComponent(Credenciais.nomeArquivo)
        let tmp = p.appendingPathComponent(Credenciais.nomeArquivo + ".tmp")
        try JSONEncoder().encode(self).write(to: tmp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try? FileManager.default.removeItem(at: alvo)
        try FileManager.default.moveItem(at: tmp, to: alvo)
    }

    public static func apagar(em pasta: URL? = pasta()) {
        guard let p = pasta else { return }
        try? FileManager.default.removeItem(at: p.appendingPathComponent(nomeArquivo))
    }
}

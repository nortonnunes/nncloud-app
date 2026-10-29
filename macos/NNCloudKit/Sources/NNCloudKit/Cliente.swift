// Cliente da API `/v1/cloud` para o NN Cloud sob demanda (a extensão File Provider).
//
// ⚠️ A resposta vem em `{"data": …}` e o erro em `{"error": {"status", "message"}}`.
// ⚠️ Os bytes nunca passam pelo servidor do NN Conecta: o envio é PUT direto no S3
// (URL assinada, com o sha256 da parte travado nela) e o download é GET direto.
import Foundation

public struct ErroAPI: Error, LocalizedError, Equatable {
    public let status: Int          // 0 = sem rede / tempo esgotado
    public let mensagem: String
    public init(_ status: Int, _ mensagem: String) {
        self.status = status
        self.mensagem = mensagem
    }
    public var errorDescription: String? { mensagem }
    public var transitorio: Bool { status == 0 || status == 429 || status >= 500 }
}

/// Um item da árvore do NN Cloud (veja app/Core/NnCloud/Dominio.php).
public struct ItemFP: Codable, Equatable {
    public struct Pode: Codable, Equatable {
        public let escrever, renomear, mover, apagar, criar: Bool
    }
    public let id: String
    public let pai: String?
    public let nome: String
    public let tipo: String
    public let tamanho: Int?
    public let impressao: String?
    public let versao: Int
    public let versao_meta: Int
    public let criado_ms: Int64
    public let modificado_ms: Int64
    public let papel: Int
    public let virtual: Bool?
    public let pode: Pode

    public var ehPasta: Bool { tipo == "pasta" }
    /// O id numérico de um item real ("i12" → 12).
    public var numero: Int? { Identificador.numeroDoItem(id) }
}

public struct Mudancas: Codable {
    public let estado: String          // ok | expirada
    public let itens: [ItemFP]
    public let removidos: [String]
    public let ancora: String?
    public let mais: Bool
}

/// Para onde algo vai no servidor (o que os endpoints de escrita entendem).
public enum Destino: Equatable {
    case espaco(Int)
    case pasta(Int)

    var json: [String: Any] {
        switch self {
        case .espaco(let id): return ["espaco_id": id]
        case .pasta(let id): return ["pasta_id": id]
        }
    }
}

public enum Identificador {
    public static let raiz = "raiz"
    public static let virtuais: Set<String> = ["raiz", "meu", "comigo", "drives"]

    public static func numeroDoItem(_ id: String) -> Int? {
        id.hasPrefix("i") ? Int(id.dropFirst()) : nil
    }

    /// O destino de uma escrita dentro de um contêiner. nil = não aceita escrita.
    public static func destino(_ pai: String, meuDrive: Int) -> Destino? {
        if pai == "meu" { return .espaco(meuDrive) }
        if pai.hasPrefix("e"), let n = Int(pai.dropFirst()) { return .espaco(n) }
        if let n = numeroDoItem(pai) { return .pasta(n) }
        return nil
    }
}

public final class ClienteNNCloud {
    public let base: URL
    public let token: String
    let sessao: URLSession
    private var meuDriveCache: Int?

    public init(base: URL, token: String, sessao: URLSession? = nil) {
        self.base = base
        self.token = token
        if let sessao {
            self.sessao = sessao
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 60 * 60
            cfg.waitsForConnectivity = false
            cfg.httpAdditionalHeaders = ["User-Agent": "NN Cloud FileProvider (macOS)"]
            self.sessao = URLSession(configuration: cfg)
        }
    }

    // MARK: - Base

    func pedir(_ metodo: String, _ caminho: String, query: [String: String] = [:], corpo: [String: Any]? = nil) async throws -> Any {
        var comp = URLComponents(url: base.appendingPathComponent("v1/cloud/" + caminho), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comp.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comp.url!)
        req.httpMethod = metodo
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let corpo {
            req.httpBody = try JSONSerialization.data(withJSONObject: corpo)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let dados: Data
        let resp: URLResponse
        do {
            (dados, resp) = try await sessao.data(for: req)
        } catch {
            throw ErroAPI(0, "Sem conexão com o NN Cloud (\(error.localizedDescription)).")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: dados)
        if (200..<300).contains(status), let j = json as? [String: Any], let d = j["data"] {
            return d
        }
        let msg = ((json as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        throw ErroAPI(status == 0 ? 502 : status, msg ?? "O servidor respondeu \(status).")
    }

    func decodificar<T: Decodable>(_ tipo: T.Type, _ v: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: v))
    }

    // MARK: - Árvore

    public func meuDrive() async throws -> Int {
        if let m = meuDriveCache { return m }
        let eu = try await pedir("GET", "eu") as? [String: Any]
        guard let id = (eu?["meu_drive"] as? [String: Any])?["id"] as? Int else { throw ErroAPI(502, "Resposta inesperada do servidor.") }
        meuDriveCache = id
        return id
    }

    public func item(_ id: String) async throws -> ItemFP {
        let d = try await pedir("GET", "fp/item", query: ["id": id]) as? [String: Any]
        return try decodificar(ItemFP.self, d?["item"] as Any)
    }

    public func filhos(_ id: String, depoisDe: Int) async throws -> (itens: [ItemFP], proximo: Int?) {
        let d = try await pedir("GET", "fp/filhos", query: ["id": id, "depois_de": String(depoisDe)]) as? [String: Any] ?? [:]
        return (try decodificar([ItemFP].self, d["itens"] ?? []), d["proximo"] as? Int)
    }

    public func ancora() async throws -> String {
        guard let a = (try await pedir("GET", "fp/ancora") as? [String: Any])?["ancora"] as? String else {
            throw ErroAPI(502, "Resposta inesperada do servidor.")
        }
        return a
    }

    public func mudancas(desde ancora: String) async throws -> Mudancas {
        try decodificar(Mudancas.self, try await pedir("POST", "fp/mudancas", corpo: ["ancora": ancora]))
    }

    // MARK: - Escrita

    /// Cria uma pasta e devolve o id do item.
    public func criarPasta(em destino: Destino, nome: String) async throws -> Int {
        var corpo = destino.json
        corpo["nome"] = nome
        guard let id = ((try await pedir("POST", "pastas", corpo: corpo) as? [String: Any])?["pasta"] as? [String: Any])?["id"] as? Int else {
            throw ErroAPI(502, "Resposta inesperada do servidor.")
        }
        return id
    }

    public func renomear(_ id: Int, para nome: String) async throws {
        _ = try await pedir("POST", "itens/\(id)/renomear", corpo: ["nome": nome])
    }

    public func mover(_ id: Int, para destino: Destino) async throws {
        _ = try await pedir("POST", "itens/\(id)/mover", corpo: destino.json)
    }

    /// Manda para a lixeira do NN Cloud (30 dias para restaurar).
    public func lixeira(_ id: Int) async throws {
        let d = try await pedir("POST", "itens/lixeira", corpo: ["ids": [id], "confirmado": 1]) as? [String: Any]
        if let r = (d?["itens"] as? [[String: Any]])?.first, (r["ok"] as? Bool) != true {
            throw ErroAPI(r["codigo"] as? Int ?? 422, r["erro"] as? String ?? "O item não foi para a lixeira.")
        }
    }

    // MARK: - Download

    /// Baixa o conteúdo para `destino` (arquivo temporário) e confere a impressão.
    public func baixar(_ id: Int, impressaoEsperada: String?, para destino: URL, progresso: Progress? = nil) async throws {
        let d = try await pedir("GET", "itens/\(id)/baixar") as? [String: Any] ?? [:]
        if let u = d["url"] as? String, let url = URL(string: u) {
            let (tmp, resp): (URL, URLResponse)
            do {
                (tmp, resp) = try await sessao.download(from: url)
            } catch {
                throw ErroAPI(0, "O download foi interrompido (\(error.localizedDescription)).")
            }
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard st == 200 else { throw ErroAPI(st == 0 ? 0 : 502, "O armazenamento respondeu \(st) ao download.") }
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.moveItem(at: tmp, to: destino)
        } else {
            try Data().write(to: destino)   // arquivo vazio não tem objeto no armazenamento
        }
        if let esperada = impressaoEsperada {
            guard let imp = try Impressao.deArquivo(destino), imp.hex == esperada else {
                try? FileManager.default.removeItem(at: destino)
                throw ErroAPI(502, "O arquivo baixado não confere com a nuvem (vai tentar de novo).")
            }
        }
        progresso?.completedUnitCount = progresso?.totalUnitCount ?? 0
    }

    // MARK: - Envio

    public struct ResultadoEnvio {
        public let itemId: Int
        public let conflito: Bool
    }

    /// Envia um arquivo: novo (`destino`) ou nova versão de um item (`itemId` + `baseVersao`).
    /// Partes direto no S3; `conflito` = a nuvem mudou antes, e o que subiu virou a cópia.
    public func enviar(_ arquivo: URL, nome: String, destino: Destino?, itemId: Int? = nil, baseVersao: Int? = nil,
                       mtime: Date? = nil, progresso: Progress? = nil) async throws -> ResultadoEnvio {
        guard let imp = try Impressao.deArquivo(arquivo) else { throw ErroAPI(409, "O arquivo está sendo gravado; tenta de novo em seguida.") }
        var corpo: [String: Any] = [
            "nome": nome, "tamanho": imp.tamanho, "impressao": imp.hex, "partes": imp.partes,
            "mime": "application/octet-stream",
        ]
        if let mtime { corpo["mtime_ms"] = Int64(mtime.timeIntervalSince1970 * 1000) }
        if let itemId {
            corpo["item_id"] = itemId
            corpo["base_versao"] = baseVersao ?? 0
        } else if let destino {
            corpo.merge(destino.json) { a, _ in a }
        }
        progresso?.totalUnitCount = Int64(max(imp.tamanho, 1))
        let ini = try await pedir("POST", "envios", corpo: corpo) as? [String: Any] ?? [:]
        if (ini["reaproveitado"] as? Bool) == true {
            progresso?.completedUnitCount = progresso?.totalUnitCount ?? 0
            return try resultado(ini)
        }
        guard let envio = ini["envio"] as? String, let n = ini["n_partes"] as? Int else { throw ErroAPI(502, "Resposta inesperada do servidor.") }
        var urls = ini["partes"] as? [[String: Any]] ?? []
        var feitas = Set<Int>()
        var tentativas = 0
        let arq = try FileHandle(forReadingFrom: arquivo)
        defer { try? arq.close() }
        while feitas.count < n {
            if urls.isEmpty {
                let e = try await pedir("GET", "envios/\(envio)", query: ["de": "1"]) as? [String: Any] ?? [:]
                feitas.formUnion((e["recebidas"] as? [Int]) ?? [])
                urls = e["partes"] as? [[String: Any]] ?? []
                if urls.isEmpty && feitas.count < n { throw ErroAPI(0, "O servidor não devolveu os endereços de envio.") }
            }
            var falhou = false
            for u in urls {
                guard let num = u["n"] as? Int, !feitas.contains(num), let s = u["url"] as? String, let url = URL(string: s),
                      let ini = u["inicio"] as? Int, let tam = u["tamanho"] as? Int else { continue }
                try arq.seek(toOffset: UInt64(ini))
                let dados = try arq.read(upToCount: tam) ?? Data()
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                for (k, v) in (u["cabecalhos"] as? [String: Any]) ?? [:] where k.lowercased() != "content-length" {
                    req.setValue("\(v)", forHTTPHeaderField: k)
                }
                let st = (try? await sessao.upload(for: req, from: dados)).map { ($0.1 as? HTTPURLResponse)?.statusCode ?? 0 } ?? 0
                if st == 200 {
                    feitas.insert(num)
                    progresso?.completedUnitCount += Int64(tam)
                } else {
                    falhou = true
                    if st == 400 || st == 403 { break }   // URL vencida ou parte diferente: pede de novo
                }
            }
            if falhou {
                tentativas += 1
                if tentativas > 6 { throw ErroAPI(0, "O envio direto ao armazenamento falhou várias vezes.") }
                try await Task.sleep(nanoseconds: UInt64(1 << (tentativas - 1)) * 1_000_000_000)
                urls = []
            } else if feitas.count < n {
                urls = []
            }
        }
        let fim: [String: Any]
        do {
            fim = try await pedir("POST", "envios/\(envio)/concluir") as? [String: Any] ?? [:]
        } catch let e as ErroAPI where e.status == 409 {
            fim = try await pedir("POST", "envios/\(envio)/concluir") as? [String: Any] ?? [:]
        }
        return try resultado(fim)
    }

    private func resultado(_ d: [String: Any]) throws -> ResultadoEnvio {
        guard let id = (d["item"] as? [String: Any])?["id"] as? Int else { throw ErroAPI(502, "Resposta inesperada do servidor.") }
        return ResultadoEnvio(itemId: id, conflito: (d["evento"] as? String) == "conflito")
    }
}

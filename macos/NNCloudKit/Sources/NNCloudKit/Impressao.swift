// A IMPRESSÃO de um arquivo — contrato com o servidor (app/Core/NnCloud/Impressao.php)
// e com o motor Dart (motor/lib/src/impressao.dart):
//   hex( sha256( concatenação dos sha256 de cada parte de 8 MiB ) )
// Arquivo vazio = uma parte vazia. Cada parte também viaja em base64 (o S3 confere
// a parte enviada contra ela).
import CryptoKit
import Foundation

public enum Impressao {
    public static let tamanhoParte = 8_388_608

    public static func nPartes(_ tamanho: Int) -> Int {
        tamanho <= 0 ? 1 : (tamanho + tamanhoParte - 1) / tamanhoParte
    }

    public static func tamanhoDaParte(_ tamanho: Int, _ n: Int) -> Int {
        let total = nPartes(tamanho)
        guard n >= 1, n <= total else { return 0 }
        return n < total ? tamanhoParte : tamanho - tamanhoParte * (total - 1)
    }

    public struct Resultado: Equatable {
        public let partes: [String]   // sha256 de cada parte, em base64
        public let hex: String
        public let tamanho: Int
    }

    public static func dePartes(_ digests: [Data], tamanho: Int) -> Resultado {
        var todos = Data()
        for d in digests { todos.append(d) }
        let hex = SHA256.hash(data: todos).map { String(format: "%02x", $0) }.joined()
        return Resultado(partes: digests.map { $0.base64EncodedString() }, hex: hex, tamanho: tamanho)
    }

    public static func deDados(_ dados: Data) -> Resultado {
        var digests: [Data] = []
        for n in 1...nPartes(dados.count) {
            let ini = (n - 1) * tamanhoParte
            let fim = ini + tamanhoDaParte(dados.count, n)
            digests.append(Data(SHA256.hash(data: dados.subdata(in: ini..<fim))))
        }
        return dePartes(digests, tamanho: dados.count)
    }

    /// Lê o arquivo em blocos de 1 MiB (nunca inteiro na memória). nil = mudou de
    /// tamanho durante a leitura (está sendo gravado).
    public static func deArquivo(_ url: URL) throws -> Resultado? {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let tamanho = Int(try h.seekToEnd())
        try h.seek(toOffset: 0)
        var digests: [Data] = []
        for n in 1...nPartes(tamanho) {
            var sha = SHA256()
            var falta = tamanhoDaParte(tamanho, n)
            while falta > 0 {
                guard let bloco = try h.read(upToCount: min(falta, 1_048_576)), !bloco.isEmpty else { return nil }
                sha.update(data: bloco)
                falta -= bloco.count
            }
            digests.append(Data(sha.finalize()))
        }
        if Int(try h.seekToEnd()) != tamanho { return nil }
        return dePartes(digests, tamanho: tamanho)
    }
}

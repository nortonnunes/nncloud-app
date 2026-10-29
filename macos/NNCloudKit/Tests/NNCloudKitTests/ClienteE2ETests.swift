import Foundation
import XCTest
@testable import NNCloudKit

/// Ponta a ponta contra a API PHP real (:8782) e o S3 falso (:8790).
///   NCL_FP_API=http://127.0.0.1:8782 NCL_FP_TOKEN=nncl_… swift test
final class ClienteE2ETests: XCTestCase {
    func testFluxoCompleto() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let api = env["NCL_FP_API"], let token = env["NCL_FP_TOKEN"] else {
            throw XCTSkip("defina NCL_FP_API e NCL_FP_TOKEN (servidores de teste no ar)")
        }
        let c = ClienteNNCloud(base: URL(string: api)!, token: token)
        let raiz = try await c.filhos("raiz", depoisDe: 0)
        XCTAssertEqual(raiz.itens.map(\.id), ["meu", "comigo", "drives"])
        let meu = try await c.meuDrive()

        // Pasta + arquivo pequeno + arquivo em 2 partes.
        let pasta = try await c.criarPasta(em: .espaco(meu), nome: "FP Swift")
        let tmp = FileManager.default.temporaryDirectory
        let peq = tmp.appendingPathComponent("peq.txt")
        try Data("olá do Finder".utf8).write(to: peq)
        let r1 = try await c.enviar(peq, nome: "peq.txt", destino: .pasta(pasta))
        XCTAssertFalse(r1.conflito)
        let grande = tmp.appendingPathComponent("grande.bin")
        let bytes = Data((0..<(Impressao.tamanhoParte + 1234)).map { UInt8(($0 * 13) % 256) })
        try bytes.write(to: grande)
        let prog = Progress(totalUnitCount: 1)
        let r2 = try await c.enviar(grande, nome: "grande.bin", destino: .pasta(pasta), progresso: prog)
        XCTAssertEqual(prog.completedUnitCount, Int64(bytes.count))

        let filhos = try await c.filhos("i\(pasta)", depoisDe: 0).itens
        XCTAssertEqual(Set(filhos.map(\.nome)), ["peq.txt", "grande.bin"])
        let itemGrande = try await c.item("i\(r2.itemId)")
        XCTAssertEqual(itemGrande.tamanho, bytes.count)
        XCTAssertEqual(itemGrande.pai, "i\(pasta)")

        // Download confere a impressão.
        let baixado = tmp.appendingPathComponent("baixado.bin")
        try await c.baixar(r2.itemId, impressaoEsperada: itemGrande.impressao, para: baixado)
        XCTAssertEqual(try Data(contentsOf: baixado), bytes)
        // Impressão errada: recusa e não deixa o arquivo.
        do {
            try await c.baixar(r2.itemId, impressaoEsperada: String(repeating: "0", count: 64), para: baixado)
            XCTFail("deveria recusar")
        } catch let e as ErroAPI {
            XCTAssertEqual(e.status, 502)
            XCTAssertFalse(FileManager.default.fileExists(atPath: baixado.path))
        }

        // Âncora → mudanças: nova versão, renomear, mover, lixeira.
        let a0 = try await c.ancora()
        try Data("versão 2".utf8).write(to: peq)
        let antes = try await c.item("i\(r1.itemId)")
        let r3 = try await c.enviar(peq, nome: "peq.txt", destino: nil, itemId: r1.itemId, baseVersao: antes.versao)
        XCTAssertEqual(r3.itemId, r1.itemId)
        XCTAssertFalse(r3.conflito)
        try await c.renomear(r2.itemId, para: "grande-renomeado.bin")
        try await c.mover(r2.itemId, para: .espaco(meu))
        let sub = try await c.criarPasta(em: .pasta(pasta), nome: "Sub")
        try await c.lixeira(sub)
        let m = try await c.mudancas(desde: a0)
        XCTAssertEqual(m.estado, "ok")
        let porId = Dictionary(uniqueKeysWithValues: m.itens.map { ($0.id, $0) })
        XCTAssertEqual(porId["i\(r1.itemId)"]?.versao, antes.versao + 1)
        XCTAssertEqual(porId["i\(r2.itemId)"]?.nome, "grande-renomeado.bin")
        XCTAssertEqual(porId["i\(r2.itemId)"]?.pai, "meu")
        XCTAssertTrue(m.removidos.contains("i\(sub)"))

        // Versão de base velha: o que sobe vira cópia de conflito.
        try Data("versão 3 de outro lugar".utf8).write(to: peq)
        let r4 = try await c.enviar(peq, nome: "peq.txt", destino: nil, itemId: r1.itemId, baseVersao: antes.versao)
        XCTAssertTrue(r4.conflito)
        XCTAssertNotEqual(r4.itemId, r1.itemId)

        // Erros: item inexistente e destino virtual.
        do {
            _ = try await c.item("i999999999")
            XCTFail("deveria dar 404")
        } catch let e as ErroAPI {
            XCTAssertEqual(e.status, 404)
        }
        try await c.lixeira(pasta)
    }
}

import Foundation
import XCTest
@testable import NNCloudKit

/// A impressão é contrato com o PHP: o fixture é gerado pelo próprio servidor
/// (motor/test/fixtures/contrato_php.json, o mesmo que o motor Dart confere).
final class ImpressaoTests: XCTestCase {
    func testIgualAoPHP() throws {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fx = raiz.appendingPathComponent("motor/test/fixtures/contrato_php.json")
        let j = try JSONSerialization.jsonObject(with: Data(contentsOf: fx)) as! [String: Any]
        let casos = j["impressoes"] as! [[String: Any]]
        XCTAssertGreaterThan(casos.count, 3)
        for c in casos {
            let tam = c["tamanho"] as! Int
            // Mesmo gerador do fixture (contrato.php): byte i = (i * 7) % 251.
            let dados = Data((0..<tam).map { UInt8(($0 * 7) % 251) })
            let r = Impressao.deDados(dados)
            XCTAssertEqual(r.hex, c["hex"] as? String, "tamanho \(tam)")
            XCTAssertEqual(r.partes, c["partes"] as? [String], "tamanho \(tam)")
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("imp-\(tam).bin")
            try dados.write(to: tmp)
            XCTAssertEqual(try Impressao.deArquivo(tmp), r, "do arquivo, tamanho \(tam)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    func testDestinos() {
        XCTAssertEqual(Identificador.destino("meu", meuDrive: 7), .espaco(7))
        XCTAssertEqual(Identificador.destino("e5", meuDrive: 7), .espaco(5))
        XCTAssertEqual(Identificador.destino("i9", meuDrive: 7), .pasta(9))
        XCTAssertNil(Identificador.destino("comigo", meuDrive: 7))
        XCTAssertNil(Identificador.destino("drives", meuDrive: 7))
        XCTAssertNil(Identificador.destino("raiz", meuDrive: 7))
    }

    func testCredenciais() throws {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("cred-\(UUID().uuidString)")
        let c = Credenciais(api: "https://api.exemplo", token: "nncl_x", liberarAposEnviar: true)
        try c.gravar(em: p)
        XCTAssertEqual(Credenciais.ler(em: p), c)
        let perm = try FileManager.default.attributesOfItem(atPath: p.appendingPathComponent("nncloud-fp.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(perm, 0o600)
        Credenciais.apagar(em: p)
        XCTAssertNil(Credenciais.ler(em: p))
    }
}

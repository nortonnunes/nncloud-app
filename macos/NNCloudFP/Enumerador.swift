// Enumeradores: o conteúdo de uma pasta (página a página) e o CONJUNTO DE TRABALHO,
// por onde chegam as mudanças feitas fora deste computador.
//
// ⚠️ Na extensão replicada, o macOS pergunta as mudanças só ao conjunto de trabalho
// (`.workingSet`). A âncora é o token de `fp/mudancas` (o estado mora no servidor).
// Âncora que o servidor não reconhece → `syncAnchorExpired`, e o sistema relista.
import FileProvider
import Foundation

final class EnumeradorPasta: NSObject, NSFileProviderEnumerator {
    let pasta: String
    let cliente: () throws -> ClienteNNCloud

    init(pasta: String, cliente: @escaping () throws -> ClienteNNCloud) {
        self.pasta = pasta
        self.cliente = cliente
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        // As páginas iniciais do sistema são marcadores; as nossas carregam a posição.
        let inicio = page.rawValue == NSFileProviderPage.initialPageSortedByName as Data
            || page.rawValue == NSFileProviderPage.initialPageSortedByDate as Data
            ? 0 : (Int(String(decoding: page.rawValue, as: UTF8.self)) ?? 0)
        Task {
            do {
                let r = try await cliente().filhos(pasta, depoisDe: inicio)
                observer.didEnumerate(r.itens.map(Item.init))
                observer.finishEnumerating(upTo: r.proximo.map { NSFileProviderPage(Data(String($0).utf8)) })
            } catch {
                observer.finishEnumeratingWithError(erroDoSistema(error))
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("pasta".utf8)))
    }
}

final class EnumeradorTrabalho: NSObject, NSFileProviderEnumerator {
    let cliente: () throws -> ClienteNNCloud

    init(cliente: @escaping () throws -> ClienteNNCloud) {
        self.cliente = cliente
    }

    func invalidate() {}

    /// O conjunto de trabalho começa vazio: as pastas descem quando a pessoa as abre.
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let token = String(decoding: anchor.rawValue, as: UTF8.self)
        Task {
            do {
                let m = try await cliente().mudancas(desde: token)
                guard m.estado == "ok", let nova = m.ancora else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
                    return
                }
                if !m.itens.isEmpty { observer.didUpdate(m.itens.map(Item.init)) }
                if !m.removidos.isEmpty { observer.didDeleteItems(withIdentifiers: m.removidos.map(Item.doSistema)) }
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(Data(nova.utf8)), moreComing: m.mais)
            } catch {
                observer.finishEnumeratingWithError(erroDoSistema(error))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        Task {
            let a = try? await cliente().ancora()
            completionHandler(a.map { NSFileProviderSyncAnchor(Data($0.utf8)) })
        }
    }
}

// Um item do NN Cloud como o macOS o vê (NSFileProviderItem).
//
// Identificadores: os NOSSOS ("raiz", "meu", "comigo", "drives", "e5", "i12") viram os
// do sistema; "raiz" é o `.rootContainer`. A versão do CONTEÚDO é a `versao` do servidor
// (muda quando o arquivo muda); a dos METADADOS junta a rev do item e o nome (renomear um
// drive não mexe na rev de item nenhum).
import FileProvider
import UniformTypeIdentifiers

final class Item: NSObject, NSFileProviderItem {
    let fp: ItemFP

    init(_ fp: ItemFP) {
        self.fp = fp
    }

    static func doSistema(_ nosso: String) -> NSFileProviderItemIdentifier {
        nosso == Identificador.raiz ? .rootContainer : NSFileProviderItemIdentifier(nosso)
    }

    static func nosso(_ id: NSFileProviderItemIdentifier) -> String {
        id == .rootContainer ? Identificador.raiz : id.rawValue
    }

    var itemIdentifier: NSFileProviderItemIdentifier { Item.doSistema(fp.id) }
    var parentItemIdentifier: NSFileProviderItemIdentifier { fp.pai.map(Item.doSistema) ?? .rootContainer }
    var filename: String { fp.nome }

    var contentType: UTType {
        fp.ehPasta ? .folder : (UTType(filenameExtension: (fp.nome as NSString).pathExtension) ?? .data)
    }

    var documentSize: NSNumber? { fp.ehPasta ? nil : NSNumber(value: fp.tamanho ?? 0) }
    var creationDate: Date? { fp.criado_ms > 0 ? Date(timeIntervalSince1970: Double(fp.criado_ms) / 1000) : nil }
    var contentModificationDate: Date? { fp.modificado_ms > 0 ? Date(timeIntervalSince1970: Double(fp.modificado_ms) / 1000) : nil }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: Data(String(fp.versao).utf8),
                                  metadataVersion: Data("\(fp.versao_meta)|\(fp.nome)|\(fp.pai ?? "")".utf8))
    }

    var capabilities: NSFileProviderItemCapabilities {
        var c: NSFileProviderItemCapabilities = [.allowsReading]
        if fp.ehPasta {
            c.insert(.allowsContentEnumerating)
            if fp.pode.criar { c.insert(.allowsAddingSubItems) }
        } else {
            // "Remover download" vem do `contentPolicy` (o `allowsEvicting` antigo foi descontinuado).
            if fp.pode.escrever { c.insert(.allowsWriting) }
        }
        if fp.pode.renomear { c.insert(.allowsRenaming) }
        if fp.pode.mover { c.insert(.allowsReparenting) }
        if fp.pode.apagar { c.insert(.allowsDeleting) }
        return c
    }

    /// Arquivo desce só quando é aberto (o padrão do domínio também é este).
    var contentPolicy: NSFileProviderContentPolicy { .downloadLazily }
}

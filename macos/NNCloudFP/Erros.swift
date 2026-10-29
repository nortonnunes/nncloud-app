// Erros da API → o que o macOS entende (ele decide se tenta de novo ou avisa a pessoa).
import FileProvider
import Foundation

func erroDoSistema(_ e: Error) -> Error {
    if let n = e as NSError?, n.domain == NSFileProviderErrorDomain || n.domain == NSCocoaErrorDomain {
        return e
    }
    guard let a = e as? ErroAPI else { return NSFileProviderError(.cannotSynchronize) }
    switch a.status {
    case 401: return NSFileProviderError(.notAuthenticated)
    case 404: return NSFileProviderError(.noSuchItem)
    case 403: return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                             userInfo: [NSLocalizedDescriptionKey: a.mensagem])
    case 507, 413: return NSFileProviderError(.insufficientQuota)
    case 0, 429, 500...: return NSFileProviderError(.serverUnreachable)
    default: return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.cannotSynchronize.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: a.mensagem])
    }
}

func semPermissao(_ msg: String = "Esta pasta não aceita alterações.") -> Error {
    NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// Arquivos do sistema e temporários de editores que não sobem.
func ficaFora(_ nome: String) -> Bool {
    nome == ".DS_Store" || nome.hasPrefix("._") || nome.hasPrefix("~$") || nome.hasPrefix(".~lock.") || nome == "Thumbs.db"
        || nome == "desktop.ini"
}

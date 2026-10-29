// A extensão File Provider do NN Cloud: o "NN Cloud" no Finder, sob demanda.
//
//   abrir um arquivo ........ fetchContents: baixa direto do S3 e confere a impressão
//   criar / colar / salvar .. createItem / modifyItem: envia em partes direto ao S3
//   renomear / mover ........ modifyItem: as rotas de sempre
//   apagar .................. deleteItem: vai para a LIXEIRA do NN Cloud (30 dias)
//   "Remover download" ...... do próprio Finder (o arquivo volta a ser só nuvem)
//
// ⚠️ Edição nos dois lados: o servidor guarda o que subiu como CÓPIA DE CONFLITO e a
// versão da nuvem fica com o nome — aqui devolvemos o item da nuvem pedindo para o
// sistema baixá-lo de novo; a cópia aparece pelas mudanças.
// ⚠️ A extensão roda em sandbox: o token vem do contêiner do grupo (Credenciais), que o
// aplicativo grava ao conectar e apaga ao desconectar.
import FileProvider
import Foundation
import os

final class Extensao: NSObject, NSFileProviderReplicatedExtension {
    let dominio: NSFileProviderDomain
    let log = Logger(subsystem: "br.com.nortonnunes.nncloud.fp", category: "extensao")
    private var clienteCache: (Credenciais, ClienteNNCloud)?

    required init(domain: NSFileProviderDomain) {
        dominio = domain
        super.init()
    }

    func invalidate() {}

    private var manager: NSFileProviderManager? { NSFileProviderManager(for: dominio) }

    /// O cliente com as credenciais atuais (relidas se o aplicativo trocou o token).
    func cliente() throws -> ClienteNNCloud {
        guard let cred = Credenciais.ler(), let base = URL(string: cred.api), !cred.token.isEmpty else {
            throw NSFileProviderError(.notAuthenticated)
        }
        if let (c, cli) = clienteCache, c == cred { return cli }
        let cli = ClienteNNCloud(base: base, token: cred.token)
        clienteCache = (cred, cli)
        return cli
    }

    /// Roda a operação assíncrona e devolve o Progress que o sistema acompanha.
    private func tarefa(_ total: Int64 = 1, _ op: @escaping (Progress) async -> Void) -> Progress {
        let p = Progress(totalUnitCount: total)
        Task { await op(p) }
        return p
    }

    // MARK: - Itens

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        tarefa { _ in
            do {
                completionHandler(Item(try await self.cliente().item(Item.nosso(identifier))), nil)
            } catch {
                completionHandler(nil, erroDoSistema(error))
            }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        tarefa(100) { p in
            do {
                let c = try self.cliente()
                let fp = try await c.item(Item.nosso(itemIdentifier))
                guard let n = fp.numero, !fp.ehPasta else { throw NSFileProviderError(.noSuchItem) }
                p.totalUnitCount = Int64(max(fp.tamanho ?? 1, 1))
                let destino = try self.temporario()
                try await c.baixar(n, impressaoEsperada: fp.impressao, para: destino, progresso: p)
                completionHandler(destino, Item(fp), nil)
            } catch {
                self.log.error("download \(itemIdentifier.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, nil, erroDoSistema(error))
            }
        }
    }

    private func temporario() throws -> URL {
        guard let m = manager else { throw NSFileProviderError(.cannotSynchronize) }
        return try m.temporaryDirectoryURL().appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Criar

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        tarefa(100) { p in
            do {
                let nome = itemTemplate.filename
                if ficaFora(nome) {
                    completionHandler(nil, [], false, NSFileProviderError(.excludedFromSync))
                    return
                }
                let c = try self.cliente()
                let pai = Item.nosso(itemTemplate.parentItemIdentifier)
                guard let destino = Identificador.destino(pai, meuDrive: try await c.meuDrive()) else {
                    throw semPermissao("Crie em Meu Drive, num drive ou dentro de uma pasta.")
                }
                let pasta = itemTemplate.contentType?.conforms(to: .folder) ?? false
                // Reimportação (o sistema já pode ter enviado antes): reaproveita o que é igual.
                if options.contains(.mayAlreadyExist), let ja = try await self.existente(c, pai: pai, nome: nome, pasta: pasta, conteudo: url) {
                    completionHandler(Item(ja), [], false, nil)
                    return
                }
                let id: Int
                if pasta {
                    id = try await c.criarPasta(em: destino, nome: nome)
                } else if itemTemplate.contentType?.conforms(to: .symbolicLink) ?? false {
                    completionHandler(nil, [], false, NSFileProviderError(.excludedFromSync))
                    return
                } else {
                    guard let url else { throw NSFileProviderError(.cannotSynchronize) }
                    id = try await c.enviar(url, nome: nome, destino: destino, mtime: itemTemplate.contentModificationDate ?? nil, progresso: p).itemId
                }
                let novo = try await c.item("i\(id)")
                completionHandler(Item(novo), [], false, nil)
                if !pasta { self.liberarSePedido(novo) }
            } catch {
                self.log.error("criar \(itemTemplate.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, [], false, erroDoSistema(error))
            }
        }
    }

    private func existente(_ c: ClienteNNCloud, pai: String, nome: String, pasta: Bool, conteudo: URL?) async throws -> ItemFP? {
        var pos: Int? = 0
        while let p = pos {
            let r = try await c.filhos(pai, depoisDe: p)
            for i in r.itens where i.nome.compare(nome, options: [.caseInsensitive]) == .orderedSame && i.ehPasta == pasta {
                if pasta { return i }
                if let url = conteudo, let imp = try Impressao.deArquivo(url), imp.hex == i.impressao { return i }
            }
            pos = r.proximo
        }
        return nil
    }

    /// "Liberar após enviar": o arquivo que acabou de subir sai do disco (fica só na nuvem).
    private func liberarSePedido(_ item: ItemFP) {
        guard Credenciais.ler()?.liberarAposEnviar == true, let m = manager else { return }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)   // o sistema termina de registrar o envio
            do {
                try await m.evictItem(identifier: Item.doSistema(item.id))
            } catch {
                self.log.info("liberar \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Alterar

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        tarefa(100) { p in
            do {
                let c = try self.cliente()
                var fp = try await c.item(Item.nosso(item.itemIdentifier))
                guard let n = fp.numero else { throw semPermissao() }
                if changedFields.contains(.contents), let url = newContents, !fp.ehPasta {
                    let base = Int(String(decoding: version.contentVersion, as: UTF8.self)) ?? fp.versao
                    let r = try await c.enviar(url, nome: item.filename, destino: nil, itemId: n, baseVersao: base,
                                               mtime: item.contentModificationDate ?? nil, progresso: p)
                    if r.conflito {
                        // A nuvem mudou antes: o que subiu virou a cópia de conflito, e a versão
                        // da nuvem desce de novo para este item.
                        fp = try await c.item("i\(n)")
                        completionHandler(Item(fp), [], true, nil)
                        try? await self.manager?.signalEnumerator(for: .workingSet)
                        return
                    }
                }
                if changedFields.contains(.filename), item.filename != fp.nome {
                    try await c.renomear(n, para: item.filename)
                }
                if changedFields.contains(.parentItemIdentifier) {
                    let novoPai = Item.nosso(item.parentItemIdentifier)
                    if novoPai != fp.pai {
                        guard let d = Identificador.destino(novoPai, meuDrive: try await c.meuDrive()) else {
                            throw semPermissao("Não dá para mover para cá.")
                        }
                        try await c.mover(n, para: d)
                    }
                }
                fp = try await c.item("i\(n)")
                completionHandler(Item(fp), [], false, nil)
                if changedFields.contains(.contents), !fp.ehPasta { self.liberarSePedido(fp) }
            } catch {
                self.log.error("alterar \(item.itemIdentifier.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, [], false, erroDoSistema(error))
            }
        }
    }

    // MARK: - Apagar

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        tarefa { _ in
            do {
                guard let n = Identificador.numeroDoItem(Item.nosso(identifier)) else { throw semPermissao("Esta pasta não pode ser apagada.") }
                try await self.cliente().lixeira(n)
                completionHandler(nil)
            } catch let e as ErroAPI where e.status == 404 {
                completionHandler(nil)   // já não existe: o que se queria
            } catch {
                completionHandler(erroDoSistema(error))
            }
        }
    }

    // MARK: - Enumeração

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        let fonte: () throws -> ClienteNNCloud = { [weak self] in
            guard let self else { throw NSFileProviderError(.cannotSynchronize) }
            return try self.cliente()
        }
        switch containerItemIdentifier {
        case .workingSet:
            return EnumeradorTrabalho(cliente: fonte)
        case .trashContainer:
            throw NSFileProviderError(.noSuchItem)
        default:
            return EnumeradorPasta(pasta: Item.nosso(containerItemIdentifier), cliente: fonte)
        }
    }
}

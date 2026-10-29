// "NN Cloud" no Explorer — a ponte com a Cloud Files API (ver nuvem_windows.h).
//
// ⚠️ Pedido do PRÓPRIO processo (o app renomeando/apagando a pedido da nuvem, ou
// lendo um arquivo) é respondido aqui na hora, sem passar pelo Dart: o Dart está
// justamente esperando aquela operação terminar, e perguntar a ele travaria tudo.
// No caso de "abrir" vindo do próprio app, a resposta é RECUSAR (o app nunca deve
// ler um placeholder vazio — ver sob_demanda.dart).
// ⚠️ Os bytes de um download são entregues ao Windows em blocos de 4 KB alinhados
// à medida que chegam (cada entrega reinicia o prazo de 60 s do sistema); o último
// bloco só sai depois que o Dart conferiu a impressão — se não conferir, a
// abertura falha em vez de entregar um arquivo errado.
#include "nuvem_windows.h"

#include <winternl.h>  // NTSTATUS
#include <cfapi.h>
#include <sddl.h>

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Provider.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <iterator>
#include <map>
#include <string>
#include <thread>
#include <vector>

#ifndef FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
#define FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS 0x00400000
#endif

namespace {

constexpr NTSTATUS kStatusOk = 0;
constexpr NTSTATUS kStatusFalha = static_cast<NTSTATUS>(0xC0000001L);    // STATUS_UNSUCCESSFUL
constexpr NTSTATUS kStatusNegado = static_cast<NTSTATUS>(0xC0000022L);   // STATUS_ACCESS_DENIED
constexpr int64_t kBloco = 4096;
constexpr int64_t kMaxEntrega = 4 * 1024 * 1024;
constexpr wchar_t kPrefixoId[] = L"NNCloud!";

NuvemWindows* g_nuvem = nullptr;
CF_CONNECTION_KEY g_conexao{};
bool g_conectado = false;

// Um pedido do Windows esperando o Dart.
struct Pedido {
  int tipo = 0;  // 0 = buscar conteúdo, 1 = apagar, 2 = renomear
  CF_CONNECTION_KEY conexao{};
  CF_TRANSFER_KEY transferencia{};
  CF_REQUEST_KEY requisicao{};
  int64_t inicio = 0, tamanho = 0;   // trecho exigido
  int64_t tamanho_arquivo = 0;
  int64_t entregue = 0;              // bytes já entregues a partir do 0
};
std::mutex g_pedidos_mutex;
std::map<int64_t, Pedido> g_pedidos;
std::atomic<int64_t> g_proximo{1};

// ---------------------------------------------------------------- texto

std::wstring ParaW(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

std::string ParaUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  std::string s(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
  return s;
}

std::string Hresult(HRESULT hr) {
  char b[64];
  snprintf(b, sizeof(b), "0x%08lX", static_cast<unsigned long>(hr));
  return b;
}

// ---------------------------------------------------------------- argumentos

const flutter::EncodableValue* Campo(const flutter::EncodableMap& m, const char* k) {
  auto it = m.find(flutter::EncodableValue(std::string(k)));
  return it == m.end() ? nullptr : &it->second;
}

std::string Texto(const flutter::EncodableMap& m, const char* k) {
  auto v = Campo(m, k);
  if (v && std::holds_alternative<std::string>(*v)) return std::get<std::string>(*v);
  return std::string();
}

int64_t Inteiro(const flutter::EncodableMap& m, const char* k, int64_t padrao = 0) {
  auto v = Campo(m, k);
  if (!v) return padrao;
  if (std::holds_alternative<int32_t>(*v)) return std::get<int32_t>(*v);
  if (std::holds_alternative<int64_t>(*v)) return std::get<int64_t>(*v);
  return padrao;
}

bool Logico(const flutter::EncodableMap& m, const char* k, bool padrao = false) {
  auto v = Campo(m, k);
  if (v && std::holds_alternative<bool>(*v)) return std::get<bool>(*v);
  return padrao;
}

flutter::EncodableValue V(const std::string& s) { return flutter::EncodableValue(s); }

// ---------------------------------------------------------------- tempo

LARGE_INTEGER ParaFiletime(int64_t ms) {
  LARGE_INTEGER t;
  t.QuadPart = ms <= 0 ? 0 : ms * 10000 + 116444736000000000LL;
  return t;
}

// ---------------------------------------------------------------- identidade da raiz

std::wstring SidDoUsuario() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return L"S";
  DWORD n = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &n);
  std::vector<BYTE> buf(n);
  std::wstring sid = L"S";
  if (n > 0 && GetTokenInformation(token, TokenUser, buf.data(), n, &n)) {
    LPWSTR s = nullptr;
    if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buf.data())->User.Sid, &s)) {
      sid = s;
      LocalFree(s);
    }
  }
  CloseHandle(token);
  return sid;
}

std::wstring IdDaRaiz(const std::wstring& conta) {
  return std::wstring(kPrefixoId) + SidDoUsuario() + L"!" + (conta.empty() ? L"conta" : conta);
}

std::wstring CaminhoDoExe() {
  wchar_t b[MAX_PATH * 2];
  DWORD n = GetModuleFileNameW(nullptr, b, static_cast<DWORD>(std::size(b)));
  return std::wstring(b, n);
}

// ---------------------------------------------------------------- arquivos

HANDLE Abrir(const std::wstring& caminho, DWORD acesso) {
  return CreateFileW(caminho.c_str(), acesso, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                     OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
}

// ---------------------------------------------------------------- respostas ao Windows

HRESULT EntregarFalha(const Pedido& p) {
  CF_OPERATION_INFO op{};
  op.StructSize = sizeof(op);
  op.Type = CF_OPERATION_TYPE_TRANSFER_DATA;
  op.ConnectionKey = p.conexao;
  op.TransferKey = p.transferencia;
  op.RequestKey = p.requisicao;
  CF_OPERATION_PARAMETERS par{};
  par.ParamSize = CF_SIZE_OF_OP_PARAM(TransferData);
  par.TransferData.CompletionStatus = kStatusFalha;
  par.TransferData.Buffer = nullptr;
  if (p.entregue > 0 && p.entregue < p.tamanho_arquivo) {
    par.TransferData.Offset.QuadPart = p.entregue;
    par.TransferData.Length.QuadPart = p.tamanho_arquivo - p.entregue;
  } else {
    par.TransferData.Offset.QuadPart = p.inicio;
    par.TransferData.Length.QuadPart = p.tamanho;
  }
  return CfExecute(&op, &par);
}

// Entrega os bytes de [arquivo] de p.entregue até [ate] (alinhado a 4 KB; no fim,
// até o fim do arquivo). false = o Windows recusou (abertura cancelada, por exemplo).
bool Entregar(Pedido& p, const std::wstring& arquivo, int64_t ate, bool fim, std::string& erro) {
  int64_t alvo = fim ? p.tamanho_arquivo : (std::min(ate, p.tamanho_arquivo) / kBloco) * kBloco;
  if (alvo <= p.entregue) return true;
  HANDLE h = CreateFileW(arquivo.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    erro = "nao abriu o arquivo baixado";
    return false;
  }
  std::vector<char> buf;
  bool ok = true;
  while (p.entregue < alvo) {
    int64_t n = std::min<int64_t>(kMaxEntrega, alvo - p.entregue);
    buf.resize(static_cast<size_t>(n));
    LARGE_INTEGER pos;
    pos.QuadPart = p.entregue;
    DWORD lidos = 0;
    if (!SetFilePointerEx(h, pos, nullptr, FILE_BEGIN) || !ReadFile(h, buf.data(), static_cast<DWORD>(n), &lidos, nullptr) ||
        static_cast<int64_t>(lidos) != n) {
      erro = "leitura curta do arquivo baixado";
      ok = false;
      break;
    }
    CF_OPERATION_INFO op{};
    op.StructSize = sizeof(op);
    op.Type = CF_OPERATION_TYPE_TRANSFER_DATA;
    op.ConnectionKey = p.conexao;
    op.TransferKey = p.transferencia;
    op.RequestKey = p.requisicao;
    CF_OPERATION_PARAMETERS par{};
    par.ParamSize = CF_SIZE_OF_OP_PARAM(TransferData);
    par.TransferData.CompletionStatus = kStatusOk;
    par.TransferData.Buffer = buf.data();
    par.TransferData.Offset.QuadPart = p.entregue;
    par.TransferData.Length.QuadPart = n;
    HRESULT hr = CfExecute(&op, &par);
    if (FAILED(hr)) {
      erro = "CfExecute " + Hresult(hr);
      ok = false;
      break;
    }
    p.entregue += n;
  }
  CloseHandle(h);
  return ok;
}

HRESULT Confirmar(const Pedido& p, bool ok) {
  CF_OPERATION_INFO op{};
  op.StructSize = sizeof(op);
  op.ConnectionKey = p.conexao;
  op.TransferKey = p.transferencia;
  op.RequestKey = p.requisicao;
  CF_OPERATION_PARAMETERS par{};
  if (p.tipo == 1) {
    op.Type = CF_OPERATION_TYPE_ACK_DELETE;
    par.ParamSize = CF_SIZE_OF_OP_PARAM(AckDelete);
    par.AckDelete.Flags = CF_OPERATION_ACK_DELETE_FLAG_NONE;
    par.AckDelete.CompletionStatus = ok ? kStatusOk : kStatusNegado;
  } else {
    op.Type = CF_OPERATION_TYPE_ACK_RENAME;
    par.ParamSize = CF_SIZE_OF_OP_PARAM(AckRename);
    par.AckRename.Flags = CF_OPERATION_ACK_RENAME_FLAG_NONE;
    par.AckRename.CompletionStatus = ok ? kStatusOk : kStatusNegado;
  }
  return CfExecute(&op, &par);
}

Pedido NovoPedido(int tipo, const CF_CALLBACK_INFO* info) {
  Pedido p;
  p.tipo = tipo;
  p.conexao = info->ConnectionKey;
  p.transferencia = info->TransferKey;
  p.requisicao = info->RequestKey;
  p.tamanho_arquivo = info->FileSize.QuadPart;
  return p;
}

bool DoProprioApp(const CF_CALLBACK_INFO* info) {
  return info->ProcessInfo != nullptr && info->ProcessInfo->ProcessId == GetCurrentProcessId();
}

std::string Identidade(const CF_CALLBACK_INFO* info) {
  if (!info->FileIdentity || info->FileIdentityLength == 0) return std::string();
  return std::string(static_cast<const char*>(info->FileIdentity), info->FileIdentityLength);
}

std::wstring CaminhoCompleto(const CF_CALLBACK_INFO* info, PCWSTR relativo) {
  std::wstring c = info->VolumeDosName ? info->VolumeDosName : L"";
  c += relativo ? relativo : L"";
  return c;
}

int64_t Guardar(Pedido p) {
  int64_t id = g_proximo++;
  std::lock_guard<std::mutex> l(g_pedidos_mutex);
  g_pedidos[id] = p;
  return id;
}

// ---------------------------------------------------------------- callbacks (threads do sistema)

void CALLBACK AoBuscar(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS* par) {
  Pedido p = NovoPedido(0, info);
  p.inicio = par->FetchData.RequiredFileOffset.QuadPart;
  p.tamanho = par->FetchData.RequiredLength.QuadPart;
  if (DoProprioApp(info) || !g_nuvem) {
    EntregarFalha(p);
    return;
  }
  int64_t id = Guardar(p);
  g_nuvem->Avisar("buscar", flutter::EncodableMap{
                                {V("req"), flutter::EncodableValue(id)},
                                {V("identidade"), V(Identidade(info))},
                                {V("caminho"), V(ParaUtf8(CaminhoCompleto(info, info->NormalizedPath)))},
                                {V("tamanho"), flutter::EncodableValue(static_cast<int64_t>(p.tamanho_arquivo))},
                            });
}

void CALLBACK AoCancelar(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS*) {
  // A abertura foi cancelada (programa fechado, por exemplo): o pedido fica até o
  // Dart terminar; a entrega seguinte é recusada pelo Windows e o pedido some.
  if (g_nuvem) g_nuvem->Avisar("cancelar", flutter::EncodableMap{{V("caminho"), V(ParaUtf8(CaminhoCompleto(info, info->NormalizedPath)))}});
}

void CALLBACK AoApagar(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS* par) {
  Pedido p = NovoPedido(1, info);
  if (DoProprioApp(info) || !g_nuvem) {
    Confirmar(p, true);
    return;
  }
  int64_t id = Guardar(p);
  g_nuvem->Avisar("apagar", flutter::EncodableMap{
                                {V("req"), flutter::EncodableValue(id)},
                                {V("identidade"), V(Identidade(info))},
                                {V("caminho"), V(ParaUtf8(CaminhoCompleto(info, info->NormalizedPath)))},
                                {V("pasta"), flutter::EncodableValue((static_cast<unsigned>(par->Delete.Flags) & CF_CALLBACK_DELETE_FLAG_IS_DIRECTORY) != 0)},
                            });
}

void CALLBACK AoRenomear(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS* par) {
  Pedido p = NovoPedido(2, info);
  if (DoProprioApp(info) || !g_nuvem) {
    Confirmar(p, true);
    return;
  }
  bool dentro = (static_cast<unsigned>(par->Rename.Flags) & CF_CALLBACK_RENAME_FLAG_TARGET_IN_SCOPE) != 0;
  int64_t id = Guardar(p);
  g_nuvem->Avisar("renomear", flutter::EncodableMap{
                                  {V("req"), flutter::EncodableValue(id)},
                                  {V("identidade"), V(Identidade(info))},
                                  {V("de"), V(ParaUtf8(CaminhoCompleto(info, info->NormalizedPath)))},
                                  {V("para"), V(ParaUtf8(CaminhoCompleto(info, par->Rename.TargetPath)))},
                                  {V("dentro"), flutter::EncodableValue(dentro)},
                              });
}

// ---------------------------------------------------------------- registro (WinRT, fora da thread da janela)

namespace wsp = winrt::Windows::Storage::Provider;

std::string Registrar(const std::wstring& raiz, const std::wstring& conta) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  try {
    CreateDirectoryW(raiz.c_str(), nullptr);
    wsp::StorageProviderSyncRootInfo info;
    std::wstring id = IdDaRaiz(conta);
    info.Id(id);
    info.Path(winrt::Windows::Storage::StorageFolder::GetFolderFromPathAsync(raiz).get());
    info.DisplayNameResource(L"NN Cloud");
    info.IconResource(CaminhoDoExe() + L",0");
    info.HydrationPolicy(wsp::StorageProviderHydrationPolicy::Full);
    info.HydrationPolicyModifier(wsp::StorageProviderHydrationPolicyModifier::AutoDehydrationAllowed);
    info.PopulationPolicy(wsp::StorageProviderPopulationPolicy::AlwaysFull);
    info.InSyncPolicy(static_cast<wsp::StorageProviderInSyncPolicy>(
        static_cast<uint32_t>(wsp::StorageProviderInSyncPolicy::FileCreationTime) |
        static_cast<uint32_t>(wsp::StorageProviderInSyncPolicy::DirectoryCreationTime)));
    info.HardlinkPolicy(wsp::StorageProviderHardlinkPolicy::None);
    info.ShowSiblingsAsGroup(false);
    info.Version(L"1");
    info.Context(winrt::Windows::Security::Cryptography::CryptographicBuffer::ConvertStringToBinary(
        id, winrt::Windows::Security::Cryptography::BinaryStringEncoding::Utf8));
    wsp::StorageProviderSyncRootManager::Register(info);
    return std::string();
  } catch (const winrt::hresult_error& e) {
    return winrt::to_string(e.message()) + " (" + Hresult(e.code()) + ")";
  } catch (...) {
    return "falha desconhecida ao registrar";
  }
}

std::string Desregistrar() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  try {
    std::wstring prefixo = std::wstring(kPrefixoId) + SidDoUsuario() + L"!";
    for (const auto& r : wsp::StorageProviderSyncRootManager::GetCurrentSyncRoots()) {
      std::wstring id{std::wstring_view(r.Id())};
      if (id.rfind(prefixo, 0) == 0) wsp::StorageProviderSyncRootManager::Unregister(id);
    }
    return std::string();
  } catch (const winrt::hresult_error& e) {
    return winrt::to_string(e.message()) + " (" + Hresult(e.code()) + ")";
  } catch (...) {
    return "falha desconhecida ao desregistrar";
  }
}

// O caminho da raiz registrada deste usuário ("" = não registrado).
std::string RaizRegistrada() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  try {
    std::wstring prefixo = std::wstring(kPrefixoId) + SidDoUsuario() + L"!";
    for (const auto& r : wsp::StorageProviderSyncRootManager::GetCurrentSyncRoots()) {
      std::wstring id{std::wstring_view(r.Id())};
      if (id.rfind(prefixo, 0) == 0) return winrt::to_string(r.Path().Path());
    }
  } catch (...) {
  }
  return std::string();
}

// ---------------------------------------------------------------- conexão

std::string Conectar(const std::wstring& raiz) {
  if (g_conectado) return std::string();
  static const CF_CALLBACK_REGISTRATION tabela[] = {
      {CF_CALLBACK_TYPE_FETCH_DATA, AoBuscar},
      {CF_CALLBACK_TYPE_CANCEL_FETCH_DATA, AoCancelar},
      {CF_CALLBACK_TYPE_NOTIFY_DELETE, AoApagar},
      {CF_CALLBACK_TYPE_NOTIFY_RENAME, AoRenomear},
      CF_CALLBACK_REGISTRATION_END,
  };
  const unsigned conectar = CF_CONNECT_FLAG_REQUIRE_PROCESS_INFO | CF_CONNECT_FLAG_REQUIRE_FULL_FILE_PATH;
  HRESULT hr = CfConnectSyncRoot(raiz.c_str(), tabela, nullptr, static_cast<CF_CONNECT_FLAGS>(conectar), &g_conexao);
  if (FAILED(hr)) return "CfConnectSyncRoot " + Hresult(hr);
  g_conectado = true;
  // A raiz aparece "em dia" no Explorer.
  HANDLE h = Abrir(raiz, FILE_READ_ATTRIBUTES | WRITE_DAC);
  if (h != INVALID_HANDLE_VALUE) {
    CfSetInSyncState(h, CF_IN_SYNC_STATE_IN_SYNC, CF_SET_IN_SYNC_FLAG_NONE, nullptr);
    CloseHandle(h);
  }
  return std::string();
}

void Desconectar() {
  if (!g_conectado) return;
  CfDisconnectSyncRoot(g_conexao);
  g_conectado = false;
  std::lock_guard<std::mutex> l(g_pedidos_mutex);
  g_pedidos.clear();
}

// ---------------------------------------------------------------- placeholders

flutter::EncodableValue Estado(const std::wstring& caminho) {
  DWORD attr = GetFileAttributesW(caminho.c_str());
  if (attr == INVALID_FILE_ATTRIBUTES) return flutter::EncodableValue();
  bool pasta = (attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
  flutter::EncodableMap r{{V("pasta"), flutter::EncodableValue(pasta)}, {V("placeholder"), flutter::EncodableValue(false)},
                          {V("emDia"), flutter::EncodableValue(false)}, {V("hidratado"), flutter::EncodableValue(true)}};
  HANDLE h = Abrir(caminho, FILE_READ_ATTRIBUTES);
  if (h == INVALID_HANDLE_VALUE) return flutter::EncodableValue(r);
  std::vector<BYTE> buf(sizeof(CF_PLACEHOLDER_STANDARD_INFO) + 4096);
  DWORD n = 0;
  HRESULT hr = CfGetPlaceholderInfo(h, CF_PLACEHOLDER_INFO_STANDARD, buf.data(), static_cast<DWORD>(buf.size()), &n);
  CloseHandle(h);
  if (FAILED(hr)) return flutter::EncodableValue(r);   // não é placeholder
  auto* info = reinterpret_cast<CF_PLACEHOLDER_STANDARD_INFO*>(buf.data());
  r[V("placeholder")] = flutter::EncodableValue(true);
  r[V("emDia")] = flutter::EncodableValue(info->InSyncState == CF_IN_SYNC_STATE_IN_SYNC);
  r[V("hidratado")] = flutter::EncodableValue(pasta || (attr & (FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | FILE_ATTRIBUTE_OFFLINE)) == 0);
  r[V("identidade")] = V(std::string(reinterpret_cast<const char*>(info->FileIdentity), info->FileIdentityLength));
  return flutter::EncodableValue(r);
}

flutter::EncodableValue CriarPlaceholders(const std::wstring& pasta, const flutter::EncodableList& itens) {
  std::vector<std::wstring> nomes;
  std::vector<std::string> ids;
  nomes.reserve(itens.size());
  ids.reserve(itens.size());
  std::vector<CF_PLACEHOLDER_CREATE_INFO> infos;
  for (const auto& v : itens) {
    if (!std::holds_alternative<flutter::EncodableMap>(v)) continue;
    const auto& m = std::get<flutter::EncodableMap>(v);
    nomes.push_back(ParaW(Texto(m, "nome")));
    ids.push_back(Texto(m, "identidade"));
  }
  size_t k = 0;
  for (const auto& v : itens) {
    if (!std::holds_alternative<flutter::EncodableMap>(v)) continue;
    const auto& m = std::get<flutter::EncodableMap>(v);
    bool ehPasta = Logico(m, "pasta");
    CF_PLACEHOLDER_CREATE_INFO c{};
    c.RelativeFileName = nomes[k].c_str();
    c.FileIdentity = ids[k].data();
    c.FileIdentityLength = static_cast<DWORD>(ids[k].size());
    c.FsMetadata.FileSize.QuadPart = ehPasta ? 0 : Inteiro(m, "tamanho");
    c.FsMetadata.BasicInfo.CreationTime = ParaFiletime(Inteiro(m, "criado"));
    c.FsMetadata.BasicInfo.LastWriteTime = ParaFiletime(Inteiro(m, "modificado"));
    c.FsMetadata.BasicInfo.LastAccessTime = c.FsMetadata.BasicInfo.LastWriteTime;
    c.FsMetadata.BasicInfo.ChangeTime = c.FsMetadata.BasicInfo.LastWriteTime;
    c.FsMetadata.BasicInfo.FileAttributes = ehPasta ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    unsigned flags = CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;
    if (ehPasta) flags |= CF_PLACEHOLDER_CREATE_FLAG_DISABLE_ON_DEMAND_POPULATION;
    c.Flags = static_cast<CF_PLACEHOLDER_CREATE_FLAGS>(flags);
    infos.push_back(c);
    k++;
  }
  flutter::EncodableList res;
  if (infos.empty()) return flutter::EncodableValue(res);
  DWORD feitos = 0;
  CfCreatePlaceholders(pasta.c_str(), infos.data(), static_cast<DWORD>(infos.size()), CF_CREATE_FLAG_NONE, &feitos);
  for (const auto& c : infos) {
    // Já existia = tudo bem (alguém criou antes, ou o nome está ocupado — o Dart decide).
    res.push_back(flutter::EncodableValue(SUCCEEDED(c.Result) || c.Result == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)));
  }
  return flutter::EncodableValue(res);
}

std::string Atualizar(const std::wstring& caminho, const flutter::EncodableMap& m) {
  HANDLE h = Abrir(caminho, FILE_READ_ATTRIBUTES | WRITE_DAC);
  if (h == INVALID_HANDLE_VALUE) return "abrir " + Hresult(HRESULT_FROM_WIN32(GetLastError()));
  std::string id = Texto(m, "identidade");
  CF_FS_METADATA meta{};
  bool comMeta = Campo(m, "tamanho") != nullptr;
  if (comMeta) {
    meta.FileSize.QuadPart = Inteiro(m, "tamanho");
    meta.BasicInfo.CreationTime = ParaFiletime(Inteiro(m, "criado"));
    meta.BasicInfo.LastWriteTime = ParaFiletime(Inteiro(m, "modificado"));
    meta.BasicInfo.ChangeTime = meta.BasicInfo.LastWriteTime;
  }
  unsigned flags = CF_UPDATE_FLAG_MARK_IN_SYNC;
  if (Logico(m, "desidratar")) flags |= CF_UPDATE_FLAG_DEHYDRATE;
  HRESULT hr = CfUpdatePlaceholder(h, comMeta ? &meta : nullptr, id.empty() ? nullptr : id.data(), static_cast<DWORD>(id.size()),
                                   nullptr, 0, static_cast<CF_UPDATE_FLAGS>(flags), nullptr, nullptr);
  CloseHandle(h);
  return FAILED(hr) ? "CfUpdatePlaceholder " + Hresult(hr) : std::string();
}

std::string Converter(const std::wstring& caminho, const std::string& id, bool desidratar) {
  DWORD attr = GetFileAttributesW(caminho.c_str());
  bool pasta = attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
  HANDLE h = Abrir(caminho, FILE_READ_ATTRIBUTES | WRITE_DAC);
  if (h == INVALID_HANDLE_VALUE) return "abrir " + Hresult(HRESULT_FROM_WIN32(GetLastError()));
  unsigned flags = CF_CONVERT_FLAG_MARK_IN_SYNC;
  if (desidratar && !pasta) flags |= CF_CONVERT_FLAG_DEHYDRATE;
#ifdef CF_CONVERT_FLAG_ALWAYS_FULL
  if (pasta) flags |= CF_CONVERT_FLAG_ALWAYS_FULL;
#endif
  HRESULT hr = CfConvertToPlaceholder(h, id.data(), static_cast<DWORD>(id.size()), static_cast<CF_CONVERT_FLAGS>(flags), nullptr, nullptr);
  CloseHandle(h);
  return FAILED(hr) ? "CfConvertToPlaceholder " + Hresult(hr) : std::string();
}

std::string Desidratar(const std::wstring& caminho) {
  HANDLE h = Abrir(caminho, FILE_READ_ATTRIBUTES | WRITE_DAC);
  if (h == INVALID_HANDLE_VALUE) return "abrir " + Hresult(HRESULT_FROM_WIN32(GetLastError()));
  LARGE_INTEGER ini, tam;
  ini.QuadPart = 0;
  tam.QuadPart = -1;
  HRESULT hr = CfDehydratePlaceholder(h, ini, tam, CF_DEHYDRATE_FLAG_NONE, nullptr);
  CloseHandle(h);
  return FAILED(hr) ? "CfDehydratePlaceholder " + Hresult(hr) : std::string();
}

std::string Reverter(const std::wstring& caminho) {
  HANDLE h = Abrir(caminho, FILE_READ_ATTRIBUTES | WRITE_DAC);
  if (h == INVALID_HANDLE_VALUE) return "abrir " + Hresult(HRESULT_FROM_WIN32(GetLastError()));
  HRESULT hr = CfRevertPlaceholder(h, CF_REVERT_FLAG_NONE, nullptr);
  CloseHandle(h);
  return FAILED(hr) ? "CfRevertPlaceholder " + Hresult(hr) : std::string();
}

}  // namespace

// =================================================================== classe

NuvemWindows::NuvemWindows(flutter::BinaryMessenger* mensageiro, HWND janela) : janela_(janela) {
  g_nuvem = this;
  canal_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      mensageiro, "nncloud/fp", &flutter::StandardMethodCodec::GetInstance());
  canal_->SetMethodCallHandler([this](const auto& chamada, auto resposta) { Tratar(chamada, std::move(resposta)); });
}

NuvemWindows::~NuvemWindows() {
  Desconectar();
  g_nuvem = nullptr;
  if (canal_) canal_->SetMethodCallHandler(nullptr);
}

void NuvemWindows::NaJanela(std::function<void()> tarefa) {
  {
    std::lock_guard<std::mutex> l(fila_mutex_);
    fila_.push_back(std::move(tarefa));
  }
  PostMessage(janela_, kMensagemNuvem, 0, 0);
}

void NuvemWindows::Avisar(const std::string& metodo, flutter::EncodableMap args) {
  NaJanela([this, metodo, args]() {
    if (canal_) canal_->InvokeMethod(metodo, std::make_unique<flutter::EncodableValue>(args));
  });
}

void NuvemWindows::Drenar() {
  std::deque<std::function<void()>> tarefas;
  {
    std::lock_guard<std::mutex> l(fila_mutex_);
    tarefas.swap(fila_);
  }
  for (auto& t : tarefas) t();
}

void NuvemWindows::Tratar(const flutter::MethodCall<flutter::EncodableValue>& chamada,
                          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> resposta) {
  const std::string& m = chamada.method_name();
  static const flutter::EncodableMap vazio;
  const flutter::EncodableMap& a = (chamada.arguments() && std::holds_alternative<flutter::EncodableMap>(*chamada.arguments()))
                                       ? std::get<flutter::EncodableMap>(*chamada.arguments())
                                       : vazio;
  auto erroOuOk = [&resposta](const std::string& e) {
    if (e.empty()) {
      resposta->Success(flutter::EncodableValue(true));
    } else {
      resposta->Error("nuvem", e);
    }
  };

  if (m == "suportado") {
    resposta->Success(flutter::EncodableValue(true));
  } else if (m == "registrado" || m == "registrar" || m == "desregistrar") {
    // WinRT síncrono não pode rodar na thread da janela (STA): vai para outra thread
    // e a resposta volta pela fila.
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> r(resposta.release());
    std::wstring raiz = ParaW(Texto(a, "raiz")), conta = ParaW(Texto(a, "conta"));
    std::thread([this, m, r, raiz, conta]() {
      if (m == "registrado") {
        std::string p = RaizRegistrada();
        NaJanela([r, p]() { r->Success(p.empty() ? flutter::EncodableValue() : flutter::EncodableValue(p)); });
      } else {
        std::string e = m == "registrar" ? Registrar(raiz, conta) : Desregistrar();
        NaJanela([r, e]() {
          if (e.empty()) {
            r->Success(flutter::EncodableValue(true));
          } else {
            r->Error("nuvem", e);
          }
        });
      }
    }).detach();
  } else if (m == "conectar") {
    erroOuOk(Conectar(ParaW(Texto(a, "raiz"))));
  } else if (m == "desconectar") {
    Desconectar();
    resposta->Success(flutter::EncodableValue(true));
  } else if (m == "criarPlaceholders") {
    auto itens = Campo(a, "itens");
    flutter::EncodableList vaziaL;
    resposta->Success(CriarPlaceholders(ParaW(Texto(a, "pasta")),
                                        itens && std::holds_alternative<flutter::EncodableList>(*itens)
                                            ? std::get<flutter::EncodableList>(*itens)
                                            : vaziaL));
  } else if (m == "estado") {
    resposta->Success(Estado(ParaW(Texto(a, "caminho"))));
  } else if (m == "atualizar") {
    erroOuOk(Atualizar(ParaW(Texto(a, "caminho")), a));
  } else if (m == "converter") {
    erroOuOk(Converter(ParaW(Texto(a, "caminho")), Texto(a, "identidade"), Logico(a, "desidratar")));
  } else if (m == "desidratar") {
    erroOuOk(Desidratar(ParaW(Texto(a, "caminho"))));
  } else if (m == "reverter") {
    erroOuOk(Reverter(ParaW(Texto(a, "caminho"))));
  } else if (m == "transferir" || m == "falhar" || m == "responder" || m == "progresso") {
    int64_t req = Inteiro(a, "req");
    Pedido p;
    {
      std::lock_guard<std::mutex> l(g_pedidos_mutex);
      auto it = g_pedidos.find(req);
      if (it == g_pedidos.end()) {
        resposta->Success(flutter::EncodableValue(false));   // já respondido ou desconectado
        return;
      }
      p = it->second;
    }
    bool terminou = true, ok = true;
    std::string erro;
    if (m == "transferir") {
      bool fim = Logico(a, "fim");
      ok = Entregar(p, ParaW(Texto(a, "arquivo")), Inteiro(a, "ate"), fim, erro);
      terminou = fim || !ok;
      if (!ok) EntregarFalha(p);
    } else if (m == "falhar") {
      EntregarFalha(p);
    } else if (m == "responder") {
      ok = SUCCEEDED(Confirmar(p, Logico(a, "ok")));
    } else {
      LARGE_INTEGER total, feito;
      total.QuadPart = Inteiro(a, "total");
      feito.QuadPart = Inteiro(a, "feito");
      CfReportProviderProgress(p.conexao, p.transferencia, total, feito);
      terminou = false;
    }
    {
      std::lock_guard<std::mutex> l(g_pedidos_mutex);
      if (terminou) {
        g_pedidos.erase(req);
      } else {
        g_pedidos[req] = p;   // guarda quanto já foi entregue
      }
    }
    if (ok) {
      resposta->Success(flutter::EncodableValue(true));
    } else {
      resposta->Error("nuvem", erro.empty() ? "o Windows recusou" : erro);
    }
  } else {
    resposta->NotImplemented();
  }
}

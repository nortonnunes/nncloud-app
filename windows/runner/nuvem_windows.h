// "NN Cloud" no Explorer (arquivos sob demanda): a ponte com a Cloud Files API.
//
// Quem decide tudo é o Dart (motor/lib/src/sob_demanda.dart). Aqui ficam só as
// chamadas do sistema: registrar a raiz de sincronização, criar e atualizar
// placeholders, entregar os bytes quando o Windows pede um arquivo e responder
// quando ele pergunta se pode apagar/renomear. Canal "nncloud/fp".
//
// ⚠️ Os pedidos do Windows chegam em threads do SISTEMA; o canal do Flutter só
// pode ser usado na thread da janela. Por isso tudo passa por uma fila + PostMessage.
#ifndef RUNNER_NUVEM_WINDOWS_H_
#define RUNNER_NUVEM_WINDOWS_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <deque>
#include <functional>
#include <memory>
#include <mutex>

// Mensagem da janela que drena a fila (WM_APP + "N").
constexpr UINT kMensagemNuvem = WM_APP + 0x4E;

class NuvemWindows {
 public:
  NuvemWindows(flutter::BinaryMessenger* mensageiro, HWND janela);
  ~NuvemWindows();

  // Chamado pela janela ao receber kMensagemNuvem (thread da janela).
  void Drenar();

  // Põe uma tarefa na fila da thread da janela (pode ser chamado de qualquer thread).
  void NaJanela(std::function<void()> tarefa);

  // Manda um evento ao Dart (pode ser chamado de qualquer thread).
  void Avisar(const std::string& metodo, flutter::EncodableMap args);

 private:
  void Tratar(const flutter::MethodCall<flutter::EncodableValue>& chamada,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> resposta);

  HWND janela_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> canal_;
  std::mutex fila_mutex_;
  std::deque<std::function<void()>> fila_;
};

#endif  // RUNNER_NUVEM_WINDOWS_H_

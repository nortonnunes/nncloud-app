import 'package:flutter/material.dart';

/// Configuração do aplicativo NN Cloud (as mesmas cores do app NN Conecta).
class AppConfig {
  static const String nome = 'NN Cloud';
  static const String versao = '1.0.0';

  /// API do NN Conecta (pode ser trocada em Configurações → Avançado).
  static const String apiPadrao = 'https://api.nortonnunes.com.br';

  /// Modo claro: o azul da logo e o degradê azul → verde do sistema web.
  static const Color azulLogo = Color(0xFF1652D0);
  static const Color degradeInicio = Color(0xFF2A50C8);
  static const Color degradeFim = Color(0xFF4DAE5B);

  /// Modo escuro: o vinho do app NN Conecta.
  static const Color vinho = Color(0xFF993635);

  /// Dias que um arquivo apagado na nuvem fica na lixeira local do app.
  static const int diasLixeiraLocal = 30;
}

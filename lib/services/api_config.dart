import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Endereço da API REST usado pelo app (produtos, carrinho, notificações).
///
/// - Padrão: o definido na compilação (`--dart-define=API_URL=...`) ou, sem
///   isso, `localhost:8080` (navegador) / `10.0.2.2:8080` (emulador Android).
/// - O usuário pode trocar dentro do app; o valor fica salvo no aparelho.
///   Assim, se o IP do PC mudar (ex.: na faculdade), não precisa recompilar.
class ApiConfig {
  static const _chave = 'api_url';

  /// Endereço atual (ex.: http://192.168.0.10:8080). Avisa quem escuta ao mudar.
  static final ValueNotifier<String> endereco = ValueNotifier<String>(enderecoPadrao());

  static String get url => endereco.value;

  /// true quando o usuário salvou um endereço diferente do padrão.
  static bool get personalizado => endereco.value != enderecoPadrao();

  /// Endereço definido na compilação ou o padrão da plataforma.
  static String enderecoPadrao() {
    const daCompilacao = String.fromEnvironment('API_URL');
    if (daCompilacao.isNotEmpty) return normalizar(daCompilacao) ?? daCompilacao;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  /// Carrega o endereço salvo (chamar no início do app).
  static Future<void> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvo = prefs.getString(_chave);
      if (salvo != null && salvo.isNotEmpty) endereco.value = salvo;
    } catch (_) {
      // Sem armazenamento disponível: segue com o padrão.
    }
  }

  /// Salva um novo endereço. Retorna o endereço normalizado.
  static Future<String> salvar(String texto) async {
    final normalizado = normalizar(texto);
    if (normalizado == null) {
      throw const FormatException('Endereço inválido. Exemplo: 192.168.0.10:8080');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, normalizado);
    endereco.value = normalizado;
    return normalizado;
  }

  /// Volta para o endereço padrão (o da compilação).
  static Future<void> restaurarPadrao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
    endereco.value = enderecoPadrao();
  }

  /// Aceita "192.168.0.10", "192.168.0.10:8080", "http://192.168.0.10:8080/",
  /// ".../produtos" etc. e devolve "http://192.168.0.10:8080".
  /// Sem porta informada, usa 8080 (para http) — a porta padrão da API.
  static String? normalizar(String texto) {
    var t = texto.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) t = 'http://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final temPorta = RegExp(r'^[a-z]+://[^/]+:\d+', caseSensitive: false).hasMatch(t);
    final porta = temPorta ? uri.port : (uri.scheme == 'http' ? 8080 : 443);

    var caminho = uri.path;
    while (caminho.endsWith('/')) {
      caminho = caminho.substring(0, caminho.length - 1);
    }
    if (caminho.endsWith('/produtos')) {
      caminho = caminho.substring(0, caminho.length - '/produtos'.length);
    }

    final padraoDoEsquema =
        (uri.scheme == 'http' && porta == 80) || (uri.scheme == 'https' && porta == 443);
    final hostPorta = padraoDoEsquema ? uri.host : '${uri.host}:$porta';
    return '${uri.scheme}://$hostPorta$caminho';
  }
}

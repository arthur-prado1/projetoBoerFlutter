import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/produto_model.dart';
import 'api_config.dart';

/// Tipo de alteração avisada pela API em tempo real.
enum TipoEventoProduto { criado, atualizado, excluido }

/// Alteração recebida pelo WebSocket da API.
class EventoProduto {
  final TipoEventoProduto tipo;
  final ProdutoModel produto;

  EventoProduto(this.tipo, this.produto);

  /// Lê a mensagem {"evento": "...", "produto": {...}}.
  /// Retorna null se a mensagem não for reconhecida.
  static EventoProduto? fromJson(String mensagem) {
    try {
      final data = jsonDecode(mensagem);
      if (data is! Map<String, dynamic>) return null;
      final tipo = TipoEventoProduto.values
          .where((t) => t.name == data['evento'])
          .firstOrNull;
      final produto = data['produto'];
      if (tipo == null || produto is! Map<String, dynamic>) return null;
      return EventoProduto(tipo, ProdutoModel.fromMap(produto));
    } catch (_) {
      return null;
    }
  }
}

/// Erro amigável retornado pela API REST de Produtos.
class ProdutoApiException implements Exception {
  final String mensagem;
  final int? statusCode;

  ProdutoApiException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

/// Cliente da API REST de Produtos (bin/server.dart).
///
/// Usa o pacote `http`, que funciona no Flutter Web, Android, iOS e desktop.
/// O endereço da API vem de [ApiConfig] (configurável dentro do app) e é
/// lido a cada chamada, então trocar o endereço vale na hora.
class ProdutoService {
  static const Duration _timeout = Duration(seconds: 8);

  final String? _baseUrlFixo;
  final http.Client _client;

  /// [baseUrl] fixo é usado nos testes; sem ele, segue o [ApiConfig].
  ProdutoService({String? baseUrl, http.Client? client})
      : _baseUrlFixo = baseUrl,
        _client = client ?? http.Client();

  /// Ex.: http://192.168.0.10:8080/produtos
  String get baseUrl => _baseUrlFixo ?? '${ApiConfig.url}/produtos';

  /// Endereço atual da API (ex.: http://192.168.0.10:8080).
  static String defaultApiUrl() => ApiConfig.url;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Listar (Read) - GET /produtos
  Future<List<ProdutoModel>> getProdutos() async {
    final response = await _send(() => _client.get(Uri.parse(baseUrl)));
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(response.bodyBytes));
      return list
          .map((item) => ProdutoModel.fromMap(item as Map<String, dynamic>))
          .toList();
    }
    throw _erro(response, 'Falha ao carregar produtos');
  }

  // Buscar por ID (Read) - GET /produtos/{id}
  Future<ProdutoModel> getProdutoById(String id) async {
    final response =
        await _send(() => _client.get(Uri.parse('$baseUrl/$id')));
    if (response.statusCode == 200) {
      return ProdutoModel.fromMap(_decodeMap(response));
    }
    throw _erro(response, 'Produto não encontrado');
  }

  // Cadastrar (Create) - POST /produtos
  Future<ProdutoModel> createProduto(ProdutoModel produto) async {
    final response = await _send(() => _client.post(
          Uri.parse(baseUrl),
          headers: _jsonHeaders,
          body: jsonEncode(_corpo(produto)),
        ));
    if (response.statusCode == 201) {
      return ProdutoModel.fromMap(_decodeMap(response));
    }
    throw _erro(response, 'Falha ao cadastrar produto');
  }

  // Atualizar (Update) - PUT /produtos/{id}
  Future<ProdutoModel> updateProduto(ProdutoModel produto) async {
    if (produto.id == null) {
      throw ProdutoApiException('ID do produto obrigatório para atualização');
    }
    final response = await _send(() => _client.put(
          Uri.parse('$baseUrl/${produto.id}'),
          headers: _jsonHeaders,
          body: jsonEncode(_corpo(produto)),
        ));
    if (response.statusCode == 200) {
      return ProdutoModel.fromMap(_decodeMap(response));
    }
    throw _erro(response, 'Falha ao atualizar produto');
  }

  // Excluir (Delete) - DELETE /produtos/{id}
  Future<void> deleteProduto(String id) async {
    final response =
        await _send(() => _client.delete(Uri.parse('$baseUrl/$id')));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw _erro(response, 'Falha ao excluir produto');
    }
  }

  /// Endereço do WebSocket da API, derivado da URL REST.
  /// Ex.: http://localhost:8080/produtos -> ws://localhost:8080/ws
  Uri get wsUri {
    final uri = Uri.parse(baseUrl);
    final segmentos = [...uri.pathSegments];
    if (segmentos.isNotEmpty) segmentos.removeLast();
    segmentos.add('ws');
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      pathSegments: segmentos,
    );
  }

  /// Abre o canal de tempo real com a API.
  /// Aguarde `canal.ready` para saber se conectou.
  WebSocketChannel conectarTempoReal() => WebSocketChannel.connect(wsUri);

  // O ID vai na URL; o corpo leva só os campos editáveis.
  Map<String, dynamic> _corpo(ProdutoModel produto) {
    return produto.toMap()..remove('id');
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw ProdutoApiException(
        'A API não respondeu a tempo ($baseUrl). Verifique se o servidor está rodando.',
      );
    } on http.ClientException {
      throw ProdutoApiException(
        'Não foi possível conectar à API ($baseUrl). '
        'Rode "dart run bin/server.dart" e tente novamente.',
      );
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  ProdutoApiException _erro(http.Response response, String padrao) {
    String mensagem = padrao;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['erro'] != null) {
        mensagem = '$padrao: ${body['erro']}';
      }
    } catch (_) {
      // Corpo não é JSON; mantém a mensagem padrão.
    }
    return ProdutoApiException(mensagem, statusCode: response.statusCode);
  }
}

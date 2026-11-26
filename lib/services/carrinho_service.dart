import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/carrinho_model.dart';
import 'produto_service.dart' show ProdutoService, ProdutoApiException;

/// Cliente das rotas de carrinho da API REST (bin/server.dart).
class CarrinhoService {
  static const Duration _timeout = Duration(seconds: 15);

  final String? _apiUrlFixo;
  final http.Client _client;

  /// [apiUrl] fixo é usado nos testes; sem ele, segue o endereço configurado.
  CarrinhoService({String? apiUrl, http.Client? client})
      : _apiUrlFixo = apiUrl,
        _client = client ?? http.Client();

  /// Ex.: http://192.168.0.10:8080 (lido a cada chamada).
  String get apiUrl => _apiUrlFixo ?? ProdutoService.defaultApiUrl();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Uri _uri(String uid, [String sufixo = '']) =>
      Uri.parse('$apiUrl/carrinhos/${Uri.encodeComponent(uid)}$sufixo');

  // GET /carrinhos/{uid}
  Future<CarrinhoModel> obter(String uid) async =>
      _carrinho(await _send(() => _client.get(_uri(uid))), 'Falha ao carregar o carrinho');

  // POST /carrinhos/{uid}/itens
  Future<CarrinhoModel> adicionar(String uid, String produtoId, {int quantidade = 1}) async =>
      _carrinho(
        await _send(() => _client.post(
              _uri(uid, '/itens'),
              headers: _jsonHeaders,
              body: jsonEncode({'produtoId': produtoId, 'quantidade': quantidade}),
            )),
        'Não foi possível adicionar ao carrinho',
      );

  // PUT /carrinhos/{uid}/itens/{produtoId}
  Future<CarrinhoModel> definirQuantidade(String uid, String produtoId, int quantidade) async =>
      _carrinho(
        await _send(() => _client.put(
              _uri(uid, '/itens/${Uri.encodeComponent(produtoId)}'),
              headers: _jsonHeaders,
              body: jsonEncode({'quantidade': quantidade}),
            )),
        'Não foi possível alterar a quantidade',
      );

  // DELETE /carrinhos/{uid}/itens/{produtoId}
  Future<CarrinhoModel> remover(String uid, String produtoId) async => _carrinho(
        await _send(() =>
            _client.delete(_uri(uid, '/itens/${Uri.encodeComponent(produtoId)}'))),
        'Não foi possível remover o item',
      );

  // DELETE /carrinhos/{uid}
  Future<CarrinhoModel> esvaziar(String uid) async => _carrinho(
        await _send(() => _client.delete(_uri(uid))),
        'Não foi possível esvaziar o carrinho',
      );

  // POST /carrinhos/{uid}/finalizar
  Future<PedidoModel> finalizar(String uid) async {
    final response = await _send(() => _client.post(_uri(uid, '/finalizar')));
    if (response.statusCode == 201) {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return PedidoModel.fromMap(
        body['pedido'] as Map<String, dynamic>,
        notificacao: body['notificacao'] as Map<String, dynamic>?,
      );
    }
    throw _erro(response, 'Não foi possível finalizar a compra');
  }

  CarrinhoModel _carrinho(http.Response response, String padrao) {
    if (response.statusCode == 200) {
      return CarrinhoModel.fromMap(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
    }
    throw _erro(response, padrao);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw ProdutoApiException('A API não respondeu a tempo ($apiUrl).');
    } on http.ClientException {
      throw ProdutoApiException(
        'Não foi possível conectar à API ($apiUrl). '
        'Rode "dart run bin/server.dart" e tente novamente.',
      );
    }
  }

  /// Usa a mensagem de erro da API (ex.: "Estoque insuficiente ...").
  ProdutoApiException _erro(http.Response response, String padrao) {
    String mensagem = padrao;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['erro'] != null) mensagem = body['erro'].toString();
    } catch (_) {}
    return ProdutoApiException(mensagem, statusCode: response.statusCode);
  }
}

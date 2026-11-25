import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/notificacao_model.dart';
import 'produto_service.dart' show ProdutoService, ProdutoApiException;

/// Lista de notificações + quantas não foram lidas.
class ListaNotificacoes {
  final List<NotificacaoModel> itens;
  final int naoLidas;
  const ListaNotificacoes({this.itens = const [], this.naoLidas = 0});

  factory ListaNotificacoes.fromMap(Map<String, dynamic> map) => ListaNotificacoes(
        itens: (map['notificacoes'] as List? ?? const [])
            .map((e) => NotificacaoModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        naoLidas: (map['naoLidas'] as num?)?.toInt() ?? 0,
      );
}

/// Cliente das rotas de notificações da API REST.
class NotificacaoService {
  static const Duration _timeout = Duration(seconds: 15);

  final String apiUrl;
  final http.Client _client;

  NotificacaoService({String? apiUrl, http.Client? client})
      : apiUrl = apiUrl ?? ProdutoService.defaultApiUrl(),
        _client = client ?? http.Client();

  Uri _uri(String uid, [String sufixo = '']) =>
      Uri.parse('$apiUrl/notificacoes/${Uri.encodeComponent(uid)}$sufixo');

  // GET /notificacoes/{uid}
  Future<ListaNotificacoes> listar(String uid) =>
      _lista(() => _client.get(_uri(uid)));

  // PUT /notificacoes/{uid}/{id}/lida
  Future<ListaNotificacoes> marcarLida(String uid, String id) =>
      _lista(() => _client.put(_uri(uid, '/${Uri.encodeComponent(id)}/lida')));

  // PUT /notificacoes/{uid}/lidas
  Future<ListaNotificacoes> marcarTodasLidas(String uid) =>
      _lista(() => _client.put(_uri(uid, '/lidas')));

  /// Canal de tempo real só deste usuário: ws://.../ws?uid=...
  Uri wsUri(String uid) {
    final base = ProdutoService(baseUrl: '$apiUrl/produtos').wsUri;
    return base.replace(queryParameters: {'uid': uid});
  }

  WebSocketChannel conectarTempoReal(String uid) => WebSocketChannel.connect(wsUri(uid));

  Future<ListaNotificacoes> _lista(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw ProdutoApiException('A API não respondeu a tempo ($apiUrl).');
    } on http.ClientException {
      throw ProdutoApiException('Não foi possível conectar à API ($apiUrl).');
    }
    final texto = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      return ListaNotificacoes.fromMap(jsonDecode(texto) as Map<String, dynamic>);
    }
    String mensagem = 'Falha ao carregar notificações';
    try {
      final body = jsonDecode(texto);
      if (body is Map && body['erro'] != null) mensagem = body['erro'].toString();
    } catch (_) {}
    throw ProdutoApiException(mensagem, statusCode: response.statusCode);
  }
}

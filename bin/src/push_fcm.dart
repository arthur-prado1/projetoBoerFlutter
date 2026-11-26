import 'dart:convert';

import 'package:http/http.dart' as http;

import 'carrinho_repository.dart'
    show baseDocumentosFirestore, camposParaMapa, decodificarFirestore, mapaParaCampos;
import 'notificacao_repository.dart';

/// Escopo OAuth necessário para enviar push pelo FCM (HTTP v1).
const escopoFcm = 'https://www.googleapis.com/auth/firebase.messaging';

/// Canal de notificação do Android usado pelos pushes de pedido.
const canalPedidos = 'pedidos';

// ---------------------------------------------------------------------------
// Tokens dos celulares de cada usuário
// ---------------------------------------------------------------------------

/// Onde a API guarda os tokens FCM dos aparelhos (um usuário pode ter vários).
abstract class DispositivoRepository {
  Future<void> registrar(String uid, String token, {String plataforma = 'android'});
  Future<void> remover(String uid, String token);
  Future<List<String>> tokens(String uid);
}

class MemoriaDispositivoRepository implements DispositivoRepository {
  final Map<String, Set<String>> _porUsuario = {};

  @override
  Future<void> registrar(String uid, String token, {String plataforma = 'android'}) async {
    _porUsuario.putIfAbsent(uid, () => {}).add(token);
  }

  @override
  Future<void> remover(String uid, String token) async {
    _porUsuario[uid]?.remove(token);
  }

  @override
  Future<List<String>> tokens(String uid) async => [...?_porUsuario[uid]];
}

/// Firestore: dispositivos/{uid}/tokens/{token}
class FirestoreDispositivoRepository implements DispositivoRepository {
  final String projectId;
  final http.Client _client;

  FirestoreDispositivoRepository({required this.projectId, required http.Client client})
      : _client = client;

  String _colecao(String uid) =>
      '${baseDocumentosFirestore(projectId)}/dispositivos/${Uri.encodeComponent(uid)}/tokens';

  @override
  Future<void> registrar(String uid, String token, {String plataforma = 'android'}) async {
    // O token é o ID do documento: registrar de novo só atualiza a data.
    final response = await _client.patch(
      Uri.parse('${_colecao(uid)}/${Uri.encodeComponent(token)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': mapaParaCampos({
          'token': token,
          'plataforma': plataforma,
          'atualizadoEm': DateTime.now(),
        }),
      }),
    );
    decodificarFirestore(response, 'registrar dispositivo');
  }

  @override
  Future<void> remover(String uid, String token) async {
    final response = await _client
        .delete(Uri.parse('${_colecao(uid)}/${Uri.encodeComponent(token)}'));
    if (response.statusCode != 404) decodificarFirestore(response, 'remover dispositivo');
  }

  @override
  Future<List<String>> tokens(String uid) async {
    final uri = Uri.parse(_colecao(uid)).replace(queryParameters: {'pageSize': '50'});
    final body = decodificarFirestore(await _client.get(uri), 'listar dispositivos');
    return [
      for (final d in (body['documents'] as List? ?? const []))
        (camposParaMapa((d as Map<String, dynamic>)['fields'] as Map<String, dynamic>?)['token']
                ?.toString() ??
            ''),
    ].where((t) => t.isNotEmpty).toList();
  }
}

// ---------------------------------------------------------------------------
// Envio pelo FCM (API HTTP v1)
// ---------------------------------------------------------------------------

/// Resultado do envio para um token.
enum ResultadoPush { enviado, tokenInvalido, erro }

/// Monta a mensagem do FCM para uma notificação do sistema.
Map<String, dynamic> mensagemFcm(String token, Notificacao n) => {
      'message': {
        'token': token,
        'notification': {'title': n.titulo, 'body': n.mensagem},
        // Dados extras para o app saber o que abrir ao tocar.
        'data': {
          'notificacaoId': n.id,
          'tipo': n.tipo,
          if (n.pedidoId != null) 'pedidoId': n.pedidoId!,
        },
        'android': {
          'priority': 'HIGH',
          'notification': {
            'channel_id': canalPedidos,
            'icon': 'ic_notificacao',
            'color': '#4CAF50',
            'tag': 'notificacao-${n.id}',
          },
        },
      },
    };

class PushFcmService {
  final String projectId;
  final http.Client _client;
  final DispositivoRepository dispositivos;

  PushFcmService({
    required this.projectId,
    required http.Client client,
    required this.dispositivos,
  }) : _client = client;

  Uri get _endpoint =>
      Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

  Future<ResultadoPush> enviarParaToken(String token, Notificacao n) async {
    final response = await _client.post(
      _endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(mensagemFcm(token, n)),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ResultadoPush.enviado;
    }
    // 404 UNREGISTERED: app desinstalado ou token expirado.
    // 400 INVALID_ARGUMENT com token mal formado também invalida.
    final texto = utf8.decode(response.bodyBytes);
    if (response.statusCode == 404 ||
        texto.contains('UNREGISTERED') ||
        (response.statusCode == 400 && texto.contains('registration token'))) {
      return ResultadoPush.tokenInvalido;
    }
    return ResultadoPush.erro;
  }

  /// Envia para todos os celulares do usuário e apaga tokens inválidos.
  /// Devolve quantos pushes foram aceitos pelo FCM.
  Future<int> enviarParaUsuario(String uid, Notificacao n) async {
    var enviados = 0;
    for (final token in await dispositivos.tokens(uid)) {
      final resultado = await enviarParaToken(token, n);
      if (resultado == ResultadoPush.enviado) enviados++;
      if (resultado == ResultadoPush.tokenInvalido) {
        await dispositivos.remover(uid, token);
      }
    }
    return enviados;
  }
}

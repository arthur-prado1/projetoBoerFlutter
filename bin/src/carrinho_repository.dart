import 'dart:convert';

import 'package:http/http.dart' as http;

import 'produto_repository.dart' show FirestoreException;

/// Carrinho de um usuário: produtoId -> quantidade (na ordem em que entraram).
typedef ItensCarrinho = Map<String, int>;

/// Onde a API guarda os carrinhos (um por usuário do Firebase Auth).
abstract class CarrinhoRepository {
  Future<ItensCarrinho> obter(String uid);
  Future<void> salvar(String uid, ItensCarrinho itens);
}

/// Onde a API guarda os pedidos finalizados.
abstract class PedidoRepository {
  /// Salva o pedido e devolve o ID gerado.
  Future<String> criar(Map<String, dynamic> pedido);
}

// ---------------------------------------------------------------------------
// Memória (sem chave do Firebase ou com USAR_MEMORIA=1)
// ---------------------------------------------------------------------------

class MemoriaCarrinhoRepository implements CarrinhoRepository {
  final Map<String, ItensCarrinho> _carrinhos = {};

  @override
  Future<ItensCarrinho> obter(String uid) async => {...?_carrinhos[uid]};

  @override
  Future<void> salvar(String uid, ItensCarrinho itens) async {
    if (itens.isEmpty) {
      _carrinhos.remove(uid);
    } else {
      _carrinhos[uid] = {...itens};
    }
  }
}

class MemoriaPedidoRepository implements PedidoRepository {
  final List<Map<String, dynamic>> pedidos = [];

  @override
  Future<String> criar(Map<String, dynamic> pedido) async {
    final id = '${pedidos.length + 1}';
    pedidos.add({...pedido, 'id': id});
    return id;
  }
}

// ---------------------------------------------------------------------------
// Firestore: coleções "carrinhos" (documento = uid) e "pedidos"
// ---------------------------------------------------------------------------

String baseDocumentosFirestore(String projectId) =>
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

Map<String, dynamic> decodificarFirestore(http.Response response, String acao) {
  final texto = utf8.decode(response.bodyBytes);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    String detalhe = texto;
    try {
      detalhe = (jsonDecode(texto) as Map)['error']['message'].toString();
    } catch (_) {}
    throw FirestoreException('falha ao $acao (${response.statusCode}): $detalhe',
        statusCode: response.statusCode);
  }
  if (texto.trim().isEmpty) return {};
  return jsonDecode(texto) as Map<String, dynamic>;
}

class FirestoreCarrinhoRepository implements CarrinhoRepository {
  static const colecao = 'carrinhos';

  final String projectId;
  final http.Client _client;

  FirestoreCarrinhoRepository({required this.projectId, required http.Client client})
      : _client = client;

  Uri _doc(String uid) => Uri.parse(
      '${baseDocumentosFirestore(projectId)}/$colecao/${Uri.encodeComponent(uid)}');

  @override
  Future<ItensCarrinho> obter(String uid) async {
    final response = await _client.get(_doc(uid));
    if (response.statusCode == 404) return {};
    final doc = decodificarFirestore(response, 'ler carrinho');
    final campos = camposParaMapa(doc['fields'] as Map<String, dynamic>?);
    final itens = <String, int>{};
    for (final item in (campos['itens'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = item['produtoId']?.toString() ?? '';
      final qtd = item['quantidade'] is num ? (item['quantidade'] as num).toInt() : 0;
      if (id.isNotEmpty && qtd > 0) itens[id] = qtd;
    }
    return itens;
  }

  @override
  Future<void> salvar(String uid, ItensCarrinho itens) async {
    if (itens.isEmpty) {
      final response = await _client.delete(_doc(uid));
      if (response.statusCode != 404) decodificarFirestore(response, 'esvaziar carrinho');
      return;
    }
    final response = await _client.patch(
      _doc(uid),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': mapaParaCampos({
          'uid': uid,
          'itens': [
            for (final e in itens.entries)
              {'produtoId': e.key, 'quantidade': e.value},
          ],
          'atualizadoEm': DateTime.now(),
        }),
      }),
    );
    decodificarFirestore(response, 'salvar carrinho');
  }
}

class FirestorePedidoRepository implements PedidoRepository {
  static const colecao = 'pedidos';

  final String projectId;
  final http.Client _client;

  FirestorePedidoRepository({required this.projectId, required http.Client client})
      : _client = client;

  @override
  Future<String> criar(Map<String, dynamic> pedido) async {
    final response = await _client.post(
      Uri.parse('${baseDocumentosFirestore(projectId)}/$colecao'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': mapaParaCampos(pedido)}),
    );
    final doc = decodificarFirestore(response, 'salvar pedido');
    return (doc['name']?.toString() ?? '').split('/').last;
  }
}

// --- Conversão genérica Dart <-> valores do Firestore ----------------------

/// {"a": 1} -> {"a": {"integerValue": "1"}}
Map<String, dynamic> mapaParaCampos(Map<String, dynamic> mapa) => {
      for (final e in mapa.entries) e.key: valorParaFirestore(e.value),
    };

Map<String, dynamic> valorParaFirestore(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is String) return {'stringValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(valorParaFirestore).toList()},
    };
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': {
          for (final e in v.entries) e.key.toString(): valorParaFirestore(e.value),
        },
      },
    };
  }
  throw ArgumentError('Tipo não suportado no Firestore: ${v.runtimeType}');
}

/// {"a": {"integerValue": "1"}} -> {"a": 1}
Map<String, dynamic> camposParaMapa(Map<String, dynamic>? campos) => {
      for (final e in (campos ?? const {}).entries) e.key: valorDoFirestore(e.value),
    };

dynamic valorDoFirestore(dynamic valor) {
  if (valor is! Map) return null;
  if (valor.containsKey('stringValue')) return valor['stringValue'];
  if (valor.containsKey('integerValue')) {
    return int.tryParse(valor['integerValue'].toString());
  }
  if (valor.containsKey('doubleValue')) return (valor['doubleValue'] as num).toDouble();
  if (valor.containsKey('booleanValue')) return valor['booleanValue'];
  if (valor.containsKey('timestampValue')) return valor['timestampValue'];
  if (valor.containsKey('arrayValue')) {
    final valores = (valor['arrayValue'] as Map?)?['values'] as List? ?? const [];
    return valores.map(valorDoFirestore).toList();
  }
  if (valor.containsKey('mapValue')) {
    return camposParaMapa(
        ((valor['mapValue'] as Map?)?['fields'] as Map?)?.cast<String, dynamic>());
  }
  return null;
}

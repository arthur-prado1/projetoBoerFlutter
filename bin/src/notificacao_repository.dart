import 'dart:convert';

import 'package:http/http.dart' as http;

import 'carrinho_repository.dart'
    show baseDocumentosFirestore, camposParaMapa, decodificarFirestore, mapaParaCampos;

/// Notificação de um usuário (ex.: "Compra confirmada").
class Notificacao {
  final String id;
  final String titulo;
  final String mensagem;
  final String tipo;
  final String? pedidoId;
  final bool lida;
  final DateTime criadoEm;

  Notificacao({
    this.id = '',
    required this.titulo,
    required this.mensagem,
    this.tipo = 'geral',
    this.pedidoId,
    this.lida = false,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now().toUtc();

  Notificacao copyWith({String? id, bool? lida}) => Notificacao(
        id: id ?? this.id,
        titulo: titulo,
        mensagem: mensagem,
        tipo: tipo,
        pedidoId: pedidoId,
        lida: lida ?? this.lida,
        criadoEm: criadoEm,
      );

  /// JSON devolvido pela API.
  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'mensagem': mensagem,
        'tipo': tipo,
        'pedidoId': pedidoId,
        'lida': lida,
        'criadoEm': criadoEm.toUtc().toIso8601String(),
      };

  /// Campos gravados no Firestore (sem o id, que é o nome do documento).
  Map<String, dynamic> paraArmazenar() => {
        'titulo': titulo,
        'mensagem': mensagem,
        'tipo': tipo,
        'pedidoId': pedidoId,
        'lida': lida,
        'criadoEm': criadoEm,
      };

  factory Notificacao.fromMap(String id, Map<String, dynamic> m) => Notificacao(
        id: id,
        titulo: m['titulo']?.toString() ?? '',
        mensagem: m['mensagem']?.toString() ?? '',
        tipo: m['tipo']?.toString() ?? 'geral',
        pedidoId: m['pedidoId']?.toString(),
        lida: m['lida'] == true,
        criadoEm: DateTime.tryParse(m['criadoEm']?.toString() ?? ''),
      );
}

/// Onde a API guarda as notificações de cada usuário.
abstract class NotificacaoRepository {
  /// Salva e devolve com o ID gerado.
  Future<Notificacao> criar(String uid, Notificacao n);

  /// Mais recentes primeiro.
  Future<List<Notificacao>> listar(String uid, {int limite = 50});

  /// Devolve null se a notificação não existe.
  Future<Notificacao?> marcarLida(String uid, String id);
}

// ---------------------------------------------------------------------------

class MemoriaNotificacaoRepository implements NotificacaoRepository {
  final Map<String, List<Notificacao>> _porUsuario = {};
  int _proximoId = 1;

  @override
  Future<Notificacao> criar(String uid, Notificacao n) async {
    final salva = n.copyWith(id: '${_proximoId++}');
    _porUsuario.putIfAbsent(uid, () => []).add(salva);
    return salva;
  }

  @override
  Future<List<Notificacao>> listar(String uid, {int limite = 50}) async {
    final lista = [...?_porUsuario[uid]]
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return lista.take(limite).toList();
  }

  @override
  Future<Notificacao?> marcarLida(String uid, String id) async {
    final lista = _porUsuario[uid];
    if (lista == null) return null;
    final i = lista.indexWhere((n) => n.id == id);
    if (i == -1) return null;
    return lista[i] = lista[i].copyWith(lida: true);
  }
}

// ---------------------------------------------------------------------------
// Firestore: notificacoes/{uid}/itens/{id}
// ---------------------------------------------------------------------------

class FirestoreNotificacaoRepository implements NotificacaoRepository {
  final String projectId;
  final http.Client _client;

  FirestoreNotificacaoRepository({required this.projectId, required http.Client client})
      : _client = client;

  String _colecao(String uid) =>
      '${baseDocumentosFirestore(projectId)}/notificacoes/${Uri.encodeComponent(uid)}/itens';

  Notificacao _doc(Map<String, dynamic> doc) => Notificacao.fromMap(
        (doc['name']?.toString() ?? '').split('/').last,
        camposParaMapa(doc['fields'] as Map<String, dynamic>?),
      );

  @override
  Future<Notificacao> criar(String uid, Notificacao n) async {
    final response = await _client.post(
      Uri.parse(_colecao(uid)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': mapaParaCampos(n.paraArmazenar())}),
    );
    return _doc(decodificarFirestore(response, 'salvar notificacao'));
  }

  @override
  Future<List<Notificacao>> listar(String uid, {int limite = 50}) async {
    final uri = Uri.parse(_colecao(uid)).replace(queryParameters: {
      'orderBy': 'criadoEm desc',
      'pageSize': '$limite',
    });
    final body = decodificarFirestore(await _client.get(uri), 'listar notificacoes');
    return [
      for (final d in (body['documents'] as List? ?? const []))
        _doc(d as Map<String, dynamic>),
    ];
  }

  @override
  Future<Notificacao?> marcarLida(String uid, String id) async {
    final uri = Uri.parse('${_colecao(uid)}/${Uri.encodeComponent(id)}').replace(
      queryParameters: {
        'updateMask.fieldPaths': 'lida',
        'currentDocument.exists': 'true',
      },
    );
    final response = await _client.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': mapaParaCampos({'lida': true}),
      }),
    );
    if (response.statusCode == 404) return null;
    return _doc(decodificarFirestore(response, 'marcar notificacao como lida'));
  }
}

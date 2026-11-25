import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'package:equadras/model/produto_model.dart';

/// Onde a API guarda os produtos.
abstract class ProdutoRepository {
  /// Texto curto para o log de inicialização.
  String get descricao;

  Future<List<ProdutoModel>> listar();
  Future<ProdutoModel?> buscar(String id);

  /// Cria o produto e devolve com o ID gerado.
  Future<ProdutoModel> criar(ProdutoModel produto);

  /// Grava o produto inteiro (o ID precisa existir).
  Future<ProdutoModel> salvar(ProdutoModel produto);

  Future<void> excluir(String id);
}

/// Produtos de exemplo usados quando o banco está vazio.
List<ProdutoModel> produtosIniciais() => [
      ProdutoModel(
        nome: 'Bola de Futebol Society',
        categoria: 'Futebol',
        preco: 120.0,
        quantidade: 15,
        imagemUrl:
            'https://images.unsplash.com/photo-1614632537190-23e4146777db?w=400',
      ),
      ProdutoModel(
        nome: 'Raquete de Beach Tennis',
        categoria: 'Beach Tennis',
        preco: 350.0,
        quantidade: 8,
        imagemUrl:
            'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?w=400',
      ),
    ];

/// Ordena por ID numérico ("2" antes de "10"); IDs não numéricos vão ao fim.
int compararIds(ProdutoModel a, ProdutoModel b) {
  final na = int.tryParse(a.id ?? '');
  final nb = int.tryParse(b.id ?? '');
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return (a.id ?? '').compareTo(b.id ?? '');
}

/// Próximo ID numérico: maior ID numérico existente + 1.
int proximoId(Iterable<ProdutoModel> produtos) {
  var maior = 0;
  for (final p in produtos) {
    final n = int.tryParse(p.id ?? '');
    if (n != null && n > maior) maior = n;
  }
  return maior + 1;
}

// ---------------------------------------------------------------------------
// Memória (modo antigo): usado só quando não há chave do Firebase.
// ---------------------------------------------------------------------------

class MemoriaProdutoRepository implements ProdutoRepository {
  final List<ProdutoModel> _produtos = [];

  MemoriaProdutoRepository({bool comExemplos = true}) {
    if (comExemplos) {
      var id = 1;
      for (final p in produtosIniciais()) {
        _produtos.add(p.copyWith(id: '${id++}'));
      }
    }
  }

  @override
  String get descricao => 'MEMÓRIA (os dados somem ao reiniciar a API)';

  @override
  Future<List<ProdutoModel>> listar() async => [..._produtos]..sort(compararIds);

  @override
  Future<ProdutoModel?> buscar(String id) async {
    for (final p in _produtos) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<ProdutoModel> criar(ProdutoModel produto) async {
    final novo = produto.copyWith(id: '${proximoId(_produtos)}');
    _produtos.add(novo);
    return novo;
  }

  @override
  Future<ProdutoModel> salvar(ProdutoModel produto) async {
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index == -1) throw StateError('Produto ${produto.id} não existe');
    _produtos[index] = produto;
    return produto;
  }

  @override
  Future<void> excluir(String id) async {
    _produtos.removeWhere((p) => p.id == id);
  }
}

// ---------------------------------------------------------------------------
// Firestore: grava na coleção "produtos" do projeto Firebase, pela API REST
// oficial do Firestore, autenticando com a chave de conta de serviço.
// ---------------------------------------------------------------------------

class FirestoreException implements Exception {
  final String mensagem;
  final int? statusCode;
  FirestoreException(this.mensagem, {this.statusCode});

  @override
  String toString() => 'Firestore: $mensagem';
}

class FirestoreProdutoRepository implements ProdutoRepository {
  static const colecao = 'produtos';

  final String projectId;
  final http.Client _client;

  FirestoreProdutoRepository({required this.projectId, required http.Client client})
      : _client = client;

  /// Cliente HTTP já autenticado (reaproveitado pelo carrinho e pedidos).
  http.Client get client => _client;

  /// Lê a chave de conta de serviço (.json) e autentica no Google.
  static Future<FirestoreProdutoRepository> conectar(File chave) async {
    final json = jsonDecode(await chave.readAsString()) as Map<String, dynamic>;
    final projectId = json['project_id']?.toString() ?? '';
    if (projectId.isEmpty) {
      throw FirestoreException('a chave ${chave.path} não tem "project_id"');
    }
    final client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(json),
      ['https://www.googleapis.com/auth/datastore'],
    );
    return FirestoreProdutoRepository(projectId: projectId, client: client);
  }

  @override
  String get descricao =>
      'FIRESTORE (projeto "$projectId", coleção "$colecao")';

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$colecao';

  @override
  Future<List<ProdutoModel>> listar() async {
    final produtos = <ProdutoModel>[];
    String? pageToken;
    do {
      final uri = Uri.parse(_base).replace(queryParameters: {
        'pageSize': '300',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final body = _decode(await _client.get(uri), 'listar produtos');
      for (final doc in (body['documents'] as List? ?? const [])) {
        produtos.add(documentoParaProduto(doc as Map<String, dynamic>));
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return produtos..sort(compararIds);
  }

  @override
  Future<ProdutoModel?> buscar(String id) async {
    final response = await _client.get(Uri.parse('$_base/${Uri.encodeComponent(id)}'));
    if (response.statusCode == 404) return null;
    return documentoParaProduto(_decode(response, 'buscar produto $id'));
  }

  @override
  Future<ProdutoModel> criar(ProdutoModel produto) async {
    // IDs numéricos (1, 2, 3...) para continuar compatível com o Postman.
    var id = proximoId(await listar());
    for (var tentativa = 0; tentativa < 5; tentativa++, id++) {
      final uri = Uri.parse(_base).replace(queryParameters: {'documentId': '$id'});
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': produtoParaCampos(produto)}),
      );
      if (response.statusCode == 409) continue; // ID já usado; tenta o próximo
      return documentoParaProduto(_decode(response, 'criar produto'));
    }
    throw FirestoreException('não foi possível gerar um ID livre');
  }

  @override
  Future<ProdutoModel> salvar(ProdutoModel produto) async {
    final id = produto.id;
    if (id == null || id.isEmpty) throw FirestoreException('produto sem ID');
    final uri = Uri.parse('$_base/${Uri.encodeComponent(id)}')
        .replace(queryParameters: {'currentDocument.exists': 'true'});
    final response = await _client.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': produtoParaCampos(produto)}),
    );
    return documentoParaProduto(_decode(response, 'salvar produto $id'));
  }

  @override
  Future<void> excluir(String id) async {
    final response =
        await _client.delete(Uri.parse('$_base/${Uri.encodeComponent(id)}'));
    _decode(response, 'excluir produto $id');
  }

  Map<String, dynamic> _decode(http.Response response, String acao) {
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
}

// --- Conversão entre ProdutoModel e o formato de documento do Firestore -----

/// {"nome": "Bola"} -> {"nome": {"stringValue": "Bola"}}
Map<String, dynamic> produtoParaCampos(ProdutoModel p) => {
      'nome': {'stringValue': p.nome},
      'categoria': {'stringValue': p.categoria},
      'preco': {'doubleValue': p.preco},
      'quantidade': {'integerValue': '${p.quantidade}'},
      'imagemUrl': {'stringValue': p.imagemUrl},
      'atualizadoEm': {
        'timestampValue': DateTime.now().toUtc().toIso8601String(),
      },
    };

/// Documento do Firestore -> ProdutoModel (o ID é o fim do "name").
ProdutoModel documentoParaProduto(Map<String, dynamic> doc) {
  final campos = (doc['fields'] as Map<String, dynamic>? ?? const {});
  final mapa = <String, dynamic>{
    for (final e in campos.entries) e.key: _valorFirestore(e.value),
  };
  final nome = doc['name']?.toString() ?? '';
  mapa['id'] = nome.split('/').last;
  return ProdutoModel.fromMap(mapa);
}

dynamic _valorFirestore(dynamic valor) {
  if (valor is! Map) return null;
  if (valor.containsKey('stringValue')) return valor['stringValue'];
  if (valor.containsKey('integerValue')) {
    return int.tryParse(valor['integerValue'].toString());
  }
  if (valor.containsKey('doubleValue')) return (valor['doubleValue'] as num).toDouble();
  if (valor.containsKey('booleanValue')) return valor['booleanValue'];
  if (valor.containsKey('timestampValue')) return valor['timestampValue'];
  return null;
}

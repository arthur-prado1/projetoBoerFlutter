import 'dart:convert';
import 'dart:io';
import '../lib/model/produto_model.dart';

final List<ProdutoModel> produtosDb = [
  ProdutoModel(
    id: '1',
    nome: 'Bola de Futebol Society',
    categoria: 'Futebol',
    preco: 120.0,
    quantidade: 15,
  ),
  ProdutoModel(
    id: '2',
    nome: 'Raquete de Beach Tennis',
    categoria: 'Beach Tennis',
    preco: 350.0,
    quantidade: 8,
  ),
];

int nextId = 3;

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Servidor REST rodando em http://${server.address.host}:${server.port}');

  await for (HttpRequest request in server) {
    _handleRequest(request);
  }
}

void _handleRequest(HttpRequest request) async {
  final response = request.response;
  response.headers.add('Access-Control-Allow-Origin', '*');
  response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept');
  response.headers.contentType = ContentType.json;

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  final segments = request.uri.pathSegments;

  List<String> pathSegments = segments;
  if (pathSegments.isNotEmpty && pathSegments.first == 'api') {
    pathSegments = pathSegments.sublist(1);
  }

  if (pathSegments.isEmpty || pathSegments.first != 'produtos') {
    _sendJson(response, HttpStatus.notFound, {'erro': 'Rota nao encontrada'});
    return;
  }

  try {
    if (pathSegments.length == 1) {
      if (request.method == 'GET') {
        final list = produtosDb.map((p) => p.toMap()).toList();
        _sendJson(response, HttpStatus.ok, list);
        return;
      }

      if (request.method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        if (content.trim().isEmpty) {
          _sendJson(response, HttpStatus.badRequest, {'erro': 'Corpo da requisicao vazio'});
          return;
        }

        final data = jsonDecode(content);
        if (data is! Map<String, dynamic>) {
          _sendJson(response, HttpStatus.badRequest, {'erro': 'Formato JSON invalido'});
          return;
        }

        final novoProduto = ProdutoModel(
          id: (nextId++).toString(),
          nome: data['nome']?.toString() ?? '',
          categoria: data['categoria']?.toString() ?? '',
          preco: (data['preco'] is num)
              ? (data['preco'] as num).toDouble()
              : (double.tryParse(data['preco']?.toString() ?? '0') ?? 0.0),
          quantidade: (data['quantidade'] is num)
              ? (data['quantidade'] as num).toInt()
              : (int.tryParse(data['quantidade']?.toString() ?? '0') ?? 0),
        );

        produtosDb.add(novoProduto);
        _sendJson(response, HttpStatus.created, novoProduto.toMap());
        return;
      }
    }

    if (pathSegments.length == 2) {
      final id = pathSegments[1];
      final index = produtosDb.indexWhere((p) => p.id == id);

      if (request.method == 'GET') {
        if (index == -1) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }
        _sendJson(response, HttpStatus.ok, produtosDb[index].toMap());
        return;
      }

      if (request.method == 'PUT') {
        if (index == -1) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }

        final content = await utf8.decoder.bind(request).join();
        if (content.trim().isEmpty) {
          _sendJson(response, HttpStatus.badRequest, {'erro': 'Corpo da requisicao vazio'});
          return;
        }

        final data = jsonDecode(content);
        if (data is! Map<String, dynamic>) {
          _sendJson(response, HttpStatus.badRequest, {'erro': 'Formato JSON invalido'});
          return;
        }

        final atualizado = produtosDb[index].copyWith(
          nome: data['nome']?.toString() ?? produtosDb[index].nome,
          categoria: data['categoria']?.toString() ?? produtosDb[index].categoria,
          preco: data['preco'] != null
              ? ((data['preco'] is num)
                  ? (data['preco'] as num).toDouble()
                  : (double.tryParse(data['preco']?.toString() ?? '0') ?? produtosDb[index].preco))
              : produtosDb[index].preco,
          quantidade: data['quantidade'] != null
              ? ((data['quantidade'] is num)
                  ? (data['quantidade'] as num).toInt()
                  : (int.tryParse(data['quantidade']?.toString() ?? '0') ?? produtosDb[index].quantidade))
              : produtosDb[index].quantidade,
        );

        produtosDb[index] = atualizado;
        _sendJson(response, HttpStatus.ok, atualizado.toMap());
        return;
      }

      if (request.method == 'DELETE') {
        if (index == -1) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }

        final removido = produtosDb.removeAt(index);
        _sendJson(response, HttpStatus.ok, {
          'mensagem': 'Produto removido com sucesso',
          'produto': removido.toMap(),
        });
        return;
      }
    }

    _sendJson(response, HttpStatus.methodNotAllowed, {'erro': 'Metodo nao permitido'});
  } catch (e) {
    _sendJson(response, HttpStatus.internalServerError, {'erro': e.toString()});
  }
}

void _sendJson(HttpResponse response, int status, dynamic body) {
  response.statusCode = status;
  response.write(jsonEncode(body));
  response.close();
}

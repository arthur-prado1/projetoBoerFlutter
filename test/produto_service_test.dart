import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:equadras/model/produto_model.dart';
import 'package:equadras/services/produto_service.dart';

const _base = 'http://api.teste/produtos';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('getProdutos faz GET /produtos e converte a lista', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), _base);
      return _json([
        {'id': '1', 'nome': 'Bola', 'categoria': 'Futebol', 'preco': 120.0, 'quantidade': 15},
        {'id': '2', 'nome': 'Raquete', 'categoria': 'Tênis', 'preco': 350, 'quantidade': 8},
      ], 200);
    });

    final produtos =
        await ProdutoService(baseUrl: _base, client: client).getProdutos();

    expect(produtos, hasLength(2));
    expect(produtos[1].categoria, 'Tênis');
    expect(produtos[1].preco, 350.0);
  });

  test('createProduto faz POST com JSON sem id e espera 201', () async {
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body.containsKey('id'), isFalse);
      expect(body['nome'], 'Rede de Vôlei');
      return _json({...body, 'id': '3'}, 201);
    });

    final criado = await ProdutoService(baseUrl: _base, client: client)
        .createProduto(ProdutoModel(
      nome: 'Rede de Vôlei',
      categoria: 'Vôlei',
      preco: 85.0,
      quantidade: 4,
    ));

    expect(criado.id, '3');
  });

  test('updateProduto faz PUT em /produtos/{id}', () async {
    final client = MockClient((req) async {
      expect(req.method, 'PUT');
      expect(req.url.toString(), '$_base/1');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json({...body, 'id': '1'}, 200);
    });

    final atualizado = await ProdutoService(baseUrl: _base, client: client)
        .updateProduto(ProdutoModel(
      id: '1',
      nome: 'Bola',
      categoria: 'Futebol',
      preco: 110.0,
      quantidade: 20,
    ));

    expect(atualizado.quantidade, 20);
  });

  test('updateProduto sem id lança erro sem chamar a API', () async {
    final client = MockClient((_) async => fail('não deveria chamar a API'));
    expect(
      () => ProdutoService(baseUrl: _base, client: client).updateProduto(
        ProdutoModel(nome: 'X', categoria: 'Y', preco: 1, quantidade: 1),
      ),
      throwsA(isA<ProdutoApiException>()),
    );
  });

  test('deleteProduto faz DELETE e repassa o erro da API', () async {
    final client = MockClient((req) async {
      expect(req.method, 'DELETE');
      return _json({'erro': 'Produto nao encontrado'}, 404);
    });

    expect(
      () => ProdutoService(baseUrl: _base, client: client).deleteProduto('99'),
      throwsA(isA<ProdutoApiException>()
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.mensagem, 'mensagem', contains('Produto nao encontrado'))),
    );
  });

  test('imagemUrl vai e volta no JSON e é opcional', () {
    final comFoto = ProdutoModel.fromMap({
      'id': '1', 'nome': 'Bola', 'categoria': 'Futebol', 'preco': 1, 'quantidade': 1,
      'imagemUrl': 'https://exemplo.com/bola.jpg',
    });
    expect(comFoto.toMap()['imagemUrl'], 'https://exemplo.com/bola.jpg');

    final semFoto = ProdutoModel.fromMap(
        {'id': '2', 'nome': 'X', 'categoria': 'Y', 'preco': 1, 'quantidade': 1});
    expect(semFoto.imagemUrl, '');
  });

  test('wsUri deriva o WebSocket da URL REST', () {
    expect(ProdutoService(baseUrl: 'http://localhost:8080/produtos').wsUri.toString(),
        'ws://localhost:8080/ws');
    expect(ProdutoService(baseUrl: 'https://api.site.com/api/produtos').wsUri.toString(),
        'wss://api.site.com/api/ws');
  });

  test('EventoProduto lê as mensagens do servidor', () {
    final evento = EventoProduto.fromJson(jsonEncode({
      'evento': 'atualizado',
      'produto': {'id': '1', 'nome': 'Bola', 'categoria': 'Futebol', 'preco': 99.9, 'quantidade': 0},
    }));
    expect(evento?.tipo, TipoEventoProduto.atualizado);
    expect(evento?.produto.quantidade, 0);

    expect(EventoProduto.fromJson('{"evento":"outro","produto":{}}'), isNull);
    expect(EventoProduto.fromJson('não é json'), isNull);
  });

  test('API fora do ar vira mensagem amigável', () async {
    final client = MockClient((_) async => throw http.ClientException('offline'));

    expect(
      () => ProdutoService(baseUrl: _base, client: client).getProdutos(),
      throwsA(isA<ProdutoApiException>()
          .having((e) => e.mensagem, 'mensagem', contains('dart run bin/server.dart'))),
    );
  });
}

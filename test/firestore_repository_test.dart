import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:equadras/model/produto_model.dart';

import '../bin/src/produto_repository.dart';

const _docs =
    'https://firestore.googleapis.com/v1/projects/proj-teste/databases/(default)/documents/produtos';

Map<String, dynamic> _doc(String id, String nome, {num preco = 10, int qtd = 1}) => {
      'name': 'projects/proj-teste/databases/(default)/documents/produtos/$id',
      'fields': produtoParaCampos(ProdutoModel(
        nome: nome,
        categoria: 'Futebol',
        preco: preco.toDouble(),
        quantidade: qtd,
      )),
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

FirestoreProdutoRepository _repo(MockClient client) =>
    FirestoreProdutoRepository(projectId: 'proj-teste', client: client);

void main() {
  test('converte produto para documento do Firestore e volta', () {
    final original = ProdutoModel(
      nome: 'Raquete',
      categoria: 'Tênis',
      preco: 350.5,
      quantidade: 8,
      imagemUrl: 'https://exemplo.com/r.jpg',
    );
    final campos = produtoParaCampos(original);
    expect(campos['quantidade'], {'integerValue': '8'});
    expect(campos['preco'], {'doubleValue': 350.5});

    final volta = documentoParaProduto({
      'name': 'projects/p/databases/(default)/documents/produtos/7',
      'fields': campos,
    });
    expect(volta.id, '7');
    expect(volta.nome, 'Raquete');
    expect(volta.preco, 350.5);
    expect(volta.quantidade, 8);
    expect(volta.imagemUrl, 'https://exemplo.com/r.jpg');
  });

  test('aceita documento criado à mão no Console (preço inteiro, sem foto)', () {
    final p = documentoParaProduto({
      'name': 'projects/p/databases/(default)/documents/produtos/abcXYZ',
      'fields': {
        'nome': {'stringValue': 'Apito'},
        'preco': {'integerValue': '15'},
      },
    });
    expect(p.id, 'abcXYZ');
    expect(p.preco, 15.0);
    expect(p.quantidade, 0);
    expect(p.imagemUrl, '');
  });

  test('listar percorre as páginas e ordena por ID numérico', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      if (req.url.queryParameters['pageToken'] == null) {
        return _json({
          'documents': [_doc('10', 'Dez'), _doc('2', 'Dois')],
          'nextPageToken': 'pag2',
        });
      }
      return _json({
        'documents': [_doc('1', 'Um')],
      });
    });

    final lista = await _repo(client).listar();
    expect(lista.map((p) => p.id), ['1', '2', '10']);
  });

  test('listar com coleção vazia devolve lista vazia', () async {
    final client = MockClient((_) async => _json({}));
    expect(await _repo(client).listar(), isEmpty);
  });

  test('criar usa o próximo ID numérico e pula ID já ocupado (409)', () async {
    final idsTentados = <String>[];
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        return _json({'documents': [_doc('1', 'Um'), _doc('3', 'Três')]});
      }
      expect(req.method, 'POST');
      final id = req.url.queryParameters['documentId']!;
      idsTentados.add(id);
      if (id == '4') return _json({'error': {'message': 'ALREADY_EXISTS'}}, 409);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json({
        'name': 'projects/proj-teste/databases/(default)/documents/produtos/$id',
        'fields': body['fields'],
      });
    });

    final criado = await _repo(client).criar(
      ProdutoModel(nome: 'Novo', categoria: 'Vôlei', preco: 85, quantidade: 4),
    );
    expect(idsTentados, ['4', '5']);
    expect(criado.id, '5');
    expect(criado.categoria, 'Vôlei');
  });

  test('salvar faz PATCH exigindo que o documento exista', () async {
    final client = MockClient((req) async {
      expect(req.method, 'PATCH');
      expect(req.url.path, endsWith('/produtos/2'));
      expect(req.url.queryParameters['currentDocument.exists'], 'true');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json({'name': '$_docs/2', 'fields': body['fields']});
    });

    final salvo = await _repo(client).salvar(ProdutoModel(
      id: '2',
      nome: 'Bola',
      categoria: 'Futebol',
      preco: 99.9,
      quantidade: 0,
    ));
    expect(salvo.quantidade, 0);
  });

  test('buscar devolve null quando o documento não existe', () async {
    final client = MockClient((_) async => _json({'error': {'message': 'NOT_FOUND'}}, 404));
    expect(await _repo(client).buscar('99'), isNull);
  });

  test('erro do Firestore vira FirestoreException com a mensagem do Google', () async {
    final client = MockClient((_) async =>
        _json({'error': {'message': 'Missing or insufficient permissions.'}}, 403));

    expect(
      () => _repo(client).listar(),
      throwsA(isA<FirestoreException>()
          .having((e) => e.statusCode, 'statusCode', 403)
          .having((e) => e.mensagem, 'mensagem', contains('insufficient permissions'))),
    );
  });

  test('repositório em memória: cria com ID sequencial, salva e exclui', () async {
    final repo = MemoriaProdutoRepository();
    expect((await repo.listar()).map((p) => p.id), ['1', '2']);

    final novo = await repo.criar(
        ProdutoModel(nome: 'X', categoria: 'Y', preco: 1, quantidade: 1));
    expect(novo.id, '3');

    await repo.salvar(novo.copyWith(quantidade: 9));
    expect((await repo.buscar('3'))?.quantidade, 9);

    await repo.excluir('1');
    expect((await repo.listar()).map((p) => p.id), ['2', '3']);
  });
}

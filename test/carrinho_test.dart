import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:equadras/model/produto_model.dart';
import 'package:equadras/services/carrinho_service.dart';
import 'package:equadras/services/produto_service.dart';

import '../bin/src/carrinho_repository.dart';
import '../bin/src/loja.dart';
import '../bin/src/produto_repository.dart';

/// Loja em memória com: 1 = Bola (R$ 120, 15 un.), 2 = Raquete (R$ 350, 8 un.)
({LojaService loja, MemoriaProdutoRepository produtos, MemoriaPedidoRepository pedidos})
    _novaLoja() {
  final produtos = MemoriaProdutoRepository();
  final pedidos = MemoriaPedidoRepository();
  return (
    loja: LojaService(
      produtos: produtos,
      carrinhos: MemoriaCarrinhoRepository(),
      pedidos: pedidos,
    ),
    produtos: produtos,
    pedidos: pedidos,
  );
}

Matcher _lojaErro(int status, [String? trecho]) => isA<LojaException>()
    .having((e) => e.status, 'status', status)
    .having((e) => e.mensagem, 'mensagem', contains(trecho ?? ''));

void main() {
  group('Regras do carrinho (LojaService)', () {
    test('adicionar soma quantidades e calcula subtotal e total', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 2);
      final carrinho = await t.loja.adicionar('u1', '2', 1);
      await t.loja.adicionar('u1', '1', 1);

      final c = await t.loja.verCarrinho('u1');
      expect(c['quantidadeItens'], 4);
      expect(c['total'], 120 * 3 + 350.0);
      final bola = (c['itens'] as List).first as Map;
      expect(bola['quantidade'], 3);
      expect(bola['subtotal'], 360.0);
      expect(carrinho['itens'], hasLength(2));
    });

    test('carrinhos são separados por usuário', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 2);
      expect((await t.loja.verCarrinho('u2'))['itens'], isEmpty);
    });

    test('não deixa passar do estoque (409)', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '2', 8);
      expect(() => t.loja.adicionar('u1', '2', 1), throwsA(_lojaErro(409, 'apenas 8')));
      expect(() => t.loja.definirQuantidade('u1', '2', 9), throwsA(_lojaErro(409)));
    });

    test('produto inexistente (404), quantidade inválida (400), sem usuário (400)', () async {
      final t = _novaLoja();
      expect(() => t.loja.adicionar('u1', '99', 1), throwsA(_lojaErro(404)));
      expect(() => t.loja.adicionar('u1', '1', 0), throwsA(_lojaErro(400)));
      expect(() => t.loja.verCarrinho(' '), throwsA(_lojaErro(400)));
    });

    test('definir 0 e remover tiram o item; esvaziar limpa tudo', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 2);
      await t.loja.adicionar('u1', '2', 1);
      expect((await t.loja.definirQuantidade('u1', '1', 0))['itens'], hasLength(1));
      expect((await t.loja.remover('u1', '2'))['itens'], isEmpty);
      await t.loja.adicionar('u1', '1', 1);
      expect((await t.loja.esvaziar('u1'))['itens'], isEmpty);
    });

    test('produto excluído sai do carrinho sozinho', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 2);
      await t.loja.adicionar('u1', '2', 1);
      await t.produtos.excluir('1');
      final c = await t.loja.verCarrinho('u1');
      expect((c['itens'] as List).map((i) => i['produtoId']), ['2']);
    });

    test('finalizar baixa o estoque, salva o pedido e esvazia o carrinho', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 3);
      await t.loja.adicionar('u1', '2', 2);

      final compra = await t.loja.finalizar('u1');

      expect(compra.pedido['total'], 120 * 3 + 350 * 2.0);
      expect(compra.pedido['quantidadeItens'], 5);
      expect(compra.pedido['id'], '1');
      expect(t.pedidos.pedidos, hasLength(1));
      expect((await t.produtos.buscar('1'))!.quantidade, 12);
      expect((await t.produtos.buscar('2'))!.quantidade, 6);
      expect(compra.produtosAtualizados.map((p) => p.quantidade), [12, 6]);
      expect((await t.loja.verCarrinho('u1'))['itens'], isEmpty);
    });

    test('finalizar sem estoque não altera nada (409)', () async {
      final t = _novaLoja();
      await t.loja.adicionar('u1', '1', 3);
      await t.loja.adicionar('u1', '2', 5);
      // Alguém comprou/alterou o estoque da raquete depois.
      final raquete = (await t.produtos.buscar('2'))!;
      await t.produtos.salvar(raquete.copyWith(quantidade: 4));

      final c = await t.loja.verCarrinho('u1');
      expect(((c['itens'] as List)[1] as Map)['estoqueSuficiente'], isFalse);

      await expectLater(t.loja.finalizar('u1'), throwsA(_lojaErro(409, 'Raquete')));
      expect((await t.produtos.buscar('1'))!.quantidade, 15); // bola intacta
      expect(t.pedidos.pedidos, isEmpty);
      expect((await t.loja.verCarrinho('u1'))['itens'], hasLength(2));
    });

    test('finalizar carrinho vazio dá 400', () async {
      final t = _novaLoja();
      expect(() => t.loja.finalizar('u1'), throwsA(_lojaErro(400, 'vazio')));
    });
  });

  group('Carrinho e pedidos no Firestore', () {
    const base =
        'https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents';

    test('conversão genérica ida e volta (listas, mapas, datas)', () {
      final original = {
        'texto': 'Vôlei',
        'inteiro': 3,
        'decimal': 85.5,
        'lista': [
          {'produtoId': '1', 'quantidade': 2},
        ],
        'ativo': true,
      };
      final volta = camposParaMapa(mapaParaCampos(original));
      expect(volta, original);
      expect(valorParaFirestore(DateTime.utc(2026, 1, 2)),
          {'timestampValue': '2026-01-02T00:00:00.000Z'});
    });

    test('salvar grava em carrinhos/{uid} e obter lê de volta', () async {
      Map<String, dynamic>? gravado;
      final client = MockClient((req) async {
        expect(req.url.toString(), startsWith('$base/carrinhos/abc'));
        if (req.method == 'PATCH') {
          gravado = (jsonDecode(req.body) as Map<String, dynamic>)['fields'];
          return http.Response('{}', 200);
        }
        return http.Response(jsonEncode({'fields': gravado}), 200);
      });
      final repo = FirestoreCarrinhoRepository(projectId: 'p', client: client);

      await repo.salvar('abc', {'2': 1, '1': 3});
      expect(await repo.obter('abc'), {'2': 1, '1': 3});
    });

    test('carrinho inexistente é vazio; esvaziar apaga o documento', () async {
      final metodos = <String>[];
      final client = MockClient((req) async {
        metodos.add(req.method);
        return http.Response('{"error":{"message":"NOT_FOUND"}}', 404);
      });
      final repo = FirestoreCarrinhoRepository(projectId: 'p', client: client);
      expect(await repo.obter('x'), isEmpty);
      await repo.salvar('x', {});
      expect(metodos, ['GET', 'DELETE']);
    });

    test('pedido é criado em pedidos com ID automático', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), '$base/pedidos');
        return http.Response(jsonEncode({'name': 'projects/p/databases/(default)/documents/pedidos/XyZ'}), 200);
      });
      final id = await FirestorePedidoRepository(projectId: 'p', client: client)
          .criar({'uid': 'u', 'total': 10.0, 'criadoEm': DateTime.now()});
      expect(id, 'XyZ');
    });

    test('erro de permissão vira FirestoreException', () async {
      final client = MockClient((_) async =>
          http.Response('{"error":{"message":"PERMISSION_DENIED"}}', 403));
      expect(() => FirestoreCarrinhoRepository(projectId: 'p', client: client).obter('u'),
          throwsA(isA<FirestoreException>()));
    });
  });

  group('CarrinhoService (app)', () {
    http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

    final carrinhoJson = {
      'uid': 'u1',
      'itens': [
        {
          'produtoId': '1', 'nome': 'Bola', 'categoria': 'Futebol', 'imagemUrl': '',
          'precoUnitario': 120.0, 'quantidade': 2, 'estoque': 15,
          'estoqueSuficiente': true, 'subtotal': 240.0,
        },
      ],
      'quantidadeItens': 2,
      'total': 240.0,
    };

    test('adicionar chama POST /carrinhos/{uid}/itens e lê o carrinho', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.teste/carrinhos/u1/itens');
        expect(jsonDecode(req.body), {'produtoId': '1', 'quantidade': 2});
        return json(carrinhoJson);
      });
      final c = await CarrinhoService(apiUrl: 'http://api.teste', client: client)
          .adicionar('u1', '1', quantidade: 2);
      expect(c.total, 240.0);
      expect(c.quantidadeDe('1'), 2);
      expect(c.podeFinalizar, isTrue);
    });

    test('erro de estoque mostra a mensagem da API', () async {
      final client = MockClient((_) async =>
          json({'erro': 'Estoque insuficiente para "Bola": apenas 15 un. disponiveis'}, 409));
      expect(
        () => CarrinhoService(apiUrl: 'http://api.teste', client: client)
            .definirQuantidade('u1', '1', 99),
        throwsA(isA<ProdutoApiException>()
            .having((e) => e.mensagem, 'mensagem', contains('apenas 15'))),
      );
    });

    test('finalizar devolve o pedido', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/carrinhos/u1/finalizar');
        return json({
          'mensagem': 'ok',
          'pedido': {'id': 'abc', 'quantidadeItens': 2, 'total': 240.0},
        }, 201);
      });
      final pedido = await CarrinhoService(apiUrl: 'http://api.teste', client: client)
          .finalizar('u1');
      expect(pedido.id, 'abc');
      expect(pedido.total, 240.0);
    });
  });

  test('ProdutoModel continua compatível com o repositório', () {
    expect(ProdutoModel(nome: 'a', categoria: 'b', preco: 1, quantidade: 1).imagemUrl, '');
  });
}

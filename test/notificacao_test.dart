import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:equadras/model/notificacao_model.dart';
import 'package:equadras/services/notificacao_controller.dart';
import 'package:equadras/services/notificacao_service.dart';

import '../bin/src/carrinho_repository.dart';
import '../bin/src/loja.dart';
import '../bin/src/notificacao_repository.dart';
import '../bin/src/produto_repository.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('API: notificação ao finalizar a compra', () {
    test('finalizar cria "Compra confirmada" com código e total', () async {
      final notificacoes = MemoriaNotificacaoRepository();
      final loja = LojaService(
        produtos: MemoriaProdutoRepository(),
        carrinhos: MemoriaCarrinhoRepository(),
        pedidos: MemoriaPedidoRepository(),
        notificacoes: notificacoes,
      );
      await loja.adicionar('u1', '1', 2); // 2 x R$ 120
      await loja.adicionar('u1', '2', 1); // 1 x R$ 350

      final compra = await loja.finalizar('u1');

      final n = compra.notificacao!;
      expect(n.titulo, 'Compra confirmada');
      expect(n.mensagem, 'Pedido nº 1 • 3 item(ns) • Total R\$ 590,00');
      expect(n.tipo, 'pedido');
      expect(n.pedidoId, '1');
      expect(n.lida, isFalse);
      expect(compra.pedido['codigo'], '1');
      expect(await notificacoes.listar('u1'), hasLength(1));
      expect(await notificacoes.listar('outro'), isEmpty);
    });

    test('código do pedido usa os 6 primeiros caracteres em maiúsculas', () {
      expect(codigoPedido('aB3dE9xYz123'), 'AB3DE9');
      expect(codigoPedido('7'), '7');
    });

    test('memória: lista da mais nova para a mais antiga e marca como lida', () async {
      final repo = MemoriaNotificacaoRepository();
      await repo.criar('u', Notificacao(titulo: 'A', mensagem: '', criadoEm: DateTime.utc(2026, 1, 1)));
      final b = await repo.criar('u', Notificacao(titulo: 'B', mensagem: '', criadoEm: DateTime.utc(2026, 1, 2)));
      expect((await repo.listar('u')).map((n) => n.titulo), ['B', 'A']);

      expect((await repo.marcarLida('u', b.id))!.lida, isTrue);
      expect(await repo.marcarLida('u', '999'), isNull);
    });
  });

  group('API: notificações no Firestore', () {
    const colecao =
        'https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents/notificacoes/u1/itens';

    test('listar pede ordenado por data (mais nova primeiro)', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.toString(), startsWith(colecao));
        expect(req.url.queryParameters['orderBy'], 'criadoEm desc');
        return _json({
          'documents': [
            {
              'name': 'projects/p/databases/(default)/documents/notificacoes/u1/itens/abc',
              'fields': mapaParaCampos({
                'titulo': 'Compra confirmada',
                'mensagem': 'Pedido nº X',
                'tipo': 'pedido',
                'lida': false,
                'criadoEm': DateTime.utc(2026, 11, 25, 12),
              }),
            },
          ],
        });
      });
      final lista = await FirestoreNotificacaoRepository(projectId: 'p', client: client).listar('u1');
      expect(lista.single.id, 'abc');
      expect(lista.single.titulo, 'Compra confirmada');
      expect(lista.single.criadoEm, DateTime.utc(2026, 11, 25, 12));
    });

    test('marcarLida altera só o campo "lida" e exige que exista', () async {
      final client = MockClient((req) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, endsWith('/notificacoes/u1/itens/abc'));
        expect(req.url.queryParameters['updateMask.fieldPaths'], 'lida');
        expect(req.url.queryParameters['currentDocument.exists'], 'true');
        return _json({
          'name': '$colecao/abc',
          'fields': mapaParaCampos({'titulo': 'T', 'mensagem': 'M', 'lida': true}),
        });
      });
      final n = await FirestoreNotificacaoRepository(projectId: 'p', client: client)
          .marcarLida('u1', 'abc');
      expect(n!.lida, isTrue);
    });

    test('marcarLida de notificação inexistente devolve null', () async {
      final client = MockClient((_) async => _json({'error': {'message': 'NOT_FOUND'}}, 404));
      expect(
        await FirestoreNotificacaoRepository(projectId: 'p', client: client).marcarLida('u1', 'x'),
        isNull,
      );
    });
  });

  group('App: NotificacaoController', () {
    Map<String, dynamic> notificacaoJson(String id, {bool lida = false}) => {
          'id': id,
          'titulo': 'Compra confirmada',
          'mensagem': 'Pedido nº $id',
          'tipo': 'pedido',
          'lida': lida,
          'criadoEm': '2026-11-25T12:00:00.000Z',
        };

    NotificacaoController controller(MockClient client, List<String> avisos) {
      return NotificacaoController(
        servico: NotificacaoService(apiUrl: 'http://api.teste', client: client),
      )
        ..uidAtual = (() => 'u1')
        ..mostrarNoSistema = ((titulo, corpo, tag) {
          avisos.add(tag);
          return true;
        });
    }

    test('receber mostra o aviso do sistema uma única vez', () {
      final avisos = <String>[];
      final c = controller(MockClient((_) async => _json({})), avisos);
      final n = NotificacaoModel.fromMap(notificacaoJson('7'));

      c.receber(n);
      c.receber(n); // mesma notificação de novo (ex.: resposta + WebSocket)

      expect(avisos, ['notificacao-7']);
      expect(c.naoLidas, 1);
      expect(c.itens, hasLength(1));
    });

    test('notificações antigas carregadas da API não viram aviso', () async {
      final avisos = <String>[];
      final client = MockClient((req) async {
        expect(req.url.toString(), 'http://api.teste/notificacoes/u1');
        return _json({
          'naoLidas': 1,
          'notificacoes': [notificacaoJson('1'), notificacaoJson('2', lida: true)],
        });
      });
      final c = controller(client, avisos);

      await c.carregar();
      c.receber(NotificacaoModel.fromMap(notificacaoJson('1')));

      expect(c.naoLidas, 1);
      expect(c.itens, hasLength(2));
      expect(avisos, isEmpty);
    });

    test('marcar todas como lidas zera o contador', () async {
      final client = MockClient((req) async {
        if (req.method == 'PUT') {
          expect(req.url.path, '/notificacoes/u1/lidas');
          return _json({'naoLidas': 0, 'notificacoes': [notificacaoJson('1', lida: true)]});
        }
        return _json({'naoLidas': 1, 'notificacoes': [notificacaoJson('1')]});
      });
      final c = controller(client, []);
      await c.carregar();
      expect(c.naoLidas, 1);

      await c.marcarTodasLidas();
      expect(c.naoLidas, 0);
      expect(c.itens.single.lida, isTrue);
    });

    test('canal em tempo real leva o uid do usuário', () {
      final s = NotificacaoService(apiUrl: 'http://localhost:8080');
      expect(s.wsUri('abc').toString(), 'ws://localhost:8080/ws?uid=abc');
    });
  });

  test('tempoRelativo', () {
    final agora = DateTime(2026, 11, 25, 12);
    expect(tempoRelativo(agora.subtract(const Duration(seconds: 20)), agora: agora), 'agora');
    expect(tempoRelativo(agora.subtract(const Duration(minutes: 5)), agora: agora), 'há 5 min');
    expect(tempoRelativo(agora.subtract(const Duration(hours: 3)), agora: agora), 'há 3 h');
    expect(tempoRelativo(agora.subtract(const Duration(days: 1)), agora: agora), 'ontem');
    expect(tempoRelativo(DateTime(2026, 1, 5), agora: agora), '05/01/2026');
  });
}

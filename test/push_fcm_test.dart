import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:equadras/services/notificacao_service.dart';

import '../bin/src/carrinho_repository.dart' show mapaParaCampos;
import '../bin/src/notificacao_repository.dart';
import '../bin/src/push_fcm.dart';

final _notificacao = Notificacao(
  id: 'n1',
  titulo: 'Compra confirmada',
  mensagem: 'Pedido nº ABC123 • 2 item(ns) • Total R\$ 240,00',
  tipo: 'pedido',
  pedidoId: 'abc123',
);

void main() {
  group('Mensagem do FCM', () {
    test('tem título, texto, dados do pedido e canal "pedidos" com prioridade alta', () {
      final m = mensagemFcm('TOKEN-1', _notificacao)['message'] as Map<String, dynamic>;
      expect(m['token'], 'TOKEN-1');
      expect(m['notification'], {
        'title': 'Compra confirmada',
        'body': 'Pedido nº ABC123 • 2 item(ns) • Total R\$ 240,00',
      });
      expect(m['data'], {'notificacaoId': 'n1', 'tipo': 'pedido', 'pedidoId': 'abc123'});
      final android = m['android'] as Map<String, dynamic>;
      expect(android['priority'], 'HIGH');
      expect((android['notification'] as Map)['channel_id'], canalPedidos);
      expect((android['notification'] as Map)['icon'], 'ic_notificacao');
    });
  });

  group('Envio pelo FCM', () {
    test('envia para todos os celulares e apaga o token inválido', () async {
      final dispositivos = MemoriaDispositivoRepository();
      await dispositivos.registrar('u1', 'bom');
      await dispositivos.registrar('u1', 'velho');
      await dispositivos.registrar('outro', 'de-outra-pessoa');

      final enviadosPara = <String>[];
      final client = MockClient((req) async {
        expect(req.url.toString(),
            'https://fcm.googleapis.com/v1/projects/proj/messages:send');
        final token = (jsonDecode(req.body) as Map)['message']['token'] as String;
        enviadosPara.add(token);
        if (token == 'velho') {
          return http.Response(
              '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}', 404);
        }
        return http.Response('{"name":"projects/proj/messages/1"}', 200);
      });

      final push = PushFcmService(projectId: 'proj', client: client, dispositivos: dispositivos);
      final enviados = await push.enviarParaUsuario('u1', _notificacao);

      expect(enviados, 1);
      expect(enviadosPara..sort(), ['bom', 'velho']);
      expect(await dispositivos.tokens('u1'), ['bom']); // "velho" foi removido
      expect(await dispositivos.tokens('outro'), ['de-outra-pessoa']);
    });

    test('erro temporário do FCM não apaga o token', () async {
      final dispositivos = MemoriaDispositivoRepository();
      await dispositivos.registrar('u1', 'tok');
      final client = MockClient((_) async => http.Response('{"error":{"status":"UNAVAILABLE"}}', 503));
      final push = PushFcmService(projectId: 'p', client: client, dispositivos: dispositivos);

      expect(await push.enviarParaUsuario('u1', _notificacao), 0);
      expect(await dispositivos.tokens('u1'), ['tok']);
    });

    test('usuário sem celular registrado: nada é enviado', () async {
      final client = MockClient((_) async => fail('não deveria chamar o FCM'));
      final push = PushFcmService(
          projectId: 'p', client: client, dispositivos: MemoriaDispositivoRepository());
      expect(await push.enviarParaUsuario('u1', _notificacao), 0);
    });
  });

  group('Tokens no Firestore', () {
    const base =
        'https://firestore.googleapis.com/v1/projects/p/databases/(default)/documents/dispositivos/u1/tokens';

    test('registrar grava em dispositivos/{uid}/tokens/{token}', () async {
      final client = MockClient((req) async {
        expect(req.method, 'PATCH');
        expect(req.url.toString(), '$base/abc%3A123');
        final campos = (jsonDecode(req.body) as Map)['fields'] as Map;
        expect(campos['token'], {'stringValue': 'abc:123'});
        expect(campos['plataforma'], {'stringValue': 'android'});
        return http.Response('{}', 200);
      });
      await FirestoreDispositivoRepository(projectId: 'p', client: client)
          .registrar('u1', 'abc:123');
    });

    test('tokens lista os documentos do usuário', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        return http.Response(
          jsonEncode({
            'documents': [
              {'name': '$base/t1', 'fields': mapaParaCampos({'token': 't1'})},
              {'name': '$base/t2', 'fields': mapaParaCampos({'token': 't2'})},
            ],
          }),
          200,
        );
      });
      expect(await FirestoreDispositivoRepository(projectId: 'p', client: client).tokens('u1'),
          ['t1', 't2']);
    });

    test('remover token inexistente não dá erro', () async {
      final client = MockClient((_) async => http.Response('{"error":{}}', 404));
      await FirestoreDispositivoRepository(projectId: 'p', client: client).remover('u1', 'x');
    });
  });

  group('App: registrar celular na API', () {
    test('registrarDispositivo faz POST /dispositivos/{uid}', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.teste/dispositivos/u1');
        expect(jsonDecode(req.body), {'token': 'tok', 'plataforma': 'android'});
        return http.Response('{"mensagem":"ok","pushAtivo":true}', 200);
      });
      await NotificacaoService(apiUrl: 'http://api.teste', client: client)
          .registrarDispositivo('u1', 'tok');
    });

    test('removerDispositivo faz DELETE /dispositivos/{uid}/{token}', () async {
      final client = MockClient((req) async {
        expect(req.method, 'DELETE');
        expect(req.url.toString(), 'http://api.teste/dispositivos/u1/tok');
        return http.Response('{}', 200);
      });
      await NotificacaoService(apiUrl: 'http://api.teste', client: client)
          .removerDispositivo('u1', 'tok');
    });
  });
}

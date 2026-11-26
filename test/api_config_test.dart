import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:equadras/services/api_config.dart';
import 'package:equadras/services/carrinho_service.dart';
import 'package:equadras/services/notificacao_service.dart';
import 'package:equadras/services/produto_service.dart';
import 'package:equadras/widgets/dialogo_endereco_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizar o endereço digitado', () {
    final casos = {
      '192.168.0.10': 'http://192.168.0.10:8080',
      '192.168.0.10:8080': 'http://192.168.0.10:8080',
      ' 192.168.0.10:9000 ': 'http://192.168.0.10:9000',
      'http://192.168.0.10:8080/': 'http://192.168.0.10:8080',
      'http://192.168.0.10:8080/produtos': 'http://192.168.0.10:8080',
      'http://192.168.0.10:8080/api/produtos/': 'http://192.168.0.10:8080/api',
      'localhost:8080': 'http://localhost:8080',
      'https://minha-api.run.app': 'https://minha-api.run.app',
      'https://minha-api.run.app:8443': 'https://minha-api.run.app:8443',
    };
    casos.forEach((digitado, esperado) {
      test('"$digitado" -> $esperado', () {
        expect(ApiConfig.normalizar(digitado), esperado);
      });
    });

    test('rejeita vazio e esquemas estranhos', () {
      expect(ApiConfig.normalizar(''), isNull);
      expect(ApiConfig.normalizar('   '), isNull);
      expect(ApiConfig.normalizar('ftp://192.168.0.10'), isNull);
    });
  });

  group('salvar e carregar no aparelho', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ApiConfig.restaurarPadrao();
    });

    test('salvar guarda o endereço normalizado e avisa quem escuta', () async {
      var avisos = 0;
      void ouvinte() => avisos++;
      ApiConfig.endereco.addListener(ouvinte);

      final salvo = await ApiConfig.salvar('10.0.0.5');

      ApiConfig.endereco.removeListener(ouvinte);
      expect(salvo, 'http://10.0.0.5:8080');
      expect(ApiConfig.url, 'http://10.0.0.5:8080');
      expect(ApiConfig.personalizado, isTrue);
      expect(avisos, 1);
      expect((await SharedPreferences.getInstance()).getString('api_url'),
          'http://10.0.0.5:8080');
    });

    test('carregar lê o que foi salvo antes (ex.: ao reabrir o app)', () async {
      SharedPreferences.setMockInitialValues({'api_url': 'http://172.16.1.20:8080'});
      await ApiConfig.carregar();
      expect(ApiConfig.url, 'http://172.16.1.20:8080');
    });

    test('restaurarPadrao volta para o endereço da compilação', () async {
      await ApiConfig.salvar('10.0.0.5');
      await ApiConfig.restaurarPadrao();
      expect(ApiConfig.url, ApiConfig.enderecoPadrao());
      expect(ApiConfig.personalizado, isFalse);
    });

    test('endereço inválido não é salvo', () async {
      expect(() => ApiConfig.salvar('ftp://x'), throwsFormatException);
      expect(ApiConfig.personalizado, isFalse);
    });

    test('os services passam a usar o endereço novo na hora', () async {
      await ApiConfig.salvar('192.168.1.50');
      expect(ProdutoService().baseUrl, 'http://192.168.1.50:8080/produtos');
      expect(ProdutoService().wsUri.toString(), 'ws://192.168.1.50:8080/ws');
      expect(CarrinhoService().apiUrl, 'http://192.168.1.50:8080');
      expect(NotificacaoService().wsUri('u1').toString(), 'ws://192.168.1.50:8080/ws?uid=u1');

      // Um service criado ANTES da troca também segue o endereço novo.
      final criadoAntes = ProdutoService();
      await ApiConfig.salvar('192.168.1.99:9000');
      expect(criadoAntes.baseUrl, 'http://192.168.1.99:9000/produtos');
    });
  });

  group('botão TESTAR', () {
    test('API do eQuadras respondendo -> ok', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), 'http://10.0.0.5:8080/produtos');
        return http.Response('[]', 200);
      });
      expect(await testarEnderecoApi('http://10.0.0.5:8080', client: client), isNull);
    });

    test('outro servidor que não devolve lista -> avisa', () async {
      final client = MockClient((_) async => http.Response('{"ola":"mundo"}', 200));
      expect(await testarEnderecoApi('http://10.0.0.5:8080', client: client),
          contains('não parece ser a API'));
    });

    test('sem conexão -> mensagem de ajuda', () async {
      final client = MockClient((_) async => throw http.ClientException('recusado'));
      expect(await testarEnderecoApi('http://10.0.0.5:8080', client: client),
          contains('Não foi possível conectar'));
    });
  });
}

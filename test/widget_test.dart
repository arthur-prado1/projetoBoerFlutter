import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equadras/model/quadra_model.dart';

void main() {
  test('QuadraModel converte corretamente para Map e do Map (Firestore)', () {
    final quadra = QuadraModel(
      id: 'quadra_123',
      nome: 'Quadra Society 1',
      tipo: 'Futebol Society',
      precoPorHora: 120.0,
      imagemUrl: 'https://exemplo.com/imagem.jpg',
    );

    // Testa conversão para o Firestore
    final map = quadra.toMap();
    expect(map['nome'], 'Quadra Society 1');
    expect(map['tipo'], 'Futebol Society');
    expect(map['precoPorHora'], 120.0);
    expect(map['imagemUrl'], 'https://exemplo.com/imagem.jpg');
    expect(map.containsKey('updatedAt'), isTrue);

    // Testa reconstrução do objeto a partir do Firestore
    final quadraCarregada = QuadraModel.fromMap(map, 'quadra_123');
    expect(quadraCarregada.id, 'quadra_123');
    expect(quadraCarregada.nome, 'Quadra Society 1');
    expect(quadraCarregada.tipo, 'Futebol Society');
    expect(quadraCarregada.precoPorHora, 120.0);
    expect(quadraCarregada.imagemUrl, 'https://exemplo.com/imagem.jpg');
  });

  testWidgets('Smoke test básico do app eQuadras', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('eQuadras'),
          ),
        ),
      ),
    );

    expect(find.text('eQuadras'), findsOneWidget);
  });
}

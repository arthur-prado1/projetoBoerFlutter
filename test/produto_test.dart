import 'package:flutter_test/flutter_test.dart';
import 'package:equadras/model/produto_model.dart';

void main() {
  test('ProdutoModel conversao toMap e fromMap', () {
    final produto = ProdutoModel(
      id: '1',
      nome: 'Bola de Tenis',
      categoria: 'Tenis',
      preco: 45.50,
      quantidade: 20,
    );

    final map = produto.toMap();
    expect(map['id'], '1');
    expect(map['nome'], 'Bola de Tenis');
    expect(map['categoria'], 'Tenis');
    expect(map['preco'], 45.50);
    expect(map['quantidade'], 20);

    final reconstruido = ProdutoModel.fromMap(map);
    expect(reconstruido.id, '1');
    expect(reconstruido.nome, 'Bola de Tenis');
    expect(reconstruido.categoria, 'Tenis');
    expect(reconstruido.preco, 45.50);
    expect(reconstruido.quantidade, 20);
  });

  test('ProdutoModel copyWith', () {
    final produto = ProdutoModel(
      id: '1',
      nome: 'Chuteira',
      categoria: 'Futebol',
      preco: 250.0,
      quantidade: 5,
    );

    final atualizado = produto.copyWith(preco: 220.0, quantidade: 4);
    expect(atualizado.id, '1');
    expect(atualizado.nome, 'Chuteira');
    expect(atualizado.preco, 220.0);
    expect(atualizado.quantidade, 4);
  });
}

import 'notificacao_model.dart';

double _lerDouble(dynamic v) =>
    v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.0);

int _lerInt(dynamic v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

/// Um produto dentro do carrinho, com os dados atuais vindos da API.
class ItemCarrinho {
  final String produtoId;
  final String nome;
  final String categoria;
  final String imagemUrl;
  final double precoUnitario;
  final int quantidade;
  final int estoque;
  final double subtotal;

  ItemCarrinho({
    required this.produtoId,
    required this.nome,
    required this.categoria,
    required this.imagemUrl,
    required this.precoUnitario,
    required this.quantidade,
    required this.estoque,
    required this.subtotal,
  });

  /// false quando o estoque caiu para menos do que está no carrinho.
  bool get estoqueSuficiente => quantidade <= estoque;

  factory ItemCarrinho.fromMap(Map<String, dynamic> map) => ItemCarrinho(
        produtoId: map['produtoId']?.toString() ?? '',
        nome: map['nome']?.toString() ?? '',
        categoria: map['categoria']?.toString() ?? '',
        imagemUrl: map['imagemUrl']?.toString() ?? '',
        precoUnitario: _lerDouble(map['precoUnitario']),
        quantidade: _lerInt(map['quantidade']),
        estoque: _lerInt(map['estoque']),
        subtotal: _lerDouble(map['subtotal']),
      );
}

/// Carrinho do usuário logado.
class CarrinhoModel {
  final List<ItemCarrinho> itens;
  final int quantidadeItens;
  final double total;

  const CarrinhoModel({
    this.itens = const [],
    this.quantidadeItens = 0,
    this.total = 0,
  });

  bool get vazio => itens.isEmpty;

  /// Pode finalizar se tem itens e todos têm estoque.
  bool get podeFinalizar => !vazio && itens.every((i) => i.estoqueSuficiente);

  int quantidadeDe(String produtoId) {
    for (final item in itens) {
      if (item.produtoId == produtoId) return item.quantidade;
    }
    return 0;
  }

  factory CarrinhoModel.fromMap(Map<String, dynamic> map) => CarrinhoModel(
        itens: (map['itens'] as List? ?? const [])
            .map((e) => ItemCarrinho.fromMap(e as Map<String, dynamic>))
            .toList(),
        quantidadeItens: _lerInt(map['quantidadeItens']),
        total: _lerDouble(map['total']),
      );
}

/// Resumo do pedido devolvido ao finalizar a compra.
class PedidoModel {
  final String id;

  /// Código curto mostrado ao usuário (ex.: "A1B2C3").
  final String codigo;
  final int quantidadeItens;
  final double total;

  /// Notificação "Compra confirmada" criada pela API (se houver).
  final NotificacaoModel? notificacao;

  PedidoModel({
    required this.id,
    String? codigo,
    required this.quantidadeItens,
    required this.total,
    this.notificacao,
  }) : codigo = codigo ?? id;

  factory PedidoModel.fromMap(Map<String, dynamic> map,
          {Map<String, dynamic>? notificacao}) =>
      PedidoModel(
        id: map['id']?.toString() ?? '',
        codigo: map['codigo']?.toString(),
        quantidadeItens: _lerInt(map['quantidadeItens']),
        total: _lerDouble(map['total']),
        notificacao:
            notificacao == null ? null : NotificacaoModel.fromMap(notificacao),
      );
}

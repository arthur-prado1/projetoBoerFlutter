class ProdutoModel {
  final String? id;
  final String nome;
  final String categoria;
  final double preco;
  final int quantidade;

  ProdutoModel({
    this.id,
    required this.nome,
    required this.categoria,
    required this.preco,
    required this.quantidade,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'categoria': categoria,
      'preco': preco,
      'quantidade': quantidade,
    };
  }

  factory ProdutoModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return ProdutoModel(
      id: id ?? map['id']?.toString(),
      nome: map['nome'] ?? '',
      categoria: map['categoria'] ?? '',
      preco: (map['preco'] is num)
          ? (map['preco'] as num).toDouble()
          : (double.tryParse(map['preco']?.toString() ?? '0') ?? 0.0),
      quantidade: (map['quantidade'] is num)
          ? (map['quantidade'] as num).toInt()
          : (int.tryParse(map['quantidade']?.toString() ?? '0') ?? 0),
    );
  }

  ProdutoModel copyWith({
    String? id,
    String? nome,
    String? categoria,
    double? preco,
    int? quantidade,
  }) {
    return ProdutoModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      preco: preco ?? this.preco,
      quantidade: quantidade ?? this.quantidade,
    );
  }
}

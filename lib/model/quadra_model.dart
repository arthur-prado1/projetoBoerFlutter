class QuadraModel {
  final String? id;
  final String nome;
  final String tipo;
  final double precoPorHora;
  final String imagemUrl;

  QuadraModel({
    this.id,
    required this.nome,
    required this.tipo,
    required this.precoPorHora,
    required this.imagemUrl,
  });

  // Converter para o Firestore (Salvar / Inserir / Atualizar)
  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'tipo': tipo,
      'precoPorHora': precoPorHora,
      'imagemUrl': imagemUrl,
      'updatedAt': DateTime.now(),
    };
  }

  // Criar o objeto a partir do Firestore (Ler / Listar)
  factory QuadraModel.fromMap(Map<String, dynamic> map, String docId) {
    return QuadraModel(
      id: docId,
      nome: map['nome'] ?? '',
      tipo: map['tipo'] ?? '',
      precoPorHora: (map['precoPorHora'] is num)
          ? (map['precoPorHora'] as num).toDouble()
          : 0.0,
      imagemUrl: map['imagemUrl'] ?? '',
    );
  }

  QuadraModel copyWith({
    String? id,
    String? nome,
    String? tipo,
    double? precoPorHora,
    String? imagemUrl,
  }) {
    return QuadraModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      precoPorHora: precoPorHora ?? this.precoPorHora,
      imagemUrl: imagemUrl ?? this.imagemUrl,
    );
  }
}

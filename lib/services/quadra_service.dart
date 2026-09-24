import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/quadra_model.dart';

class QuadraService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Coleção principal de quadras
  CollectionReference get _quadrasRef => _firestore.collection('quadras');

  // Criar (Create)
  Future<void> createQuadra(QuadraModel quadra) async {
    await _quadrasRef.add(quadra.toMap());
  }

  // Listar em tempo real (Read / Stream)
  Stream<List<QuadraModel>> streamQuadras() {
    return _quadrasRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return QuadraModel.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  // Atualizar (Update)
  Future<void> updateQuadra(QuadraModel quadra) async {
    if (quadra.id == null) {
      throw Exception("ID da quadra é obrigatório para atualização.");
    }
    await _quadrasRef.doc(quadra.id).update(quadra.toMap());
  }

  // Excluir (Delete)
  Future<void> deleteQuadra(String id) async {
    await _quadrasRef.doc(id).delete();
  }
}

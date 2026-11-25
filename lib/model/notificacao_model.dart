/// Notificação do usuário (ex.: "Compra confirmada").
class NotificacaoModel {
  final String id;
  final String titulo;
  final String mensagem;
  final String tipo;
  final String? pedidoId;
  final bool lida;
  final DateTime? criadoEm;

  NotificacaoModel({
    required this.id,
    required this.titulo,
    required this.mensagem,
    this.tipo = 'geral',
    this.pedidoId,
    this.lida = false,
    this.criadoEm,
  });

  NotificacaoModel copyWith({bool? lida}) => NotificacaoModel(
        id: id,
        titulo: titulo,
        mensagem: mensagem,
        tipo: tipo,
        pedidoId: pedidoId,
        lida: lida ?? this.lida,
        criadoEm: criadoEm,
      );

  factory NotificacaoModel.fromMap(Map<String, dynamic> map) => NotificacaoModel(
        id: map['id']?.toString() ?? '',
        titulo: map['titulo']?.toString() ?? '',
        mensagem: map['mensagem']?.toString() ?? '',
        tipo: map['tipo']?.toString() ?? 'geral',
        pedidoId: map['pedidoId']?.toString(),
        lida: map['lida'] == true,
        criadoEm: DateTime.tryParse(map['criadoEm']?.toString() ?? '')?.toLocal(),
      );
}

/// "agora", "há 5 min", "há 2 h", "ontem", "há 3 dias" ou a data.
String tempoRelativo(DateTime? quando, {DateTime? agora}) {
  if (quando == null) return '';
  final diferenca = (agora ?? DateTime.now()).difference(quando);
  if (diferenca.inMinutes < 1) return 'agora';
  if (diferenca.inMinutes < 60) return 'há ${diferenca.inMinutes} min';
  if (diferenca.inHours < 24) return 'há ${diferenca.inHours} h';
  if (diferenca.inDays == 1) return 'ontem';
  if (diferenca.inDays < 7) return 'há ${diferenca.inDays} dias';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(quando.day)}/${dois(quando.month)}/${quando.year}';
}

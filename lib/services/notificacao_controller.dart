import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/notificacao_model.dart';
import 'notificacao_service.dart';
import 'notificacao_sistema.dart';

/// Central de notificações do usuário logado.
///
/// - Lista e contador de não lidas (sininho), guardados pela API no Firestore.
/// - Recebe notificações novas na hora por WebSocket (/ws?uid=...).
/// - Mostra o aviso do sistema (Windows/navegador) quando chega uma nova.
class NotificacaoController extends ChangeNotifier {
  static final NotificacaoController instancia = NotificacaoController();

  NotificacaoService servico;

  /// Quem é o usuário atual. Pode ser trocado (ex.: testes, prévia sem login).
  String? Function() uidAtual = () => FirebaseAuth.instance.currentUser?.uid;

  /// Mostra o aviso do sistema. Pode ser trocado nos testes.
  bool Function(String titulo, String corpo, String tag) mostrarNoSistema =
      (titulo, corpo, tag) => NotificacaoSistema.mostrar(titulo, corpo, tag: tag);

  NotificacaoController({NotificacaoService? servico})
      : servico = servico ?? NotificacaoService();

  List<NotificacaoModel> _itens = [];
  int _naoLidas = 0;
  bool _carregando = false;
  String? _erro;
  String? _uid;

  /// IDs já exibidos no sistema (evita aviso duplicado).
  final Set<String> _jaAvisadas = {};

  WebSocketChannel? _canal;
  StreamSubscription? _assinatura;
  Timer? _timerReconexao;
  bool _ativo = false;

  List<NotificacaoModel> get itens => List.unmodifiable(_itens);
  int get naoLidas => _naoLidas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  PermissaoNotificacao get permissaoSistema => NotificacaoSistema.permissao;

  /// Começa a acompanhar as notificações do usuário logado. Pode ser chamado
  /// por várias telas: só conecta uma vez (ou de novo se trocou de usuário).
  void iniciar() {
    final uid = uidAtual();
    if (uid == null || uid.isEmpty) return;
    if (_ativo && uid == _uid) return;
    parar();
    _uid = uid;
    _ativo = true;
    _itens = [];
    _naoLidas = 0;
    carregar(silencioso: true);
    _conectar();
  }

  void parar() {
    _ativo = false;
    _timerReconexao?.cancel();
    _assinatura?.cancel();
    _canal?.sink.close();
    _canal = null;
    _assinatura = null;
  }

  Future<void> _conectar() async {
    final uid = _uid;
    if (!_ativo || uid == null) return;
    final canal = servico.conectarTempoReal(uid);
    try {
      await canal.ready;
    } catch (_) {
      _reconectarDepois();
      return;
    }
    if (!_ativo || uid != _uid) {
      canal.sink.close();
      return;
    }
    _canal = canal;
    _assinatura = canal.stream.listen(
      (mensagem) {
        if (mensagem is String) _aoReceberMensagem(mensagem);
      },
      onDone: _reconectarDepois,
      onError: (_) => _reconectarDepois(),
      cancelOnError: true,
    );
    // Pega o que chegou enquanto estava desconectado.
    carregar(silencioso: true);
  }

  void _reconectarDepois() {
    _assinatura?.cancel();
    _assinatura = null;
    _canal = null;
    if (!_ativo) return;
    _timerReconexao?.cancel();
    _timerReconexao = Timer(const Duration(seconds: 3), _conectar);
  }

  void _aoReceberMensagem(String mensagem) {
    try {
      final data = jsonDecode(mensagem);
      if (data is Map<String, dynamic> &&
          data['evento'] == 'notificacao' &&
          data['notificacao'] is Map<String, dynamic>) {
        receber(NotificacaoModel.fromMap(data['notificacao'] as Map<String, dynamic>));
      }
    } catch (_) {
      // Mensagem de outro tipo (ex.: produto); ignorada aqui.
    }
  }

  /// Coloca a notificação no topo da lista e mostra o aviso do sistema
  /// (uma única vez por notificação).
  void receber(NotificacaoModel n, {bool avisarNoSistema = true}) {
    if (n.id.isEmpty) return;
    final existe = _itens.any((i) => i.id == n.id);
    if (!existe) {
      _itens = [n, ..._itens];
      if (!n.lida) _naoLidas++;
      notifyListeners();
    }
    if (avisarNoSistema && !n.lida && _jaAvisadas.add(n.id)) {
      mostrarNoSistema(n.titulo, n.mensagem, 'notificacao-${n.id}');
    }
  }

  Future<void> carregar({bool silencioso = false}) async {
    final uid = _uid ?? uidAtual();
    if (uid == null || uid.isEmpty) return;
    if (!silencioso) {
      _carregando = true;
      _erro = null;
      notifyListeners();
    }
    try {
      _aplicar(await servico.listar(uid));
      _erro = null;
    } catch (e) {
      if (!silencioso) _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  void _aplicar(ListaNotificacoes lista) {
    _itens = lista.itens;
    _naoLidas = lista.naoLidas;
    // O que já existia quando a lista foi carregada não vira aviso do sistema.
    _jaAvisadas.addAll(lista.itens.map((n) => n.id));
  }

  Future<void> marcarLida(NotificacaoModel n) async {
    final uid = _uid ?? uidAtual();
    if (uid == null || n.lida) return;
    // Atualiza na tela na hora; a API confirma em seguida.
    _itens = [for (final i in _itens) i.id == n.id ? i.copyWith(lida: true) : i];
    _naoLidas = _itens.where((i) => !i.lida).length;
    notifyListeners();
    try {
      _aplicar(await servico.marcarLida(uid, n.id));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> marcarTodasLidas() async {
    final uid = _uid ?? uidAtual();
    if (uid == null || _naoLidas == 0) return;
    _itens = [for (final i in _itens) i.copyWith(lida: true)];
    _naoLidas = 0;
    notifyListeners();
    try {
      _aplicar(await servico.marcarTodasLidas(uid));
      notifyListeners();
    } catch (_) {}
  }

  /// Pede ao navegador permissão para os avisos do sistema.
  Future<PermissaoNotificacao> ativarAvisosDoSistema() async {
    final resultado = await NotificacaoSistema.pedirPermissao();
    notifyListeners();
    return resultado;
  }
}

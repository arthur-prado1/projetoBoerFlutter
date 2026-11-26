import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../widgets/sino_notificacoes.dart';
import 'api_config.dart';
import 'notificacao_controller.dart';
import 'notificacao_service.dart';

/// Canal do Android para os avisos de pedido (o mesmo que a API usa no FCM).
const String canalPedidosId = 'pedidos';

/// Recebe push com o app fechado ou em segundo plano.
/// Quando a mensagem tem título/texto, o próprio Android já mostra a
/// notificação na barra; aqui só garantimos o Firebase inicializado.
@pragma('vm:entry-point')
Future<void> pushEmSegundoPlano(RemoteMessage mensagem) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Push no celular pelo Firebase Cloud Messaging (FCM) — só no app Android.
///
/// 1. Pede permissão de notificação (Android 13+).
/// 2. Pega o token do aparelho e registra na API (POST /dispositivos/{uid}).
/// 3. Com o app aberto, mostra o aviso com flutter_local_notifications
///    (o Android não mostra push sozinho com o app em primeiro plano).
/// 4. Ao tocar na notificação, abre o app no painel de notificações.
class PushService {
  static final PushService instancia = PushService();

  /// Usado para navegar quando o usuário toca na notificação.
  static final GlobalKey<NavigatorState> navegador = GlobalKey<NavigatorState>();

  /// Só o app Android recebe push do FCM neste projeto.
  static bool get suportado =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  NotificacaoService servico = NotificacaoService();

  PushService() {
    // Trocou o endereço da API: registra este celular na API nova.
    ApiConfig.endereco.addListener(() {
      final uid = _uid;
      final token = _token;
      if (suportado && uid != null && token != null) {
        servico.registrarDispositivo(uid, token).catchError((_) {});
      }
    });
  }

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localPronto = false;
  String? _uid;
  String? _token;
  final List<StreamSubscription> _assinaturas = [];

  /// Registra este celular para o usuário logado. Pode ser chamado por
  /// várias telas: só faz o trabalho uma vez por usuário.
  Future<void> iniciar() async {
    if (!suportado) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == _uid) return;
    await parar();
    _uid = uid;

    try {
      await _configurarNotificacoesLocais();

      final messaging = FirebaseMessaging.instance;
      final permissao = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (permissao.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: permissão de notificação negada pelo usuário.');
        return;
      }

      _token = await messaging.getToken();
      if (_token != null) {
        await servico.registrarDispositivo(uid, _token!);
        debugPrint('Push: celular registrado na API.');
      }

      _assinaturas
        ..add(messaging.onTokenRefresh.listen((novo) {
          _token = novo;
          servico.registrarDispositivo(uid, novo).catchError((_) {});
        }))
        ..add(FirebaseMessaging.onMessage.listen(_aoReceberComAppAberto))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((_) => _abrirPainel()));

      // App aberto a partir de uma notificação (estava fechado).
      if (await messaging.getInitialMessage() != null) _abrirPainel();
    } catch (e) {
      // Sem internet/API fora do ar: o app segue funcionando sem push.
      debugPrint('Push: não foi possível registrar o celular: $e');
      _uid = null;
    }
  }

  /// Para de receber push neste celular (chamar no logout).
  Future<void> parar() async {
    for (final a in _assinaturas) {
      await a.cancel();
    }
    _assinaturas.clear();
    final uid = _uid;
    final token = _token;
    _uid = null;
    if (suportado && uid != null && token != null) {
      try {
        await servico.removerDispositivo(uid, token);
      } catch (_) {}
    }
  }

  Future<void> _configurarNotificacoesLocais() async {
    if (_localPronto) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notificacao'),
      ),
      onDidReceiveNotificationResponse: (_) => _abrirPainel(),
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          canalPedidosId,
          'Pedidos',
          description: 'Confirmação das suas compras no eQuadras',
          importance: Importance.high,
        ));
    _localPronto = true;
  }

  void _aoReceberComAppAberto(RemoteMessage mensagem) {
    final n = mensagem.notification;
    if (n != null) {
      _local.show(
        id: (mensagem.messageId ?? '${DateTime.now().millisecondsSinceEpoch}').hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            canalPedidosId,
            'Pedidos',
            channelDescription: 'Confirmação das suas compras no eQuadras',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notificacao',
            color: Color(0xFF4CAF50),
          ),
        ),
      );
    }
    // Atualiza o sininho também.
    NotificacaoController.instancia.carregar(silencioso: true);
  }

  /// Leva o usuário para os produtos e abre o painel de notificações.
  void _abrirPainel() {
    final nav = navegador.currentState;
    if (nav == null || FirebaseAuth.instance.currentUser == null) return;
    nav.pushNamedAndRemoveUntil('/produtos', (rota) => false);
    Future.delayed(const Duration(milliseconds: 600), () {
      final contexto = navegador.currentContext;
      if (contexto != null && contexto.mounted) abrirPainelNotificacoes(contexto);
    });
  }
}

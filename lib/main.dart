import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart'; // Será gerado pelo FlutterFire
import 'services/api_config.dart';
import 'services/push_service.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/quadras_screen.dart';
import 'screens/produtos_screen.dart';
import 'screens/carrinho_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); 

  // Inicializa o Firebase com as opções geradas
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Endereço da API salvo no aparelho (configurável dentro do app)
  await ApiConfig.carregar();

  // Push no celular (FCM): tratamento com o app fechado / em segundo plano
  if (PushService.suportado) {
    FirebaseMessaging.onBackgroundMessage(pushEmSegundoPlano);
  }

  runApp(const EQuadrasApp());
}

class EQuadrasApp extends StatelessWidget {
  const EQuadrasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eQuadras',
      // Permite abrir o app no painel de notificações ao tocar num push
      navigatorKey: PushService.navegador,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
          case '/splash':
            return MaterialPageRoute(settings: settings, builder: (_) => const SplashScreen());
          case '/login':
            return MaterialPageRoute(settings: settings, builder: (_) => const LoginScreen());
          case '/cadastro':
            return MaterialPageRoute(settings: settings, builder: (_) => const RegisterScreen());
          case '/home':
          case '/perfil':
            // AUTH GUARD REAL DO FIREBASE
            if (FirebaseAuth.instance.currentUser == null) {
              return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
            }
            return MaterialPageRoute(settings: settings, builder: (_) => const HomeScreen());
          case '/quadras':
            if (FirebaseAuth.instance.currentUser == null) {
              return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
            }
            return MaterialPageRoute(settings: settings, builder: (_) => const QuadrasScreen());
          case '/produtos':
            // Login pelo Firebase; dados dos produtos pela API REST
            if (FirebaseAuth.instance.currentUser == null) {
              return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
            }
            return MaterialPageRoute(settings: settings, builder: (_) => const ProdutosScreen());
          case '/carrinho':
            // Carrinho do usuário logado (uid do Firebase), guardado pela API
            if (FirebaseAuth.instance.currentUser == null) {
              return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
            }
            return MaterialPageRoute(settings: settings, builder: (_) => const CarrinhoScreen());
          default:
            return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
        }
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

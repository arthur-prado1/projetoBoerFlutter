import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; // Será gerado pelo FlutterFire

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/quadras_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); 

  // Inicializa o Firebase com as opções geradas
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const EQuadrasApp());
}

class EQuadrasApp extends StatelessWidget {
  const EQuadrasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eQuadras',
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
          default:
            return MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen());
        }
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

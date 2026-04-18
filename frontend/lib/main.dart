import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  usePathUrlStrategy();
  runApp(
    ChangeNotifierProvider(create: (_) => AuthProvider(), child: const ReApp()),
  );
}

class ReApp extends StatelessWidget {
  const ReApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RE Follow-Up Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B5BD6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        // Flutter Web calls this with the actual browser path on first load
        if (settings.name != null &&
            settings.name!.startsWith('/reset-password')) {
          return MaterialPageRoute(
            builder: (_) => const ResetPasswordScreen(),
            settings: settings,
          );
        }
        return MaterialPageRoute(
          builder: (_) => const _RootRouter(),
          settings: settings,
        );
      },
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _wasLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final loggedIn = auth.isLoggedIn;

    if (_wasLoggedIn && !loggedIn) {
      final expired = auth.sessionExpired;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.popUntil((r) => r.isFirst);
        if (expired) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Sessão expirada. Faça login novamente.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          auth.consumeSessionExpired();
        }
      });
    }
    _wasLoggedIn = loggedIn;

    return loggedIn ? const HomeScreen() : const LoginScreen();
  }
}

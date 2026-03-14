import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

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
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('pt'),
      ],
      locale: const Locale('pt'),
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

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}

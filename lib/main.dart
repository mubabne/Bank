import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_page.dart';
import 'login_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://edjhxbjcagkedxnvxdev.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_rUHHevvZQthQKCZmrtp8rA_jZVZfpNt',
    ),
  );

  runApp(const BankMailApp());
}

class BankMailApp extends StatelessWidget {
  const BankMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mailance',
      theme: AppTheme.light,

      home: const _AuthGate(),
      routes: {
        LoginPage.routeName: (context) => const LoginPage(),
        DashboardPage.routeName: (context) => const DashboardPage(),
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        return auth.currentSession == null
            ? const LoginPage()
            : const DashboardPage();
      },
    );
  }
}

// You technically don't need this anymore,
// but keep it if other files currently reference MyApp.
class MyApp extends BankMailApp {
  const MyApp({super.key});
}

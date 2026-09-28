import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'screens/company_picker_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/agenda_controller.dart';
import 'state/auth_controller.dart';
import 'state/cash_controller.dart';
import 'state/checkout_controller.dart';
import 'state/my_controller.dart';
import 'theme/barbora_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin esto, DateFormat con el locale «es» revienta en tiempo de ejecución.
  await initializeDateFormatting('es');

  final session = Session();
  final api = ApiClient(session: session);

  runApp(BarboraApp(session: session, api: api));
}

class BarboraApp extends StatelessWidget {
  const BarboraApp({super.key, required this.session, required this.api});

  final Session session;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(
          create: (_) => AuthController(api: api, session: session)..bootstrap(),
        ),
        ChangeNotifierProvider(create: (_) => AgendaController(api: api)),
        ChangeNotifierProvider(create: (_) => MyController(api: api)),
        ChangeNotifierProvider(create: (_) => CashController(api: api)),
        ChangeNotifierProvider(create: (_) => CheckoutController(api: api)),
      ],
      child: MaterialApp(
        title: 'Barbora',
        debugShowCheckedModeBanner: false,
        theme: BarboraTheme.light(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

/// Decide qué pantalla toca según el estado de la sesión. Es el único sitio
/// donde se navega entre acceso, elección de barbería y la app en sí.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<AuthController>().stage;

    return switch (stage) {
      AuthStage.loading => const SplashScreen(),
      AuthStage.loggedOut => const LoginScreen(),
      AuthStage.choosingCompany => const CompanyPickerScreen(),
      AuthStage.subscriptionBlocked => const SubscriptionBlockedScreen(),
      AuthStage.ready => const HomeShell(),
    };
  }
}

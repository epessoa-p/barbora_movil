import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/brand_logo.dart';
import 'agenda_screen.dart';
import 'cash_screen.dart';
import 'commissions_screen.dart';
import 'profile_screen.dart';

/// El armazón con la barra inferior. Las pestañas dependen de lo que el plan
/// incluya y de si el usuario tiene ficha de barbero: sin ficha, «Comisiones»
/// no tiene sentido y no se muestra.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final me = auth.me;

    final tabs = <_Tab>[
      const _Tab(
        label: 'Agenda',
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today,
        screen: AgendaScreen(),
      ),
      // La caja depende del plan y del permiso: un barbero que solo atiende no
      // tiene por qué ver el cajón.
      if ((me?.hasModule('caja') ?? false) && (me?.can('cash.view') ?? false))
        const _Tab(
          label: 'Caja',
          icon: Icons.point_of_sale_outlined,
          activeIcon: Icons.point_of_sale,
          screen: CashScreen(),
        ),
      if ((me?.hasStaffProfile ?? false) && (me?.hasModule('comisiones') ?? false))
        const _Tab(
          label: 'Comisiones',
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments,
          screen: CommissionsScreen(),
        ),
      const _Tab(
        label: 'Perfil',
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        screen: ProfileScreen(),
      ),
    ];

    // Si el plan cambia mientras la app está abierta, el índice podría quedar
    // apuntando a una pestaña que ya no existe.
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      // La agenda trae su propia cabecera oscura con el día; las demás usan
      // esta, para no repetir dos barras.
      appBar: index == 0
          ? null
          : AppBar(
              flexibleSpace: const DecoratedBox(
                decoration: BoxDecoration(gradient: BarboraTheme.inkGradient),
              ),
              title: Text(tabs[index].label),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Text(
                      auth.company?.name ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: BarboraTheme.titanium.withValues(alpha: .8),
                      ),
                    ),
                  ),
                ),
              ],
            ),

      body: SafeArea(
        top: index != 0,
        bottom: false,
        child: IndexedStack(
          index: index,
          children: tabs.map((t) => t.screen).toList(),
        ),
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: BarboraTheme.border)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: tabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.activeIcon),
                  label: t.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;
}

/// Pantalla de arranque, mientras se lee el token guardado.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BarboraTheme.inkGradient),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandLogo.mark(height: 74),
              SizedBox(height: 26),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: BarboraTheme.copperLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuando la suscripción de la barbería no deja entrar. No se deja la app en
/// blanco: se explica y se ofrece reintentar o salir.
class SubscriptionBlockedScreen extends StatelessWidget {
  const SubscriptionBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BarboraTheme.inkGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.credit_card_off_outlined,
                    size: 58,
                    color: BarboraTheme.copperLight,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Suscripción vencida',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    auth.error ??
                        'La suscripción de la barbería está vencida. '
                            'Habla con el administrador para renovarla.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BarboraTheme.titanium.withValues(alpha: .85),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 30),
                  FilledButton.icon(
                    onPressed: auth.busy
                        ? null
                        : () => context.read<AuthController>().refreshMe(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Volver a comprobar'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.read<AuthController>().logout(),
                    style: TextButton.styleFrom(foregroundColor: BarboraTheme.titanium),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

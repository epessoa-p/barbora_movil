import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/appointment.dart';
import '../models/me.dart';
import '../state/agenda_controller.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/error_view.dart';
import 'agenda_screen.dart';
import 'barbers_screen.dart';
import 'cash_screen.dart';
import 'checkout_screen.dart';
import 'clients_screen.dart';
import 'commissions_screen.dart';
import 'new_appointment_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';
import 'services_screen.dart';

/// Las secciones de la app y las acciones rápidas, con lo que exige cada una.
///
/// Es el único sitio donde se decide qué ve quién: el menú lateral, el botón
/// flotante y la sección de arranque leen de aquí. Cada entrada pide dos
/// cosas, igual que el menú de la web: que el plan incluya el módulo y que el
/// usuario tenga el permiso. El servidor lo vuelve a comprobar en cada
/// llamada; esto solo evita enseñar puertas que no abren.
class AppMenu {
  const AppMenu(this.me);

  final Me? me;

  bool _allows(String module, String permission) =>
      (me?.hasModule(module) ?? false) && (me?.can(permission) ?? false);

  bool get agenda => _allows('agenda', 'appointments.view');

  bool get newAppointment => _allows('agenda', 'appointments.create');

  bool get clients => _allows('clientes', 'clients.view');

  /// Los servicios se consultan dentro del módulo de agenda.
  bool get services => _allows('agenda', 'services.view');

  /// Gestionar barberos (personal): administrativo, solo por permiso.
  bool get barbers => me?.can('personal.view') ?? false;

  /// Un barbero que solo atiende no tiene por qué ver el cajón.
  bool get cash => _allows('caja', 'cash.view');

  bool get checkout => _allows('pos', 'sales.create');

  /// «Lo mío»: sin ficha de personal no hay comisiones que enseñar.
  bool get commissions => (me?.hasStaffProfile ?? false) && (me?.hasModule('comisiones') ?? false);

  bool get reports => _allows('estadisticas', 'reports.view');

  // El perfil ya no es una sección del menú: se abre con el botón de arriba a
  // la derecha (ver HomeShell).
  List<Section> get sections => [
        if (agenda) Section.agenda,
        if (clients) Section.clients,
        if (services) Section.services,
        if (barbers) Section.barbers,
        if (cash) Section.cash,
        if (commissions) Section.commissions,
        if (reports) Section.reports,
      ];
}

enum Section {
  agenda('Agenda', Icons.calendar_today_outlined, Icons.calendar_today),
  clients('Clientes', Icons.people_outline, Icons.people),
  services('Servicios', Icons.design_services_outlined, Icons.design_services),
  barbers('Barberos', Icons.content_cut_outlined, Icons.content_cut),
  cash('Caja', Icons.point_of_sale_outlined, Icons.point_of_sale),
  commissions('Comisiones', Icons.payments_outlined, Icons.payments),
  reports('Reportes', Icons.bar_chart_outlined, Icons.bar_chart);

  const Section(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;

  Widget get screen => switch (this) {
        Section.agenda => const AgendaScreen(),
        Section.clients => const ClientsScreen(),
        Section.services => const ServicesScreen(),
        Section.barbers => const BarbersScreen(),
        Section.cash => const CashScreen(),
        Section.commissions => const CommissionsScreen(),
        Section.reports => const ReportsScreen(),
      };
}

/// El armazón: barra superior, menú lateral y la sección elegida.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Section? _current;

  /// Secciones ya abiertas: se conservan montadas para no recargar al volver,
  /// pero no se monta ninguna hasta que se visita (cada una pide sus datos).
  final Set<Section> _visited = {};

  void _go(Section section) {
    Navigator.of(context).pop(); // cierra el menú
    setState(() => _current = section);
  }

  Future<void> _newAppointment({bool fromDrawer = false}) async {
    if (fromDrawer) Navigator.of(context).pop();

    final agenda = context.read<AgendaController>();

    final created = await Navigator.of(context).push<Appointment>(
      MaterialPageRoute(builder: (_) => NewAppointmentScreen(day: agenda.day)),
    );

    if (created == null || !mounted) return;

    // Se lleva a la agenda al día de la cita, para verla en su sitio.
    final menu = AppMenu(context.read<AuthController>().me);
    if (menu.agenda) {
      setState(() => _current = Section.agenda);
      agenda.goToDay(created.startsAt);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cita reservada: ${created.client?.fullName ?? 'cliente'} · ${created.timeRange}',
        ),
      ),
    );
  }

  void _checkout() {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  /// El perfil se abre como pantalla propia (ya no es sección del menú). Como
  /// ProfileScreen no trae Scaffold, se envuelve en uno con su barra.
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: BarboraTheme.inkSoft,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Mi perfil'),
          ),
          body: const ProfileScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final menu = AppMenu(auth.me);
    final sections = menu.sections;

    // Si el plan o el rol cambian con la app abierta, la sección actual puede
    // dejar de existir: se vuelve a la primera disponible (o ninguna).
    final current = sections.contains(_current)
        ? _current!
        : (sections.isEmpty ? null : sections.first);
    if (current != null) _visited.add(current);

    return Scaffold(
      appBar: AppBar(
        // Color liso y no degradado: debajo de la agenda va su cabecera
        // oscura, y dos degradados seguidos dejan una costura visible.
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current?.label ?? 'Barbora'),
            if (auth.company != null)
              Text(
                auth.company!.name,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: BarboraTheme.titanium.withValues(alpha: .8),
                ),
              ),
          ],
        ),
        actions: [
          // Acceso al perfil: círculo con icono de persona, arriba a la derecha.
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              onPressed: _openProfile,
              tooltip: 'Mi perfil',
              icon: const CircleAvatar(
                radius: 15,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),

      drawer: _AppDrawer(
        menu: menu,
        current: current,
        onSection: _go,
        onNewAppointment: () => _newAppointment(fromDrawer: true),
        onCheckout: _checkout,
      ),

      floatingActionButton: current == Section.agenda && menu.newAppointment
          ? FloatingActionButton.extended(
              onPressed: _newAppointment,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva cita', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,

      body: SafeArea(
        top: false,
        child: current == null
            ? const EmptyView(
                icon: Icons.lock_outline,
                title: 'Sin accesos',
                subtitle: 'Tu cuenta no tiene módulos habilitados. Habla con tu administrador.',
              )
            : IndexedStack(
                index: sections.indexOf(current),
                children: [
                  for (final s in sections)
                    _visited.contains(s) ? s.screen : const SizedBox.shrink(),
                ],
              ),
      ),
    );
  }
}

/// El menú lateral. Solo enseña lo que el plan y los permisos dejan usar.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.menu,
    required this.current,
    required this.onSection,
    required this.onNewAppointment,
    required this.onCheckout,
  });

  final AppMenu menu;
  final Section? current;
  final ValueChanged<Section> onSection;
  final VoidCallback onNewAppointment;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final me = auth.me;
    final hasActions = menu.newAppointment || menu.checkout;

    return Drawer(
      backgroundColor: BarboraTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
      ),
      child: Column(
        children: [
          _DrawerHeader(
            name: me?.personal?.fullName ?? me?.user.name ?? '',
            subtitle: me?.personal?.cargo ?? me?.role?.name ?? '',
            company: auth.company?.name ?? '',
            logoUrl: auth.company?.logoUrl,
            initials: me?.personal?.initials ?? _initialsOf(me?.user.name ?? ''),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: [
                if (hasActions) ...[
                  const _GroupLabel('Acciones rápidas'),
                  if (menu.newAppointment)
                    _DrawerItem(
                      icon: Icons.event_available_outlined,
                      label: 'Nueva cita',
                      highlight: true,
                      onTap: onNewAppointment,
                    ),
                  if (menu.checkout)
                    _DrawerItem(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Cobrar',
                      highlight: true,
                      onTap: onCheckout,
                    ),
                  const SizedBox(height: 10),
                ],

                const _GroupLabel('Secciones'),
                for (final s in menu.sections)
                  _DrawerItem(
                    icon: s == current ? s.activeIcon : s.icon,
                    label: s.label,
                    selected: s == current,
                    onTap: () => onSection(s),
                  ),
              ],
            ),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Column(
              children: [
                if (auth.companies.length > 1)
                  _DrawerItem(
                    icon: Icons.swap_horiz,
                    label: 'Cambiar de barbería',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.read<AuthController>().changeCompany();
                    },
                  ),
                _DrawerItem(
                  icon: Icons.logout,
                  label: 'Cerrar sesión',
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a escribir tu correo y contraseña.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (ok == true) await auth.logout();
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.name,
    required this.subtitle,
    required this.company,
    required this.logoUrl,
    required this.initials,
  });

  final String name;
  final String subtitle;
  final String company;

  /// Logo de la barbería; si es null, se cae a las iniciales del personal.
  final String? logoUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.only(topRight: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar: el logo de la barbería si lo subió; si no, las iniciales.
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: logoUrl == null ? BarboraTheme.copperGradient : null,
                  color: logoUrl == null ? null : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: logoUrl != null
                    ? Image.network(
                        logoUrl!,
                        fit: BoxFit.cover,
                        width: 46,
                        height: 46,
                        errorBuilder: (_, _, _) => _InitialsAvatar(initials: initials),
                      )
                    : Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: BarboraTheme.copperLight, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (company.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 15, color: BarboraTheme.titanium.withValues(alpha: .8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: BarboraTheme.titanium.withValues(alpha: .9),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Respaldo del avatar cuando el logo no carga: las iniciales sobre cobre.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: BarboraTheme.copperGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: BarboraTheme.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Las acciones rápidas llevan el icono en cobre: son lo que se hace, no
  /// adónde se va.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? BarboraTheme.copperDark
        : highlight
            ? BarboraTheme.copper
            : BarboraTheme.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        onTap: onTap,
        dense: true,
        selected: selected,
        selectedTileColor: BarboraTheme.copper.withValues(alpha: .10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: color, size: 22),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? BarboraTheme.copperDark : BarboraTheme.ink,
          ),
        ),
      ),
    );
  }
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

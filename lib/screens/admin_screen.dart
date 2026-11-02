import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../widgets/admin_widgets.dart';
import 'barbers_screen.dart';
import 'branches_screen.dart';
import 'cajas_admin_screen.dart';
import 'company_profile_screen.dart';
import 'home_shell.dart';
import 'payment_methods_screen.dart';
import 'reports_screen.dart';

/// «Administración»: un cuadro por cada apartado que el usuario puede ver.
///
/// Qué cuadros salen lo decide [AppMenu], igual que el menú lateral: plan y
/// permiso. El servidor lo vuelve a comprobar en cada llamada.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final menu = AppMenu(context.watch<AuthController>().me);

    final cards = <_AdminCard>[
      if (menu.companyProfile)
        _AdminCard('Mi empresa', 'Nombre, contacto y comprobante', Icons.storefront_outlined,
            const Color(0xFFB7793F), (_) => const CompanyProfileScreen()),
      if (menu.reports)
        _AdminCard('Reportes', 'Ventas, servicios, ganancias…', Icons.bar_chart, const Color(0xFF0EA5E9),
            (_) => const AdminPage(title: 'Reportes', child: ReportsScreen())),
      if (menu.barbers)
        _AdminCard('Personal', 'Barberos y demás personal', Icons.badge_outlined, const Color(0xFFE11D48),
            (_) => const AdminPage(title: 'Personal', child: BarbersScreen())),
      if (menu.branches)
        _AdminCard('Sucursales', 'Locales de la barbería', Icons.store_mall_directory_outlined,
            const Color(0xFF0D9488), (_) => const BranchesScreen()),
      if (menu.cajas)
        _AdminCard('Cajas', 'Cajas registradoras', Icons.point_of_sale_outlined, const Color(0xFF16A34A),
            (_) => const CajasAdminScreen()),
      if (menu.paymentMethods)
        _AdminCard('Métodos de pago', 'Cómo cobra la barbería', Icons.credit_card, const Color(0xFF7C3AED),
            (_) => const PaymentMethodsScreen()),
    ];

    return AdminPage(
      title: 'Administración',
      child: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .98,
        children: [for (final c in cards) _AdminTileCard(card: c)],
      ),
    );
  }
}

class _AdminCard {
  const _AdminCard(this.title, this.subtitle, this.icon, this.color, this.builder);

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

class _AdminTileCard extends StatelessWidget {
  const _AdminTileCard({required this.card});

  final _AdminCard card;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: card.builder)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: card.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(card.icon, color: card.color, size: 23),
              ),
              const Spacer(),
              Text(
                card.title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -.3),
              ),
              const SizedBox(height: 3),
              Text(
                card.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

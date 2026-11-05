import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'accounts_screen.dart';
import 'expense_categories_screen.dart';
import 'expenses_screen.dart';
import 'home_shell.dart';
import 'purchases_screen.dart';
import 'suppliers_screen.dart';

/// Una pestaña de abajo: su etiqueta, iconos y pantalla.
class HubTab {
  const HubTab(this.label, this.icon, this.selectedIcon, this.builder);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

/// Una sección con barra inferior: cada pestaña se monta al visitarla y se
/// conserva. Con una sola pestaña, no hay barra.
class HubScreen extends StatefulWidget {
  const HubScreen({super.key, required this.tabs});

  final List<HubTab> tabs;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  int _index = 0;
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final index = _index < tabs.length ? _index : 0;
    _visited.add(index);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < tabs.length; i++) _visited.contains(i) ? tabs[i].builder() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final t in tabs)
                  NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
              ],
            ),
    );
  }
}

/// Gastos (sección propia del menú), cada tipo en su pestaña sin repetirse:
/// generales (por defecto: comida, pasajes…), a proveedores, a personal y
/// servicios básicos (alquiler, luz, agua, hosting… lo mensual o anual).
class ExpensesHubScreen extends StatelessWidget {
  const ExpensesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HubScreen(tabs: [
      HubTab('Gastos', Icons.receipt_long_outlined, Icons.receipt_long, () => const ExpensesScreen(group: 'general')),
      HubTab('Proveedores', Icons.local_shipping_outlined, Icons.local_shipping,
          () => const ExpensesScreen(group: 'proveedor')),
      HubTab('Personal', Icons.badge_outlined, Icons.badge, () => const ExpensesScreen(group: 'personal')),
      HubTab('Servicios', Icons.home_work_outlined, Icons.home_work, () => const ExpensesScreen(group: 'basicos')),
    ]);
  }
}

/// Finanzas: Cuentas (por defecto) y Categorías de gasto, según permisos.
class FinanceHubScreen extends StatelessWidget {
  const FinanceHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final menu = AppMenu(context.watch<AuthController>().me);

    return HubScreen(tabs: [
      if (menu.accounts)
        HubTab('Cuentas', Icons.account_balance_outlined, Icons.account_balance, () => const AccountsScreen()),
      if (menu.expenseCategories)
        HubTab('Categorías', Icons.label_outline, Icons.label, () => const ExpenseCategoriesScreen()),
    ]);
  }
}

/// Compras: Compras (por defecto) y Proveedores, según permisos.
class PurchasesHubScreen extends StatelessWidget {
  const PurchasesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final menu = AppMenu(context.watch<AuthController>().me);

    return HubScreen(tabs: [
      if (menu.purchases)
        HubTab('Compras', Icons.shopping_bag_outlined, Icons.shopping_bag, () => const PurchasesScreen()),
      if (menu.suppliers)
        HubTab('Proveedores', Icons.local_shipping_outlined, Icons.local_shipping, () => const SuppliersScreen()),
    ]);
  }
}

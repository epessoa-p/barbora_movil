import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'catalog_screen.dart';
import 'home_shell.dart';
import 'service_categories_screen.dart';
import 'services_screen.dart';

/// Las pestañas de abajo de Servicios.
enum ServicesTab { services, categories, catalog }

/// La sección Servicios con su barra inferior: Servicios (por defecto),
/// Categorías y Catálogo. Cada pestaña sale solo si el permiso la deja; con
/// una sola, no hay barra.
class ServicesHubScreen extends StatefulWidget {
  const ServicesHubScreen({super.key});

  @override
  State<ServicesHubScreen> createState() => _ServicesHubScreenState();
}

class _ServicesHubScreenState extends State<ServicesHubScreen> {
  ServicesTab _tab = ServicesTab.services;

  /// Pestañas ya abiertas: se montan al visitarlas y se conservan.
  final Set<ServicesTab> _visited = {ServicesTab.services};

  @override
  Widget build(BuildContext context) {
    final menu = AppMenu(context.watch<AuthController>().me);
    final tabs = [
      ServicesTab.services,
      if (menu.serviceCategories) ServicesTab.categories,
      if (menu.catalog) ServicesTab.catalog,
    ];
    final tab = tabs.contains(_tab) ? _tab : ServicesTab.services;
    _visited.add(tab);

    return Scaffold(
      body: IndexedStack(
        index: tabs.indexOf(tab),
        children: [
          for (final t in tabs)
            !_visited.contains(t)
                ? const SizedBox.shrink()
                : switch (t) {
                    ServicesTab.services => const ServicesScreen(),
                    ServicesTab.categories => const ServiceCategoriesScreen(),
                    ServicesTab.catalog => const CatalogScreen(),
                  },
        ],
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: tabs.indexOf(tab),
              onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
              destinations: [
                for (final t in tabs)
                  switch (t) {
                    ServicesTab.services => const NavigationDestination(
                        icon: Icon(Icons.design_services_outlined),
                        selectedIcon: Icon(Icons.design_services),
                        label: 'Servicios',
                      ),
                    ServicesTab.categories => const NavigationDestination(
                        icon: Icon(Icons.category_outlined),
                        selectedIcon: Icon(Icons.category),
                        label: 'Categorías',
                      ),
                    ServicesTab.catalog => const NavigationDestination(
                        icon: Icon(Icons.qr_code_2_outlined),
                        selectedIcon: Icon(Icons.qr_code_2),
                        label: 'Catálogo',
                      ),
                  },
              ],
            ),
    );
  }
}

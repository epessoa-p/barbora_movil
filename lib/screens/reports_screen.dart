import 'package:flutter/material.dart';

import '../theme/barbora_theme.dart';
import 'report_detail_screen.dart';

/// La portada de Reportes: una tarjeta por reporte. Al tocar, se abre su vista.
///
/// La lista es fija (los tipos los define el backend en ReportController::TYPES);
/// toda la sección ya está detrás del módulo «estadisticas» y del permiso
/// `reports.view`, así que si se ve, los reportes están disponibles.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  static const _reports = <_ReportCard>[
    _ReportCard('ventas', 'Ventas', 'Cuánto se vendió y cómo se cobró', Icons.receipt_long, Color(0xFF0EA5E9)),
    _ReportCard('servicios', 'Servicios', 'Qué servicios se piden y citas', Icons.content_cut, Color(0xFF0D9488)),
    _ReportCard('barberos', 'Barberos', 'Producción y comisiones por barbero', Icons.badge_outlined, Color(0xFFE11D48)),
    _ReportCard('productos', 'Productos', 'Rotación y margen de productos', Icons.inventory_2_outlined, Color(0xFF7C3AED)),
    _ReportCard('clientes', 'Clientes', 'Nuevos, recurrentes y top', Icons.people_outline, Color(0xFFDB2777)),
    _ReportCard('ganancias', 'Ganancias', 'Ingresos, gastos y neto', Icons.savings_outlined, Color(0xFF16A34A)),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: .98,
      children: [for (final r in _reports) _ReportTile(card: r)],
    );
  }
}

class _ReportCard {
  const _ReportCard(this.type, this.title, this.subtitle, this.icon, this.color);

  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.card});

  final _ReportCard card;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportDetailScreen(type: card.type, title: card.title),
          ),
        ),
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
                style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

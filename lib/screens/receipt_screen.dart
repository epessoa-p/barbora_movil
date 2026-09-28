import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/sale.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// El comprobante de una venta, para enseñárselo al cliente.
///
/// No se imprime: un barbero no lleva impresora en el bolsillo. Se ve en
/// pantalla y se puede copiar como texto para mandarlo por WhatsApp, que es lo
/// que se hace de verdad en una barbería.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final company = auth.company;
    final symbol = company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: BarboraTheme.inkGradient),
        ),
        title: const Text('Comprobante'),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copy(context, company, symbol),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (company != null) ...[
            _ShopHeader(company: company),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BarboraTheme.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF16A34A),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$symbol ${sale.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sale.number,
                  style: const TextStyle(
                    color: BarboraTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  DateFormat("d 'de' MMMM, HH:mm", 'es').format(sale.soldAt),
                  style: const TextStyle(color: BarboraTheme.titanium, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _Block(
            title: 'Detalle',
            children: [
              ...sale.items.map(
                (item) => _Row(
                  label: item.description,
                  sublabel: item.quantity == 1
                      ? null
                      : '${_number(item.quantity)} × $symbol ${item.unitPrice.toStringAsFixed(2)}',
                  value: '$symbol ${item.total.toStringAsFixed(2)}',
                ),
              ),
              const Divider(height: 1),
              _Row(
                label: 'Subtotal',
                value: '$symbol ${sale.subtotal.toStringAsFixed(2)}',
              ),
              if (sale.discount > 0)
                _Row(
                  label: 'Descuento',
                  value: '−$symbol ${sale.discount.toStringAsFixed(2)}',
                ),
              if (sale.tip > 0)
                _Row(label: 'Propina', value: '$symbol ${sale.tip.toStringAsFixed(2)}'),
              _Row(
                label: 'Total',
                value: '$symbol ${sale.total.toStringAsFixed(2)}',
                strong: true,
              ),
            ],
          ),

          if (sale.payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Block(
              title: 'Pago',
              children: sale.payments
                  .map((p) => _Row(
                        label: p.paymentMethodLabel,
                        value: '$symbol ${p.amount.toStringAsFixed(2)}',
                      ))
                  .toList(),
            ),
          ],

          if (sale.clientName != null || sale.personalName != null) ...[
            const SizedBox(height: 12),
            _Block(
              title: 'Atención',
              children: [
                if (sale.clientName != null)
                  _Row(label: 'Cliente', value: sale.clientName!),
                if (sale.personalName != null)
                  _Row(label: 'Atendió', value: sale.personalName!),
              ],
            ),
          ],

          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => _copy(context, company, symbol),
            icon: const Icon(Icons.copy_all_outlined, size: 19),
            label: const Text('Copiar para enviar'),
          ),
        ],
      ),
    );
  }

  /// El comprobante como texto, listo para pegar en WhatsApp.
  void _copy(BuildContext context, Company? company, String symbol) {
    final lines = <String>[
      if (company != null && company.name.isNotEmpty) company.name.toUpperCase(),
      ?company?.taxLine,
      if (company?.address != null && company!.address!.isNotEmpty) company.address!,
      '',
      'Comprobante ${sale.number}',
      DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es').format(sale.soldAt),
      '',
      ...sale.items.map((i) => i.quantity == 1
          ? '· ${i.description}  $symbol ${i.total.toStringAsFixed(2)}'
          : '· ${i.description} (${_number(i.quantity)})  $symbol ${i.total.toStringAsFixed(2)}'),
      '',
      if (sale.discount > 0) 'Descuento: −$symbol ${sale.discount.toStringAsFixed(2)}',
      if (sale.tip > 0) 'Propina: $symbol ${sale.tip.toStringAsFixed(2)}',
      'TOTAL: $symbol ${sale.total.toStringAsFixed(2)}',
      if (sale.personalName != null) '',
      if (sale.personalName != null) 'Te atendió: ${sale.personalName}',
      '',
      // El pie lo define la barbería: sus redes, el horario, una promoción.
      company?.footer ?? '¡Gracias por tu visita!',
      if (company?.phone != null && company!.phone!.isNotEmpty) company.phone!,
    ];

    Clipboard.setData(ClipboardData(text: lines.join('\n')));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comprobante copiado.')),
    );
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

/// Encabezado con los datos de la barbería: logo, nombre, NIT y dirección.
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.company});

  final Company company;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Logo(url: company.logoUrl, name: company.name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    company.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                  ),
                  if (company.taxLine != null)
                    Text(
                      company.taxLine!,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                  if (company.address != null && company.address!.isNotEmpty)
                    Text(
                      company.address!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.titanium),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El logo de la barbería, o sus iniciales si no subió ninguno o no carga.
///
/// No carga cuando el móvil no llega al servidor por la URL del logo; en vez
/// de un icono roto se ven las iniciales, que también identifican.
class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.name});

  final String? url;
  final String name;

  static const double _size = 54;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: BarboraTheme.copperGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: _size,
        height: _size,
        color: Colors.white,
        child: Image.network(
          url!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: BarboraTheme.textMuted,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.sublabel,
    this.strong = false,
  });

  final String label;
  final String value;
  final String? sublabel;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: strong ? 15 : 13.5,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                    color: strong ? BarboraTheme.ink : BarboraTheme.textMuted,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: const TextStyle(fontSize: 11, color: BarboraTheme.titanium),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: strong ? 17 : 13.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

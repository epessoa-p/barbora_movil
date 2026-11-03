import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/profit_report.dart';
import '../models/report.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

const _green = Color(0xFF16A34A);

/// Reporte de ganancias: cuánto queda de lo vendido después del costo de los
/// productos y las comisiones. Se filtra por ventas de productos, servicios o
/// ambos, y las ventas rápidas (productos sin ficha, sin costo conocido) se
/// pueden unir o dejar aparte. Los datos vienen de `GET /reports/profit`.
class ProfitReportScreen extends StatefulWidget {
  const ProfitReportScreen({super.key});

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen> {
  ProfitReportView? _report;
  ApiException? _error;
  bool _loading = true;

  String _preset = 'mes';
  String _scope = 'ambos';
  bool _quick = false;

  /// Pestaña de productos: false = más ganancia, true = margen bajo.
  bool _lowMargin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/reports/profit', query: {
        'preset': _preset,
        'scope': _scope,
        'quick': _quick ? '1' : '0',
      });

      if (!mounted) return;
      setState(() => _report = ProfitReportView.fromJson(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Ganancias'),
      ),
      body: _body(symbol),
    );
  }

  Widget _body(String symbol) {
    if (_loading && _report == null) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    final r = _report!;
    final money = _Money(symbol);
    final products = _lowMargin ? r.lowMarginProducts : r.topProducts;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          ReportPeriodChips(
            period: r.period,
            onPick: (p) {
              if (p != _preset) _set(() => _preset = p);
            },
          ),
          const SizedBox(height: 12),

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ambos', label: Text('Ambos')),
              ButtonSegment(value: 'ventas', label: Text('Ventas')),
              ButtonSegment(value: 'servicios', label: Text('Servicios')),
            ],
            selected: {_scope},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _set(() => _scope = s.first),
          ),
          const SizedBox(height: 8),

          // Las ventas rápidas no tienen costo: si se unen, inflan el margen.
          Card(
            child: SwitchListTile(
              value: _quick,
              onChanged: (v) => _set(() => _quick = v),
              activeThumbColor: BarboraTheme.copper,
              title: const Text('Unir ventas rápidas',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text(
                'Productos no cargados: no tienen costo conocido.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(color: BarboraTheme.copper, minHeight: 2),
            ),

          if (!_quick && r.quickCount > 0 && r.scope != 'servicios')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hay ${r.quickCount} venta(s) rápida(s) por ${money(r.quickRevenue)} fuera del cálculo.',
                style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
              ),
            ),
          const SizedBox(height: 12),

          _SummaryCard(totals: r.summary, money: money),

          if (r.expenses != null && r.net != null) ...[
            const SizedBox(height: 10),
            _ResultCard(expenses: r.expenses!, net: r.net!, money: money),
          ],

          if (r.scope != 'servicios') ...[
            const SizedBox(height: 12),
            _BlockCard(
              title: 'Ventas',
              icon: Icons.inventory_2_outlined,
              totals: r.products,
              costLabel: 'Costo de productos',
              money: money,
            ),
          ],
          if (r.scope != 'ventas') ...[
            const SizedBox(height: 12),
            _BlockCard(
              title: 'Servicios',
              icon: Icons.content_cut,
              totals: r.services,
              costLabel: 'Comisiones',
              money: money,
            ),
          ],

          if (r.estimated)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Algunos costos se estimaron con el costo actual del producto.',
                style: TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted),
              ),
            ),

          const _Header('POR DÍA'),
          if (r.daily.isEmpty)
            const _Empty('Sin ventas en este periodo.')
          else
            Card(
              child: Column(
                children: [
                  for (final d in r.daily)
                    ListTile(
                      dense: true,
                      title: Text(
                        _capitalize(DateFormat('EEE d MMM', 'es').format(d.date)),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('Vendido ${money(d.totals.revenue)}'),
                      trailing: _ProfitText(d.totals, money),
                    ),
                ],
              ),
            ),

          if (r.scope != 'servicios') ...[
            const _Header('PRODUCTOS'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Más ganancia')),
                ButtonSegment(value: true, label: Text('Margen bajo')),
              ],
              selected: {_lowMargin},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _lowMargin = s.first),
            ),
            const SizedBox(height: 8),
            if (products.isEmpty)
              const _Empty('Sin productos vendidos.')
            else
              Card(
                child: Column(
                  children: [
                    for (final p in products)
                      ListTile(
                        dense: true,
                        title: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${_qty(p.quantity)} u · vendido ${money(p.totals.revenue)}'
                          '${p.quick ? ' · venta rápida' : ''}',
                        ),
                        trailing: _ProfitText(p.totals, money),
                      ),
                  ],
                ),
              ),
          ],

          const _Header('VENTAS'),
          if (r.sales.isEmpty)
            const _Empty('Sin ventas en este periodo.')
          else
            Card(
              child: Column(
                children: [
                  for (final s in r.sales)
                    ListTile(
                      dense: true,
                      title: Text(
                        'Venta ${s.number}${s.client != null ? ' · ${s.client}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${DateFormat('d MMM HH:mm', 'es').format(s.soldAt)} · '
                        'vendido ${money(s.totals.revenue)} · costo ${money(s.totals.cost)}',
                      ),
                      trailing: _ProfitText(s.totals, money),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
}

/// Formatea importes con el símbolo de la empresa.
class _Money {
  const _Money(this.symbol);

  final String symbol;

  String call(double v) => '$symbol ${v.toStringAsFixed(2)}';
}

String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

Color _profitColor(double v) => v < 0 ? BarboraTheme.copperDark : _green;

/// Los atajos de periodo de un reporte (Hoy, Esta semana, …), en fila.
class ReportPeriodChips extends StatelessWidget {
  const ReportPeriodChips({super.key, required this.period, required this.onPick});

  final ReportPeriodInfo period;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: period.presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = period.presets[i];
          final selected = p.key == period.preset;
          return ChoiceChip(
            label: Text(p.label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onPick(p.key),
            selectedColor: BarboraTheme.ink,
            backgroundColor: BarboraTheme.surface,
            side: BorderSide(color: selected ? BarboraTheme.ink : BarboraTheme.border),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : BarboraTheme.textMuted,
            ),
          );
        },
      ),
    );
  }
}

/// Ganancia grande arriba; margen, ingresos y costo debajo.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals, required this.money});

  final ProfitTotals totals;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GANANCIA',
              style: TextStyle(
                  fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: BarboraTheme.titanium)),
          const SizedBox(height: 4),
          Text(
            money(totals.profit),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -.8,
              color: totals.profit < 0 ? BarboraTheme.copperLight : Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Figure('Margen', _pct(totals.marginPct)),
              _Figure('Ingresos', money(totals.revenue)),
              _Figure('Costo', money(totals.cost)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: BarboraTheme.titanium)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Lo que queda después de los gastos del periodo (de Finanzas).
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.expenses, required this.net, required this.money});

  final double expenses;
  final double net;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gastos del periodo',
                      style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
                  Text(money(expenses), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Neto', style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
                Text(money(net),
                    style: TextStyle(fontWeight: FontWeight.w800, color: _profitColor(net))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.title,
    required this.icon,
    required this.totals,
    required this.costLabel,
    required this.money,
  });

  final String title;
  final IconData icon;
  final ProfitTotals totals;
  final String costLabel;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: BarboraTheme.copper),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                Text('${totals.sales} venta(s)',
                    style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            _Row('Ingresos', money(totals.revenue)),
            _Row(costLabel, money(totals.cost)),
            _Row(
              'Ganancia (${_pct(totals.marginPct)})',
              money(totals.profit),
              color: _profitColor(totals.profit),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w800 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: weight))),
          Text(value, style: TextStyle(fontSize: 13.5, fontWeight: weight, color: color)),
        ],
      ),
    );
  }
}

/// Ganancia y margen alineados a la derecha de una fila.
class _ProfitText extends StatelessWidget {
  const _ProfitText(this.totals, this.money);

  final ProfitTotals totals;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(money(totals.profit),
            style: TextStyle(fontWeight: FontWeight.w800, color: _profitColor(totals.profit))),
        Text(_pct(totals.marginPct),
            style: const TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 0, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: BarboraTheme.textMuted,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(text, style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13)),
      ),
    );
  }
}

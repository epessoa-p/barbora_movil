import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/sale.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'receipt_screen.dart';

/// Periodos del historial. Cubren lo que se mira de verdad: lo de hoy para
/// cuadrar, ayer para revisar, y la semana o el mes para hacerse una idea.
enum SalesPeriod {
  today('Hoy'),
  yesterday('Ayer'),
  week('7 días'),
  month('Mes'),
  custom('Rango');

  const SalesPeriod(this.label);

  final String label;

  /// Primer y último día (inclusive).
  (DateTime, DateTime) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    return switch (this) {
      SalesPeriod.today => (today, today),
      SalesPeriod.yesterday => (
          today.subtract(const Duration(days: 1)),
          today.subtract(const Duration(days: 1)),
        ),
      SalesPeriod.week => (today.subtract(const Duration(days: 6)), today),
      SalesPeriod.month => (DateTime(today.year, today.month), today),
      // El rango lo elige el usuario: ver _SalesScreenState._range.
      SalesPeriod.custom => (today, today),
    };
  }

  bool get singleDay => this == SalesPeriod.today || this == SalesPeriod.yesterday;
}

/// Historial de ventas: lo cobrado en el periodo, cada venta con su
/// comprobante, y anulación para quien tenga permiso.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  SalesPeriod _period = SalesPeriod.today;
  List<SaleRow> _sales = const [];
  SalesSummary _summary = const SalesSummary();
  ApiException? _error;
  bool _loading = true;

  /// Venta que se está abriendo, para mostrar el indicador en su fila.
  int? _opening;

  /// Fechas elegidas en «Rango».
  DateTimeRange? _range;

  /// Elige el rango; si se cancela, queda el periodo que había.
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: _range ?? DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      helpText: 'Ventas entre',
      saveText: 'Ver',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _range = picked;
      _period = SalesPeriod.custom;
    });
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final (from, to) = _period == SalesPeriod.custom && _range != null
        ? (_range!.start, _range!.end)
        : _period.range(DateTime.now());

    try {
      final body = await context.read<ApiClient>().get(
        '/sales',
        // Un rango largo puede tener muchas ventas: se pide el máximo.
        query: {'from': _date(from), 'to': _date(to), if (_period == SalesPeriod.custom) 'limit': '200'},
      );
      if (!mounted) return;
      setState(() {
        _sales = (body['data'] as List? ?? [])
            .map((e) => SaleRow.fromJson(e as Map<String, dynamic>))
            .toList();
        _summary = SalesSummary.fromJson(body['summary'] as Map<String, dynamic>? ?? const {});
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SaleRow row) async {
    setState(() => _opening = row.id);

    try {
      final body = await context.read<ApiClient>().get('/sales/${row.id}');
      if (!mounted) return;

      final sale = Sale.fromJson(body['data'] as Map<String, dynamic>);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReceiptScreen(sale: sale, allowCancel: true)),
      );

      // Pudo anularse desde el comprobante: se refresca la lista y el resumen.
      if (mounted) _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<SalesPeriod>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final p in SalesPeriod.values) ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_period},
              onSelectionChanged: (s) {
                if (s.first == SalesPeriod.custom) {
                  _pickRange();
                  return;
                }
                setState(() => _period = s.first);
                _load();
              },
            ),
          ),
        ),
        // El rango elegido, y tocarlo para cambiarlo.
        if (_period == SalesPeriod.custom && _range != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InkWell(
              onTap: _pickRange,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 18, color: BarboraTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('d MMM y', 'es').format(_range!.start)} — ${DateFormat('d MMM y', 'es').format(_range!.end)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Text('Cambiar', style: TextStyle(color: BarboraTheme.copper, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        if (!_loading && _error == null)
          _SummaryCard(summary: _summary, symbol: symbol),
        Expanded(child: _body(symbol)),
      ],
    );
  }

  Widget _body(String symbol) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    if (_sales.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 60),
            EmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'Sin ventas en este periodo',
              subtitle: 'Lo que se cobre aparecerá aquí.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _sales.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, i) => _SaleTile(
          sale: _sales[i],
          symbol: symbol,
          showDate: !_period.singleDay && !(_period == SalesPeriod.custom && _range?.duration == Duration.zero),
          opening: _opening == _sales[i].id,
          onTap: _opening == null ? () => _open(_sales[i]) : null,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.symbol});

  final SalesSummary summary;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _Stat(value: '$symbol ${summary.total.toStringAsFixed(2)}', label: 'cobrado', flex: 2),
          _Stat(value: '${summary.count}', label: summary.count == 1 ? 'venta' : 'ventas'),
          if (summary.tips > 0)
            _Stat(value: '$symbol ${summary.tips.toStringAsFixed(2)}', label: 'propinas', flex: 2),
          if (summary.cancelled > 0)
            _Stat(
              value: '${summary.cancelled}',
              label: summary.cancelled == 1 ? 'anulada' : 'anuladas',
              color: const Color(0xFFF87171),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.flex = 1, this.color});

  final String value;
  final String label;
  final int flex;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: -.4,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(color: BarboraTheme.titanium.withValues(alpha: .7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.sale,
    required this.symbol,
    required this.showDate,
    required this.opening,
    required this.onTap,
  });

  final SaleRow sale;
  final String symbol;
  final bool showDate;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat(showDate ? "d MMM · HH:mm" : 'HH:mm', 'es').format(sale.soldAt);
    final cancelled = sale.isCancelled;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sale.number,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          when,
                          style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                        ),
                        if (cancelled) ...[
                          const SizedBox(width: 8),
                          const Text(
                            'ANULADA',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFDC2626),
                              letterSpacing: .8,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Qué se cobró: servicio, producto o ambos.
                    if (sale.services > 0 || sale.products > 0) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (sale.services > 0)
                            const _KindBadge(label: 'Servicio', icon: Icons.content_cut, color: Color(0xFF0D9488)),
                          if (sale.products > 0)
                            const _KindBadge(label: 'Producto', icon: Icons.inventory_2_outlined, color: Color(0xFF7C3AED)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      [
                        sale.client ?? 'Sin cliente',
                        if (sale.personal != null) sale.personal!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    if (sale.methods.isNotEmpty)
                      Text(
                        sale.methods.join(', '),
                        style: const TextStyle(fontSize: 11.5, color: BarboraTheme.titanium),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$symbol ${sale.total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                  color: cancelled ? BarboraTheme.textMuted : null,
                ),
              ),
              const SizedBox(width: 2),
              opening
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: BarboraTheme.copper),
                      ),
                    )
                  : const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Distintivo de lo que se cobró en la venta: «Servicio» o «Producto».
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

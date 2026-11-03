import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/analysis_report.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);

/// Análisis: cómo va el negocio contra antes, sin elegir fechas.
///
/// Pestañas Servicios / Ventas / Compras (si el plan tiene inventario) / Top,
/// cada una en monto o cantidad: semana y mes contra el mismo tramo anterior,
/// la semana por día junto a la anterior, las últimas 8 semanas y los últimos
/// 6 meses. Top: lo más fuerte del mes. Datos de `GET /reports/analysis`.
class AnalysisReportScreen extends StatefulWidget {
  const AnalysisReportScreen({super.key});

  @override
  State<AnalysisReportScreen> createState() => _AnalysisReportScreenState();
}

class _AnalysisReportScreenState extends State<AnalysisReportScreen> {
  static const _titles = {'servicios': 'Servicios', 'ventas': 'Ventas', 'compras': 'Compras'};

  AnalysisReportView? _report;
  ApiException? _error;
  bool _loading = true;

  /// Monto (true) o cantidad.
  bool _amount = true;

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
      final body = await context.read<ApiClient>().get('/reports/analysis');
      if (!mounted) return;
      setState(() => _report = AnalysisReportView.fromJson(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AppBar _appBar({PreferredSizeWidget? bottom}) => AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Análisis'),
        bottom: bottom,
      );

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    final r = _report;

    if (r == null) {
      return Scaffold(
        appBar: _appBar(),
        body: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : const Center(child: CircularProgressIndicator(color: BarboraTheme.copper)),
      );
    }

    final keys = [for (final k in _titles.keys) if (r.series.containsKey(k)) k];

    return DefaultTabController(
      length: keys.length + 1,
      child: Scaffold(
        appBar: _appBar(
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: BarboraTheme.copper,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              for (final k in keys) Tab(text: _titles[k]),
              const Tab(text: 'Top'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final k in keys) _page(_seriesTab(k, r, symbol)),
            _page(_topTab(r, symbol)),
          ],
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) => RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text('Monto (${context.read<AuthController>().company?.symbol ?? ''})')),
                const ButtonSegment(value: false, label: Text('Cantidad')),
              ],
              selected: {_amount},
              onSelectionChanged: (s) => setState(() => _amount = s.first),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(color: BarboraTheme.copper),
              ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  String _fmt(double v, String symbol) {
    if (_amount) return '$symbol ${NumberFormat('#,##0.00', 'en').format(v)}';
    return v == v.roundToDouble() ? NumberFormat('#,##0', 'en').format(v) : v.toStringAsFixed(2);
  }

  List<Widget> _seriesTab(String key, AnalysisReportView r, String symbol) {
    final pair = r.series[key]!;
    final m = _amount ? pair.amount : pair.count;

    return [
      Row(
        children: [
          Expanded(child: _PeriodCard(label: 'Semana', value: _fmt(m.week, symbol), change: m.weekChange)),
          const SizedBox(width: 10),
          Expanded(child: _PeriodCard(label: 'Mes', value: _fmt(m.month, symbol), change: m.monthChange)),
        ],
      ),
      const SizedBox(height: 6),
      const Text(
        'Contra el mismo tramo anterior: si hoy es miércoles, de lunes a miércoles.',
        style: TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted),
      ),
      const SizedBox(height: 14),
      _ChartCard(
        title: 'Semana anterior vs. actual (por día)',
        legend: true,
        labels: [for (final d in m.daily) d.label],
        current: [for (final d in m.daily) d.current],
        previous: [for (final d in m.daily) d.previous],
      ),
      const SizedBox(height: 14),
      _ChartCard(
        title: 'Comparativa semanal (últimas 8)',
        labels: [for (final p in m.weeks) p.label],
        current: [for (final p in m.weeks) p.value],
      ),
      const SizedBox(height: 14),
      _ChartCard(
        title: 'Comparativa mensual (últimos 6)',
        labels: [for (final p in m.months) p.label],
        current: [for (final p in m.months) p.value],
      ),
      if (key == 'compras' && !_amount)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('En compras, la cantidad es el número de compras.',
              style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
        ),
    ];
  }

  List<Widget> _topTab(AnalysisReportView r, String symbol) {
    const blocks = {
      'services': ('Servicios', Icons.content_cut),
      'products': ('Productos', Icons.inventory_2_outlined),
      'clients': ('Clientes', Icons.people_outline),
    };

    return [
      Text('Lo más fuerte de este mes, por ${_amount ? 'monto' : 'cantidad'}.',
          style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
      const SizedBox(height: 10),
      for (final MapEntry(key: key, value: (title, icon)) in blocks.entries) ...[
        _TopCard(
          title: title,
          icon: icon,
          rows: ([...?r.top[key]]..sort((a, b) => (_amount ? b.amount.compareTo(a.amount) : b.count.compareTo(a.count))))
              .take(10)
              .toList(),
          value: (row) => _amount ? row.amount : row.count,
          fmt: (v) => _fmt(v, symbol),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.value, this.change});

  final String label;
  final String value;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final c = change;
    final up = (c ?? 0) >= 0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: BarboraTheme.textMuted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _green)),
            ),
            const SizedBox(height: 4),
            if (c == null)
              const Text('Sin datos antes', style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted))
            else
              Row(
                children: [
                  Icon(up ? Icons.trending_up : Icons.trending_down, size: 16, color: up ? _green : _red),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${c > 0 ? '+' : ''}${c.toStringAsFixed(c.abs() >= 100 ? 0 : 1)}% vs anterior',
                      style: TextStyle(fontSize: 12, color: up ? _green : _red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Barras: una serie, o dos lado a lado (anterior clara, actual verde).
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.labels,
    required this.current,
    this.previous,
    this.legend = false,
  });

  final String title;
  final List<String> labels;
  final List<double> current;
  final List<double>? previous;
  final bool legend;

  static final _prevColor = _green.withValues(alpha: .3);

  String _axis(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final prev = previous;
    final all = [...current, ...?prev];
    final top = all.fold<double>(0, (a, b) => b > a ? b : a);
    final maxY = top <= 0 ? 1.0 : top * 1.2;
    final width = prev == null ? 18.0 : 9.0;

    Widget dot(Color c, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(fontSize: 12.5)),
          ],
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (legend) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 16, children: [dot(_prevColor, 'Semana anterior'), dot(_green, 'Semana actual')]),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (_) => const FlLine(color: BarboraTheme.border, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: maxY / 4,
                        getTitlesWidget: (v, meta) => v == meta.max
                            ? const SizedBox.shrink()
                            : Text(_axis(v), style: const TextStyle(fontSize: 9.5, color: BarboraTheme.textMuted)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final i = v.round();
                          return Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(i >= 0 && i < labels.length ? labels[i] : '',
                                style: const TextStyle(fontSize: 9.5, color: BarboraTheme.textMuted)),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(enabled: false),
                  barGroups: [
                    for (var i = 0; i < current.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 3,
                        barRods: [
                          if (prev != null)
                            BarChartRodData(
                              toY: prev[i],
                              color: _prevColor,
                              width: width,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          BarChartRodData(
                            toY: current[i],
                            color: _green,
                            width: width,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.title, required this.icon, required this.rows, required this.value, required this.fmt});

  final String title;
  final IconData icon;
  final List<AnalysisTopRow> rows;
  final double Function(AnalysisTopRow) value;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<double>(1, (m, r) => value(r) > m ? value(r) : m);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: BarboraTheme.textMuted),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty) const Text('Sin datos este mes.', style: TextStyle(color: BarboraTheme.textMuted)),
            for (final (i, r) in rows.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text('${i + 1}.', style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13)),
                        ),
                        Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(fmt(value(r)), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: value(r) / max,
                        minHeight: 5,
                        color: _green,
                        backgroundColor: _green.withValues(alpha: .1),
                      ),
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

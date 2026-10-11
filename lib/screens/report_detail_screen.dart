import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/report.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/report_chart.dart';

/// Un reporte cualquiera, pintado con el mismo molde: resumen de tarjetas +
/// tablas, con un selector de periodo arriba. Los datos vienen ya formados de
/// `GET /reports/{type}`; aquí solo se les da forma visual.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.type, required this.title});

  final String type;
  final String title;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  ReportView? _report;
  ApiException? _error;
  bool _loading = true;

  /// Periodo elegido (clave de preset). Por defecto, el mes en curso.
  String _preset = 'mes';

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
      final body = await context.read<ApiClient>().get('/reports/${widget.type}', query: {
        'preset': _preset,
      });

      if (!mounted) return;
      setState(() => _report = ReportView.fromJson(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changePreset(String preset) {
    if (preset == _preset) return;
    setState(() => _preset = preset);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title),
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

    final report = _report!;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _PeriodBar(period: report.period, onPick: _changePreset),
          const SizedBox(height: 14),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: BarboraTheme.copper),
                ),
              ),
            ),

          if (report.note != null) ...[
            _NoteBanner(text: report.note!),
            const SizedBox(height: 14),
          ],

          if (report.summary.isNotEmpty) _SummaryGrid(stats: report.summary, symbol: symbol),

          for (final chart in report.charts)
            if (chart.hasData) ...[
              const SizedBox(height: 18),
              ReportChartCard(chart: chart, symbol: symbol),
            ],

          for (final table in report.tables)
            if (table.rows.isNotEmpty) ...[
              const SizedBox(height: 18),
              _ReportTableCard(table: table, symbol: symbol),
            ],

          if (report.summary.isEmpty && report.tables.every((t) => t.rows.isEmpty)) ...[
            const SizedBox(height: 60),
            const EmptyView(
              icon: Icons.bar_chart_outlined,
              title: 'Sin datos en este periodo',
              subtitle: 'Prueba con otro rango de fechas.',
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period, required this.onPick});

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

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats, required this.symbol});

  final List<ReportStat> stats;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in stats)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 32 - 20) / 3,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: BarboraTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BarboraTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Un total grande (Bs 12.340,00) no cabe a tamaño fijo: se
                  // encoge para no cortarse.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatReportValue(s.value, s.kind, symbol),
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -.3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: BarboraTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportTableCard extends StatelessWidget {
  const _ReportTableCard({required this.table, required this.symbol});

  final ReportTable table;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            table.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: BarboraTheme.textMuted,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                _Row(
                  cells: [for (final c in table.columns) c.label],
                  columns: table.columns,
                  header: true,
                  symbol: symbol,
                ),
                const Divider(height: 1),
                for (final (i, row) in table.rows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _Row(cells: row, columns: table.columns, symbol: symbol),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    required this.columns,
    required this.symbol,
    this.header = false,
  });

  final List<Object?> cells;
  final List<ReportColumn> columns;
  final String symbol;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          for (final (i, col) in columns.indexed)
            Expanded(
              // La primera columna (nombre) pesa más que las numéricas.
              flex: i == 0 ? 5 : 3,
              child: Text(
                header
                    ? col.label
                    : formatReportValue(i < cells.length ? cells[i] : null, col.kind, symbol),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: col.isEnd ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  fontSize: header ? 11 : 13,
                  fontWeight: header ? FontWeight.w700 : (i == 0 ? FontWeight.w600 : FontWeight.w700),
                  letterSpacing: header ? .5 : 0,
                  color: header ? BarboraTheme.textMuted : BarboraTheme.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteBanner extends StatelessWidget {
  const _NoteBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/report.dart';
import '../theme/barbora_theme.dart';

/// Pinta un [ReportChart] como línea (serie en el tiempo) o barras
/// (comparación entre categorías), en la paleta de la marca.
///
/// Con muchas etiquetas (p. ej. 30 días) solo se rotulan algunas para no
/// amontonarlas; el valor exacto sale al tocar.
class ReportChartCard extends StatelessWidget {
  const ReportChartCard({super.key, required this.chart, required this.symbol});

  final ReportChart chart;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            chart.title.toUpperCase(),
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
            padding: const EdgeInsets.fromLTRB(10, 18, 14, 10),
            child: SizedBox(
              height: 180,
              child: chart.isLine ? _line() : _bars(),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => formatReportValue(v, chart.kind, symbol);

  /// Etiqueta corta para el eje X (los nombres largos se recortan).
  String _short(int i) {
    if (i < 0 || i >= chart.labels.length) return '';
    final l = chart.labels[i];
    return l.length > 8 ? '${l.substring(0, 8)}…' : l;
  }

  double get _maxY {
    final m = chart.data.fold<double>(0, (a, b) => b > a ? b : a);
    return m <= 0 ? 1 : m * 1.15;
  }

  Widget _bottomTitle(int i, {required int every}) {
    if (i % every != 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _short(i),
        style: const TextStyle(fontSize: 9.5, color: BarboraTheme.textMuted),
      ),
    );
  }

  FlTitlesData _titles({required int every}) => FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (value, meta) => _bottomTitle(value.round(), every: every),
          ),
        ),
      );

  FlGridData get _grid => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: BarboraTheme.border, strokeWidth: 1),
      );

  Widget _line() {
    final spots = [
      for (final (i, v) in chart.data.indexed) FlSpot(i.toDouble(), v),
    ];
    // Con ~30 puntos, rotular cada 5 días deja el eje legible.
    final every = (chart.labels.length / 6).ceil().clamp(1, 999);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: _maxY,
        gridData: _grid,
        borderData: FlBorderData(show: false),
        titlesData: _titles(every: every),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => BarboraTheme.ink,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${_short(s.x.round())}\n${_fmt(s.y)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: .2,
            color: BarboraTheme.copper,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: BarboraTheme.copper.withValues(alpha: .10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bars() {
    final groups = [
      for (final (i, v) in chart.data.indexed)
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: v,
            color: BarboraTheme.copper,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ]),
    ];

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: _maxY,
        gridData: _grid,
        borderData: FlBorderData(show: false),
        titlesData: _titles(every: 1),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => BarboraTheme.ink,
            getTooltipItem: (group, a, rod, b) => BarTooltipItem(
              '${_short(group.x)}\n${_fmt(rod.toY)}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5),
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }
}

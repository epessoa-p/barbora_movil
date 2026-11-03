double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Un punto con etiqueta: una semana (14/09) o un mes (Oct).
typedef AnalysisPoint = ({String label, double value});

/// Un día de la semana: lo de esta semana y lo de la anterior.
typedef AnalysisDay = ({String label, double current, double previous});

/// Una métrica (monto o cantidad) de una serie.
class AnalysisMetric {
  const AnalysisMetric({
    this.week = 0,
    this.weekChange,
    this.month = 0,
    this.monthChange,
    this.daily = const [],
    this.weeks = const [],
    this.months = const [],
  });

  final double week;

  /// % contra el mismo tramo anterior; null si antes no hubo nada.
  final double? weekChange;
  final double month;
  final double? monthChange;
  final List<AnalysisDay> daily;
  final List<AnalysisPoint> weeks;
  final List<AnalysisPoint> months;

  static List<AnalysisPoint> _points(Object? raw) => [
        for (final p in (raw as List? ?? []).cast<Map<String, dynamic>>())
          (label: '${p['label'] ?? ''}', value: _d(p['value'])),
      ];

  factory AnalysisMetric.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AnalysisMetric();
    return AnalysisMetric(
      week: _d(json['week']),
      weekChange: (json['week_change'] as num?)?.toDouble(),
      month: _d(json['month']),
      monthChange: (json['month_change'] as num?)?.toDouble(),
      daily: [
        for (final d in (json['daily'] as List? ?? []).cast<Map<String, dynamic>>())
          (label: '${d['label'] ?? ''}', current: _d(d['current']), previous: _d(d['previous'])),
      ],
      weeks: _points(json['weeks']),
      months: _points(json['months']),
    );
  }
}

/// Una fila del top: servicio, producto o cliente.
typedef AnalysisTopRow = ({String name, double amount, double count});

/// `GET /reports/analysis`.
class AnalysisReportView {
  const AnalysisReportView({required this.series, required this.top});

  /// servicios · ventas · compras (si el plan tiene inventario) → monto y cantidad.
  final Map<String, ({AnalysisMetric amount, AnalysisMetric count})> series;

  /// services · products · clients, del mes en curso.
  final Map<String, List<AnalysisTopRow>> top;

  factory AnalysisReportView.fromJson(Map<String, dynamic> json) {
    final series = json['series'] as Map<String, dynamic>? ?? const {};
    final top = json['top'] as Map<String, dynamic>? ?? const {};

    return AnalysisReportView(
      series: {
        for (final e in series.entries)
          e.key: (
            amount: AnalysisMetric.fromJson((e.value as Map<String, dynamic>)['amount'] as Map<String, dynamic>?),
            count: AnalysisMetric.fromJson((e.value as Map<String, dynamic>)['count'] as Map<String, dynamic>?),
          ),
      },
      top: {
        for (final e in top.entries)
          e.key: [
            for (final r in (e.value as List? ?? []).cast<Map<String, dynamic>>())
              (name: '${r['name'] ?? ''}', amount: _d(r['amount']), count: _d(r['count'])),
          ],
      },
    );
  }
}

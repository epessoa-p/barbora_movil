/// Un reporte, tal como llega de `GET /reports/{type}`.
///
/// El backend reusa el cálculo de la web y lo entrega en un formato uniforme
/// —resumen de tarjetas + tablas— para que una sola pantalla pinte todos. Los
/// importes vienen como número: la app les pone el símbolo de la barbería.
class ReportView {
  const ReportView({
    required this.key,
    required this.title,
    required this.period,
    this.summary = const [],
    this.tables = const [],
    this.note,
  });

  final String key;
  final String title;
  final ReportPeriodInfo period;
  final List<ReportStat> summary;
  final List<ReportTable> tables;
  final String? note;

  factory ReportView.fromJson(Map<String, dynamic> json) => ReportView(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        period: ReportPeriodInfo.fromJson(json['period'] as Map<String, dynamic>? ?? const {}),
        summary: (json['summary'] as List? ?? [])
            .map((e) => ReportStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        tables: (json['tables'] as List? ?? [])
            .map((e) => ReportTable.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: json['note'] as String?,
      );
}

class ReportPeriodInfo {
  const ReportPeriodInfo({
    this.preset,
    this.label = '',
    this.presets = const [],
  });

  final String? preset;
  final String label;
  final List<PresetOption> presets;

  factory ReportPeriodInfo.fromJson(Map<String, dynamic> json) => ReportPeriodInfo(
        preset: json['preset'] as String?,
        label: json['label'] as String? ?? '',
        presets: (json['presets'] as List? ?? [])
            .map((e) => PresetOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PresetOption {
  const PresetOption({required this.key, required this.label});

  final String key;
  final String label;

  factory PresetOption.fromJson(Map<String, dynamic> json) => PresetOption(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

/// Un dato del resumen. `kind` decide cómo se muestra: int, money, percent, text.
class ReportStat {
  const ReportStat({required this.label, required this.value, required this.kind});

  final String label;
  final Object? value;
  final String kind;

  factory ReportStat.fromJson(Map<String, dynamic> json) => ReportStat(
        label: json['label'] as String? ?? '',
        value: json['value'],
        kind: json['kind'] as String? ?? 'text',
      );
}

class ReportTable {
  const ReportTable({required this.title, this.columns = const [], this.rows = const []});

  final String title;
  final List<ReportColumn> columns;
  final List<List<Object?>> rows;

  factory ReportTable.fromJson(Map<String, dynamic> json) => ReportTable(
        title: json['title'] as String? ?? '',
        columns: (json['columns'] as List? ?? [])
            .map((e) => ReportColumn.fromJson(e as Map<String, dynamic>))
            .toList(),
        rows: (json['rows'] as List? ?? [])
            .map((r) => (r as List? ?? []).map((c) => c as Object?).toList())
            .toList(),
      );
}

class ReportColumn {
  const ReportColumn({required this.label, this.kind = 'text', this.align = 'start'});

  final String label;
  final String kind;
  final String align;

  bool get isEnd => align == 'end';

  factory ReportColumn.fromJson(Map<String, dynamic> json) => ReportColumn(
        label: json['label'] as String? ?? '',
        kind: json['kind'] as String? ?? 'text',
        align: json['align'] as String? ?? 'start',
      );
}

/// Da formato a un valor según su `kind`. El símbolo es el de la barbería.
String formatReportValue(Object? value, String kind, String symbol) {
  if (value == null) return '—';

  switch (kind) {
    case 'money':
      final n = value is num ? value : num.tryParse('$value') ?? 0;
      return '$symbol ${n.toStringAsFixed(2)}';
    case 'int':
      final n = value is num ? value : num.tryParse('$value') ?? 0;
      return n.toInt().toString();
    case 'percent':
      final n = value is num ? value : num.tryParse('$value');
      return n == null ? '—' : '${n % 1 == 0 ? n.toInt() : n}%';
    default:
      return '$value';
  }
}

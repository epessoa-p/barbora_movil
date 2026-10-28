import 'appointment.dart';
import 'report.dart';

/// El resumen del día (`GET /dashboard`). Cada bloque es null si el plan o los
/// permisos no lo dejan ver.
class Dashboard {
  const Dashboard({this.agenda, this.sales, this.cash, this.stock});

  final DashAgenda? agenda;
  final DashSales? sales;
  final DashCash? cash;
  final DashStock? stock;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    T? block<T>(String key, T Function(Map<String, dynamic>) parse) =>
        json[key] is Map<String, dynamic> ? parse(json[key] as Map<String, dynamic>) : null;

    return Dashboard(
      agenda: block('agenda', DashAgenda.fromJson),
      sales: block('sales', DashSales.fromJson),
      cash: block('cash', DashCash.fromJson),
      stock: block('stock', DashStock.fromJson),
    );
  }
}

class DashAgenda {
  const DashAgenda({
    this.total = 0,
    this.pending = 0,
    this.attended = 0,
    this.noShow = 0,
    this.next = const [],
  });

  final int total;
  final int pending;
  final int attended;
  final int noShow;

  /// Las próximas citas que quedan hoy (hasta 3).
  final List<Appointment> next;

  factory DashAgenda.fromJson(Map<String, dynamic> json) => DashAgenda(
        total: json['total'] as int? ?? 0,
        pending: json['pending'] as int? ?? 0,
        attended: json['attended'] as int? ?? 0,
        noShow: json['no_show'] as int? ?? 0,
        next: (json['next'] as List? ?? [])
            .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DashSales {
  const DashSales({
    this.today = 0,
    this.count = 0,
    this.tips = 0,
    this.average = 0,
    this.yesterday = 0,
    this.week,
  });

  final double today;
  final int count;
  final double tips;
  final double average;
  final double yesterday;

  /// Lo cobrado los últimos 7 días, para el gráfico.
  final ReportChart? week;

  /// Variación frente a ayer, en %. Null si ayer no hubo ventas.
  double? get vsYesterday => yesterday <= 0 ? null : (today - yesterday) / yesterday * 100;

  factory DashSales.fromJson(Map<String, dynamic> json) {
    final week = json['week'] as Map<String, dynamic>?;

    return DashSales(
      today: (json['today'] as num?)?.toDouble() ?? 0,
      count: json['count'] as int? ?? 0,
      tips: (json['tips'] as num?)?.toDouble() ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0,
      yesterday: (json['yesterday'] as num?)?.toDouble() ?? 0,
      week: week == null
          ? null
          : ReportChart.fromJson({...week, 'type': 'bar', 'title': 'Últimos 7 días', 'kind': 'money'}),
    );
  }
}

class DashCash {
  const DashCash({required this.open, this.caja, this.openedBy, this.expectedCash = 0, this.income = 0});

  final bool open;
  final String? caja;
  final String? openedBy;
  final double expectedCash;
  final double income;

  factory DashCash.fromJson(Map<String, dynamic> json) => DashCash(
        open: json['open'] as bool? ?? false,
        caja: json['caja'] as String?,
        openedBy: json['opened_by'] as String?,
        expectedCash: (json['expected_cash'] as num?)?.toDouble() ?? 0,
        income: (json['income'] as num?)?.toDouble() ?? 0,
      );
}

class DashStock {
  const DashStock({this.lowCount = 0, this.items = const []});

  final int lowCount;

  /// Los primeros por reponer: nombre y existencia («2 unidades»).
  final List<({String name, String stock})> items;

  factory DashStock.fromJson(Map<String, dynamic> json) => DashStock(
        lowCount: json['low_count'] as int? ?? 0,
        items: (json['items'] as List? ?? [])
            .map((e) => (
                  name: (e as Map<String, dynamic>)['name'] as String? ?? '',
                  stock: e['stock_label'] as String? ?? '',
                ))
            .toList(),
      );
}

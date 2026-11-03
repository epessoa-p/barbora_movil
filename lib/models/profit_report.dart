import 'report.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Ingresos, costo y ganancia de un bloque (todo, ventas, servicios, un día…).
class ProfitTotals {
  const ProfitTotals({
    this.revenue = 0,
    this.cost = 0,
    this.profit = 0,
    this.marginPct,
    this.sales = 0,
  });

  final double revenue;
  final double cost;
  final double profit;

  /// null si no hubo ingresos (no hay margen que calcular).
  final double? marginPct;

  /// Ventas distintas que aportan al bloque (solo productos / servicios).
  final int sales;

  factory ProfitTotals.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ProfitTotals();
    return ProfitTotals(
      revenue: _d(json['revenue']),
      cost: _d(json['cost']),
      profit: _d(json['profit']),
      marginPct: (json['margin_pct'] as num?)?.toDouble(),
      sales: (json['sales'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProfitDay {
  const ProfitDay({required this.date, required this.totals});

  final DateTime date;
  final ProfitTotals totals;

  factory ProfitDay.fromJson(Map<String, dynamic> json) => ProfitDay(
        date: DateTime.parse(json['date'] as String),
        totals: ProfitTotals.fromJson(json),
      );
}

class ProfitProduct {
  const ProfitProduct({
    required this.name,
    required this.quick,
    required this.quantity,
    required this.totals,
  });

  final String name;

  /// Venta rápida: producto sin ficha, sin costo conocido.
  final bool quick;
  final double quantity;
  final ProfitTotals totals;

  factory ProfitProduct.fromJson(Map<String, dynamic> json) => ProfitProduct(
        name: json['name'] as String? ?? '',
        quick: json['quick'] as bool? ?? false,
        quantity: _d(json['quantity']),
        totals: ProfitTotals.fromJson(json),
      );
}

class ProfitSale {
  const ProfitSale({
    required this.id,
    required this.number,
    required this.soldAt,
    this.client,
    required this.totals,
  });

  final int id;
  final String number;
  final DateTime soldAt;
  final String? client;
  final ProfitTotals totals;

  factory ProfitSale.fromJson(Map<String, dynamic> json) => ProfitSale(
        id: (json['id'] as num).toInt(),
        number: '${json['number'] ?? ''}',
        soldAt: DateTime.parse(json['sold_at'] as String).toLocal(),
        client: json['client'] as String?,
        totals: ProfitTotals.fromJson(json),
      );
}

/// `GET /reports/profit`: la ganancia por lo vendido.
class ProfitReportView {
  const ProfitReportView({
    required this.period,
    required this.scope,
    required this.includeQuick,
    required this.summary,
    required this.products,
    required this.services,
    required this.quickRevenue,
    required this.quickCount,
    required this.daily,
    required this.topProducts,
    required this.lowMarginProducts,
    required this.sales,
    required this.estimated,
    this.expenses,
    this.net,
  });

  final ReportPeriodInfo period;

  /// ambos · ventas · servicios
  final String scope;
  final bool includeQuick;
  final ProfitTotals summary;
  final ProfitTotals products;
  final ProfitTotals services;
  final double quickRevenue;
  final int quickCount;
  final List<ProfitDay> daily;
  final List<ProfitProduct> topProducts;
  final List<ProfitProduct> lowMarginProducts;
  final List<ProfitSale> sales;

  /// Algún costo salió del costo actual del producto (la venta no lo guardó).
  final bool estimated;

  /// Gastos del periodo y lo que queda después de ellos.
  final double? expenses;
  final double? net;

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
      (raw as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

  factory ProfitReportView.fromJson(Map<String, dynamic> json) {
    final quick = json['quick'] as Map<String, dynamic>? ?? const {};
    final result = json['result'] as Map<String, dynamic>?;

    return ProfitReportView(
      period: ReportPeriodInfo.fromJson(json['period'] as Map<String, dynamic>? ?? const {}),
      scope: json['scope'] as String? ?? 'ambos',
      includeQuick: json['include_quick'] as bool? ?? false,
      summary: ProfitTotals.fromJson(json['summary'] as Map<String, dynamic>?),
      products: ProfitTotals.fromJson(json['products'] as Map<String, dynamic>?),
      services: ProfitTotals.fromJson(json['services'] as Map<String, dynamic>?),
      quickRevenue: _d(quick['revenue']),
      quickCount: (quick['count'] as num?)?.toInt() ?? 0,
      daily: _list(json['daily'], ProfitDay.fromJson),
      topProducts: _list(json['top_products'], ProfitProduct.fromJson),
      lowMarginProducts: _list(json['low_margin_products'], ProfitProduct.fromJson),
      sales: _list(json['sales'], ProfitSale.fromJson),
      estimated: json['estimated'] as bool? ?? false,
      expenses: (result?['expenses'] as num?)?.toDouble(),
      net: (result?['net'] as num?)?.toDouble(),
    );
  }
}

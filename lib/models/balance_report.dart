import 'report.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

DateTime? _date(Object? v) => v is String ? DateTime.parse(v).toLocal() : null;

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
    (raw as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

/// Una línea de ingresos o egresos: «Servicios», «Pago a proveedor»…
class BalanceLine {
  const BalanceLine({required this.key, required this.label, required this.total, this.type});

  final String key;
  final String label;
  final double total;

  /// Solo en las categorías de Movimientos: ingreso · egreso.
  final String? type;

  bool get isIncome => type == 'ingreso';

  factory BalanceLine.fromJson(Map<String, dynamic> json) => BalanceLine(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        total: _d(json['total']),
        type: json['type'] as String?,
      );
}

/// Ingresos o egresos del periodo: por categoría, el total y cuánto pasó por
/// caja y cuánto por tesorería.
class BalanceSide {
  const BalanceSide({this.lines = const [], this.total = 0, this.cash = 0, this.treasury = 0});

  final List<BalanceLine> lines;
  final double total;
  final double cash;
  final double treasury;

  factory BalanceSide.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BalanceSide();
    final source = json['by_source'] as Map<String, dynamic>? ?? const {};
    return BalanceSide(
      lines: _list(json['lines'], BalanceLine.fromJson),
      total: _d(json['total']),
      cash: _d(source['caja']),
      treasury: _d(source['tesoreria']),
    );
  }
}

class BalanceMovement {
  const BalanceMovement({
    required this.id,
    required this.source,
    required this.type,
    required this.categoryLabel,
    required this.concept,
    required this.amount,
    required this.at,
    this.place = '',
    this.method,
  });

  final String id;

  /// caja · tesoreria · sin_caja (venta cobrada sin turno abierto)
  final String source;
  final String type;
  final String categoryLabel;
  final String concept;
  final double amount;
  final DateTime at;
  final String place;
  final String? method;

  bool get isIncome => type == 'ingreso';

  factory BalanceMovement.fromJson(Map<String, dynamic> json) => BalanceMovement(
        id: '${json['id']}',
        source: json['source'] as String? ?? 'caja',
        type: json['type'] as String? ?? 'ingreso',
        categoryLabel: json['category_label'] as String? ?? '',
        concept: json['concept'] as String? ?? '',
        amount: _d(json['amount']),
        at: _date(json['at']) ?? DateTime.now(),
        place: json['place'] as String? ?? '',
        method: json['method'] as String?,
      );
}

/// Un turno de caja con su arqueo.
class BalanceClosing {
  const BalanceClosing({
    required this.id,
    this.number,
    this.caja,
    this.branch,
    required this.open,
    this.openedAt,
    this.openedBy,
    this.closedAt,
    this.closedBy,
    this.opening = 0,
    this.cashIncome = 0,
    this.cashExpense = 0,
    this.expected = 0,
    this.counted,
    this.difference,
    this.otherMethods = const [],
  });

  final int id;
  final String? number;
  final String? caja;
  final String? branch;
  final bool open;
  final DateTime? openedAt;
  final String? openedBy;
  final DateTime? closedAt;
  final String? closedBy;
  final double opening;
  final double cashIncome;
  final double cashExpense;
  final double expected;
  final double? counted;
  final double? difference;

  /// Lo cobrado por QR, tarjeta…: no está en el cajón.
  final List<({String label, double amount})> otherMethods;

  String get title => [caja, branch].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  factory BalanceClosing.fromJson(Map<String, dynamic> json) => BalanceClosing(
        id: (json['id'] as num).toInt(),
        number: json['number'] as String?,
        caja: json['caja'] as String?,
        branch: json['branch'] as String?,
        open: json['status'] == 'abierta',
        openedAt: _date(json['opened_at']),
        openedBy: json['opened_by'] as String?,
        closedAt: _date(json['closed_at']),
        closedBy: json['closed_by'] as String?,
        opening: _d(json['opening']),
        cashIncome: _d(json['cash_income']),
        cashExpense: _d(json['cash_expense']),
        expected: _d(json['expected']),
        counted: (json['counted'] as num?)?.toDouble(),
        difference: (json['difference'] as num?)?.toDouble(),
        otherMethods: [
          for (final o in (json['other_methods'] as List? ?? []).cast<Map<String, dynamic>>())
            (label: o['label'] as String? ?? '', amount: _d(o['amount'])),
        ],
      );
}

/// `GET /reports/balance`: lo que entró y salió de caja y tesorería.
class BalanceReportView {
  const BalanceReportView({
    required this.period,
    required this.source,
    this.type,
    required this.income,
    required this.expense,
    required this.profit,
    required this.contributions,
    required this.withdrawals,
    required this.flowIncome,
    required this.flowExpense,
    required this.flowBalance,
    required this.categories,
    required this.movements,
    required this.movementsCount,
    required this.closings,
  });

  final ReportPeriodInfo period;

  /// Filtro de Movimientos: caja · tesoreria · todo, e ingreso · egreso · null.
  final String source;
  final String? type;

  final BalanceSide income;
  final BalanceSide expense;
  final double profit;

  /// Dinero del dueño: no es ganancia ni gasto.
  final double contributions;
  final double withdrawals;

  final double flowIncome;
  final double flowExpense;
  final double flowBalance;
  final List<BalanceLine> categories;
  final List<BalanceMovement> movements;

  /// Todos los movimientos del filtro; la lista trae como mucho 500.
  final int movementsCount;
  final List<BalanceClosing> closings;

  factory BalanceReportView.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as Map<String, dynamic>? ?? const {};
    final capital = results['capital'] as Map<String, dynamic>? ?? const {};
    final flow = json['flow'] as Map<String, dynamic>? ?? const {};

    return BalanceReportView(
      period: ReportPeriodInfo.fromJson(json['period'] as Map<String, dynamic>? ?? const {}),
      source: json['source'] as String? ?? 'caja',
      type: json['type'] as String?,
      income: BalanceSide.fromJson(results['income'] as Map<String, dynamic>?),
      expense: BalanceSide.fromJson(results['expense'] as Map<String, dynamic>?),
      profit: _d(results['profit']),
      contributions: _d(capital['contributions']),
      withdrawals: _d(capital['withdrawals']),
      flowIncome: _d(flow['income']),
      flowExpense: _d(flow['expense']),
      flowBalance: _d(flow['balance']),
      categories: _list(flow['categories'], BalanceLine.fromJson),
      movements: _list(flow['items'], BalanceMovement.fromJson),
      movementsCount: (flow['count'] as num?)?.toInt() ?? 0,
      closings: _list(json['closings'], BalanceClosing.fromJson),
    );
  }
}

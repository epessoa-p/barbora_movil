import '../core/shop_time.dart';

/// Respuesta de `GET /my/commissions`.
class CommissionReport {
  const CommissionReport({
    required this.from,
    required this.to,
    required this.periodLabel,
    required this.earned,
    required this.pending,
    required this.settled,
    required this.tips,
    this.currencySymbol = '',
    this.entries = const [],
  });

  final DateTime from;
  final DateTime to;
  final String periodLabel;

  final double earned;

  /// Lo devengado que todavía no se ha pagado: lo que la barbería le debe.
  final double pending;
  final double settled;
  final double tips;

  final String currencySymbol;
  final List<CommissionEntry> entries;

  double get totalToCollect => pending + tips;

  factory CommissionReport.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? const {};
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};

    return CommissionReport(
      from: DateTime.parse(period['from'] as String),
      to: DateTime.parse(period['to'] as String),
      periodLabel: period['label'] as String? ?? '',
      earned: (totals['earned'] as num?)?.toDouble() ?? 0,
      pending: (totals['pending'] as num?)?.toDouble() ?? 0,
      settled: (totals['settled'] as num?)?.toDouble() ?? 0,
      tips: (totals['tips'] as num?)?.toDouble() ?? 0,
      currencySymbol: totals['currency_symbol'] as String? ?? '',
      entries: (json['data'] as List?)
              ?.map((e) => CommissionEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class CommissionEntry {
  const CommissionEntry({
    required this.id,
    required this.earnedAt,
    required this.baseAmount,
    required this.amount,
    this.description,
    this.rateLabel,
    this.settled = false,
  });

  final int id;
  final DateTime earnedAt;

  /// El importe de la línea sobre el que se calculó la comisión.
  final double baseAmount;
  final double amount;
  final String? description;
  final String? rateLabel;
  final bool settled;

  factory CommissionEntry.fromJson(Map<String, dynamic> json) => CommissionEntry(
        id: json['id'] as int,
        earnedAt: ShopTime.parse(json['earned_at'] as String),
        baseAmount: (json['base_amount'] as num?)?.toDouble() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        rateLabel: json['rate_label'] as String?,
        settled: json['settled'] as bool? ?? false,
      );
}

/// Una franja de `GET /my/schedule`.
class WorkSlot {
  const WorkSlot({
    required this.id,
    required this.weekday,
    required this.weekdayLabel,
    required this.startTime,
    required this.endTime,
    this.branch,
  });

  final int id;

  /// ISO-8601: 1 = lunes … 7 = domingo.
  final int weekday;
  final String weekdayLabel;
  final String startTime;
  final String endTime;
  final String? branch;

  String get range => '$startTime – $endTime';

  factory WorkSlot.fromJson(Map<String, dynamic> json) => WorkSlot(
        id: json['id'] as int,
        weekday: json['weekday'] as int? ?? 1,
        weekdayLabel: json['weekday_label'] as String? ?? '',
        startTime: json['start_time'] as String? ?? '',
        endTime: json['end_time'] as String? ?? '',
        branch: json['branch'] as String?,
      );
}

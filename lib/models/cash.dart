import '../core/shop_time.dart';

/// Un turno de caja: se abre con un fondo, acumula movimientos y se cierra
/// contando el efectivo.
class CashSession {
  const CashSession({
    required this.id,
    required this.status,
    required this.isOpen,
    required this.cajaId,
    required this.cajaName,
    required this.openedAt,
    required this.openingAmount,
    required this.duration,
    required this.totals,
    this.openedBy,
    this.movements = const [],
    this.movementsCount = 0,
    this.closedAt,
    this.closedBy,
    this.closingAmount,
    this.expectedAmount,
    this.difference,
    this.differenceLabel,
  });

  final int id;
  final String status;
  final bool isOpen;
  final int? cajaId;
  final String cajaName;
  final DateTime openedAt;
  final String? openedBy;
  final double openingAmount;
  final String duration;
  final CashTotals totals;
  final List<CashMovement> movements;
  final int movementsCount;

  // Solo cuando está cerrado.
  final DateTime? closedAt;
  final String? closedBy;
  final double? closingAmount;
  final double? expectedAmount;
  final double? difference;
  final String? differenceLabel;

  /// ¿Sobró, faltó o cuadró? Null mientras el turno sigue abierto.
  bool? get isShort => difference == null ? null : difference! < -0.005;

  factory CashSession.fromJson(Map<String, dynamic> json) {
    final caja = json['caja'] as Map<String, dynamic>? ?? const {};

    return CashSession(
      id: json['id'] as int,
      status: json['status'] as String? ?? '',
      isOpen: json['is_open'] as bool? ?? false,
      cajaId: caja['id'] as int?,
      cajaName: caja['name'] as String? ?? 'Caja',
      openedAt: ShopTime.parse(json['opened_at'] as String),
      openedBy: json['opened_by'] as String?,
      openingAmount: (json['opening_amount'] as num?)?.toDouble() ?? 0,
      duration: json['duration'] as String? ?? '',
      totals: CashTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? const {}),
      movements: (json['movements'] as List?)
              ?.map((e) => CashMovement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      movementsCount: json['movements_count'] as int? ?? 0,
      closedAt: ShopTime.tryParse(json['closed_at'] as String?),
      closedBy: json['closed_by'] as String?,
      closingAmount: (json['closing_amount'] as num?)?.toDouble(),
      expectedAmount: (json['expected_amount'] as num?)?.toDouble(),
      difference: (json['difference'] as num?)?.toDouble(),
      differenceLabel: json['difference_label'] as String?,
    );
  }
}

class CashTotals {
  const CashTotals({
    this.income = 0,
    this.expense = 0,
    this.cashIncome = 0,
    this.cashExpense = 0,
    this.expectedCash = 0,
    this.net = 0,
  });

  final double income;
  final double expense;
  final double cashIncome;
  final double cashExpense;

  /// Lo que debería haber en el cajón ahora mismo: fondo + efectivo que entró
  /// − el que salió. Es la cifra contra la que se arquea.
  final double expectedCash;
  final double net;

  factory CashTotals.fromJson(Map<String, dynamic> json) => CashTotals(
        income: (json['income'] as num?)?.toDouble() ?? 0,
        expense: (json['expense'] as num?)?.toDouble() ?? 0,
        cashIncome: (json['cash_income'] as num?)?.toDouble() ?? 0,
        cashExpense: (json['cash_expense'] as num?)?.toDouble() ?? 0,
        expectedCash: (json['expected_cash'] as num?)?.toDouble() ?? 0,
        net: (json['net'] as num?)?.toDouble() ?? 0,
      );
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.type,
    required this.paymentMethod,
    required this.paymentMethodLabel,
    required this.concept,
    required this.amount,
    required this.createdAt,
    this.reference,
    this.createdBy,
  });

  final int id;

  /// ingreso · egreso
  final String type;
  final String paymentMethod;
  final String paymentMethodLabel;
  final String concept;
  final double amount;
  final DateTime createdAt;
  final String? reference;
  final String? createdBy;

  bool get isIncome => type == 'ingreso';

  /// Con signo, para pintarlo en la lista.
  double get signedAmount => isIncome ? amount : -amount;

  factory CashMovement.fromJson(Map<String, dynamic> json) => CashMovement(
        id: json['id'] as int,
        type: json['type'] as String? ?? '',
        paymentMethod: json['payment_method'] as String? ?? '',
        paymentMethodLabel: json['payment_method_label'] as String? ?? '',
        concept: json['concept'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        createdAt: ShopTime.parse(json['created_at'] as String),
        reference: json['reference'] as String?,
        createdBy: json['created_by'] as String?,
      );
}

/// Una caja registradora y si tiene turno abierto.
class Caja {
  const Caja({
    required this.id,
    required this.name,
    required this.isOpen,
    this.branch,
  });

  final int id;
  final String name;
  final bool isOpen;
  final String? branch;

  factory Caja.fromJson(Map<String, dynamic> json) => Caja(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        isOpen: json['is_open'] as bool? ?? false,
        branch: json['branch'] as String?,
      );
}

/// Un método de pago de la barbería.
///
/// **No van escritos en la app**: cada barbería define los suyos (una puede
/// cobrar por Tigo Money y otra por el QR de su banco), así que llegan en
/// `GET /me` y se guardan en la sesión.
class PaymentMethod {
  const PaymentMethod({
    required this.slug,
    required this.name,
    this.countsAsCash = false,
    this.requiresReference = false,
  });

  final String slug;
  final String name;

  /// ¿Este dinero queda en el cajón? Es lo que se compara al arquear el turno.
  /// Un cobro con tarjeta o billetera está en el banco, no en la caja.
  final bool countsAsCash;

  final bool requiresReference;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        countsAsCash: json['counts_as_cash'] as bool? ?? false,
        requiresReference: json['requires_reference'] as bool? ?? false,
      );

  /// Los cuatro de siempre, por si `/me` todavía no respondió. Es solo un
  /// arranque en frío: en cuanto llega la sesión se sustituyen por los reales.
  static const List<PaymentMethod> fallback = [
    PaymentMethod(slug: 'efectivo', name: 'Efectivo', countsAsCash: true),
    PaymentMethod(slug: 'tarjeta', name: 'Tarjeta'),
    PaymentMethod(slug: 'transferencia', name: 'Transferencia', requiresReference: true),
    PaymentMethod(slug: 'qr', name: 'QR', requiresReference: true),
  ];
}

import '../core/shop_time.dart';

/// Una venta cobrada.
class Sale {
  const Sale({
    required this.id,
    required this.number,
    required this.status,
    required this.soldAt,
    required this.subtotal,
    required this.discount,
    required this.tip,
    required this.total,
    this.notes,
    this.clientName,
    this.personalName,
    this.branch,
    this.appointmentId,
    this.items = const [],
    this.payments = const [],
    this.statusLabel,
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
  });

  final int id;
  final String number;
  final String status;
  final DateTime soldAt;
  final double subtotal;
  final double discount;
  final double tip;
  final double total;
  final String? notes;
  final String? clientName;
  final String? personalName;
  final String? branch;
  final int? appointmentId;
  final List<SaleItem> items;
  final List<SalePayment> payments;

  final String? statusLabel;

  /// Solo en las anuladas: por qué, cuándo y quién.
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;

  bool get isCancelled => status == 'anulada';

  factory Sale.fromJson(Map<String, dynamic> json) {
    final client = json['client'] as Map<String, dynamic>?;
    final personal = json['personal'] as Map<String, dynamic>?;

    return Sale(
      id: json['id'] as int,
      number: json['number'] as String? ?? '',
      status: json['status'] as String? ?? '',
      soldAt: ShopTime.parse(json['sold_at'] as String),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      tip: (json['tip'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      clientName: client?['full_name'] as String?,
      personalName: personal?['full_name'] as String?,
      branch: json['branch'] as String?,
      appointmentId: json['appointment_id'] as int?,
      items: (json['items'] as List?)
              ?.map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      payments: (json['payments'] as List?)
              ?.map((e) => SalePayment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      statusLabel: json['status_label'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      cancelledAt: ShopTime.tryParse(json['cancelled_at'] as String?),
      cancelledBy: json['cancelled_by'] as String?,
    );
  }
}

/// Una fila del historial (`GET /sales`): lo justo para la lista.
class SaleRow {
  const SaleRow({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.soldAt,
    this.client,
    this.personal,
    this.methods = const [],
  });

  final int id;
  final String number;
  final String status;
  final double total;
  final DateTime soldAt;
  final String? client;
  final String? personal;

  /// Cómo se pagó: «Efectivo», «QR»…
  final List<String> methods;

  bool get isCancelled => status == 'anulada';

  factory SaleRow.fromJson(Map<String, dynamic> json) => SaleRow(
        id: json['id'] as int,
        number: json['number'] as String? ?? '',
        status: json['status'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        soldAt: ShopTime.parse(json['sold_at'] as String),
        client: json['client'] as String?,
        personal: json['personal'] as String?,
        methods: (json['methods'] as List? ?? []).cast<String>(),
      );
}

/// Totales del periodo: lo cobrado no incluye las anuladas.
class SalesSummary {
  const SalesSummary({this.count = 0, this.total = 0, this.tips = 0, this.cancelled = 0});

  final int count;
  final double total;
  final double tips;
  final int cancelled;

  factory SalesSummary.fromJson(Map<String, dynamic> json) => SalesSummary(
        count: json['count'] as int? ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        tips: (json['tips'] as num?)?.toDouble() ?? 0,
        cancelled: json['cancelled'] as int? ?? 0,
      );
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.type,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.personal,
  });

  final int id;

  /// servicio · producto
  final String type;
  final String description;
  final double quantity;
  final double unitPrice;
  final double total;
  final String? personal;

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: json['id'] as int,
        type: json['type'] as String? ?? '',
        description: json['description'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        personal: json['personal'] as String?,
      );
}

class SalePayment {
  const SalePayment({
    required this.paymentMethod,
    required this.paymentMethodLabel,
    required this.amount,
    this.reference,
  });

  final String paymentMethod;
  final String paymentMethodLabel;
  final double amount;
  final String? reference;

  factory SalePayment.fromJson(Map<String, dynamic> json) => SalePayment(
        paymentMethod: json['payment_method'] as String? ?? '',
        paymentMethodLabel: json['payment_method_label'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        reference: json['reference'] as String?,
      );
}

/// Una línea de la comanda mientras se arma, antes de cobrar.
///
/// El precio que se guarda aquí es solo para enseñar el total en pantalla: al
/// cobrar se manda el id y la cantidad, y el servidor vuelve a leer el precio
/// del catálogo. Si alguien cambia la tarifa mientras se arma la comanda, manda
/// la del servidor.
class CartLine {
  CartLine({
    required this.type,
    required this.id,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
    this.personalId,
  });

  /// servicio · producto
  final String type;
  final int id;
  final String name;
  final double unitPrice;
  double quantity;
  int? personalId;

  double get total => unitPrice * quantity;

  bool get isService => type == 'servicio';

  Map<String, dynamic> toRequest() => {
        'type': type,
        'id': id,
        'quantity': quantity,
        'personal_id': ?personalId,
      };
}

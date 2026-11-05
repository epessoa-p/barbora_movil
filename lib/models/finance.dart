// Finanzas (cuentas, movimientos, gastos) y Compras (proveedores, compras).
// Llega de `/finance/...`, `/purchases/...` y `/suppliers`.

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Una cuenta: capital, caja chica, banco… El dinero fuera del cajón.
class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.typeLabel,
    this.bankName,
    this.accountNumber,
    this.branch,
    this.notes,
    this.balance = 0,
    this.active = true,
  });

  final int id;
  final String name;
  final String type;
  final String typeLabel;
  final String? bankName;
  final String? accountNumber;
  final String? branch;
  final String? notes;
  final double balance;
  final bool active;

  factory FinanceAccount.fromJson(Map<String, dynamic> j) => FinanceAccount(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'otro',
        typeLabel: j['type_label'] as String? ?? '',
        bankName: j['bank_name'] as String?,
        accountNumber: j['account_number'] as String?,
        branch: j['branch'] as String?,
        notes: j['notes'] as String?,
        balance: _d(j['balance']),
        active: j['active'] as bool? ?? true,
      );
}

/// Un ingreso o egreso de una cuenta.
class FinanceMovement {
  const FinanceMovement({
    required this.id,
    required this.type,
    required this.originLabel,
    required this.concept,
    required this.amount,
    required this.balanceAfter,
    required this.occurredOn,
    this.reference,
    this.createdBy,
    this.cancelled = false,
    this.canCancel = false,
  });

  final int id;
  final String type;
  final String originLabel;
  final String concept;
  final double amount;
  final double balanceAfter;
  final DateTime occurredOn;
  final String? reference;
  final String? createdBy;
  final bool cancelled;
  final bool canCancel;

  bool get isIncome => type == 'ingreso';

  factory FinanceMovement.fromJson(Map<String, dynamic> j) => FinanceMovement(
        id: j['id'] as int,
        type: j['type'] as String? ?? 'egreso',
        originLabel: j['origin_label'] as String? ?? '',
        concept: j['concept'] as String? ?? '',
        amount: _d(j['amount']),
        balanceAfter: _d(j['balance_after']),
        occurredOn: DateTime.parse(j['occurred_on'] as String),
        reference: j['reference'] as String?,
        createdBy: j['created_by'] as String?,
        cancelled: j['cancelled'] as bool? ?? false,
        canCancel: j['can_cancel'] as bool? ?? false,
      );
}

/// Un gasto.
class ExpenseItem {
  const ExpenseItem({
    required this.id,
    required this.number,
    required this.description,
    required this.amount,
    required this.spentOn,
    required this.source,
    required this.sourceLabel,
    this.category,
    this.payee,
    this.reference,
    this.notes,
    this.cancelled = false,
    this.cancelReason,
    this.canCancel = false,
  });

  final int id;
  final String number;
  final String description;
  final double amount;
  final DateTime spentOn;

  /// «account» o «cash».
  final String source;
  final String sourceLabel;
  final String? category;
  final String? payee;
  final String? reference;
  final String? notes;
  final bool cancelled;
  final String? cancelReason;
  final bool canCancel;

  factory ExpenseItem.fromJson(Map<String, dynamic> j) => ExpenseItem(
        id: j['id'] as int,
        number: j['number'] as String? ?? '',
        description: j['description'] as String? ?? '',
        amount: _d(j['amount']),
        spentOn: DateTime.parse(j['spent_on'] as String),
        source: j['source'] as String? ?? 'account',
        sourceLabel: j['source_label'] as String? ?? '',
        category: j['category'] as String?,
        payee: j['payee'] as String?,
        reference: j['reference'] as String?,
        notes: j['notes'] as String?,
        cancelled: j['cancelled'] as bool? ?? false,
        cancelReason: j['cancel_reason'] as String?,
        canCancel: j['can_cancel'] as bool? ?? false,
      );
}

/// En qué se gasta. `payee`: «ninguno», «proveedor» o «personal».
class ExpenseCategoryItem {
  const ExpenseCategoryItem({
    required this.id,
    required this.name,
    this.payee = 'ninguno',
    this.recurring = false,
    this.type = 'general',
    this.frequency = 'mensual',
    this.active = true,
    this.expensesCount = 0,
  });

  final int id;
  final String name;
  final String payee;

  /// Servicio básico / recurrente: alquiler, luz, agua… (mensual o anual).
  final bool recurring;

  /// general · basicos (servicio básico) · proveedor · personal.
  final String type;

  /// Si es servicio básico: mensual o anual.
  final String frequency;

  bool get isAnnual => recurring && frequency == 'anual';

  final bool active;
  final int expensesCount;

  factory ExpenseCategoryItem.fromJson(Map<String, dynamic> j) => ExpenseCategoryItem(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        payee: j['payee'] as String? ?? 'ninguno',
        recurring: j['recurring'] as bool? ?? false,
        type: j['type'] as String? ?? 'general',
        frequency: j['frequency'] as String? ?? 'mensual',
        active: j['active'] as bool? ?? true,
        expensesCount: j['expenses_count'] as int? ?? 0,
      );
}

/// Un turno de caja abierto, para sacar dinero del cajón.
class OpenSessionOption {
  const OpenSessionOption({required this.id, this.number, this.caja, this.expectedCash = 0});

  final int id;
  final String? number;
  final String? caja;
  final double expectedCash;

  String get label => [caja ?? 'Caja', ?number].join(' · ');

  factory OpenSessionOption.fromJson(Map<String, dynamic> j) => OpenSessionOption(
        id: j['id'] as int,
        number: j['number'] as String?,
        caja: j['caja'] as String?,
        expectedCash: _d(j['expected_cash']),
      );
}

/// De dónde puede salir el dinero: cuentas (si el plan tiene Finanzas) y
/// turnos de caja abiertos (si tiene Caja).
class PaymentSourceOptions {
  const PaymentSourceOptions({
    this.sources = const [],
    this.accounts = const [],
    this.sessions = const [],
    this.preferredSessionId,
  });

  final List<String> sources;
  final List<FinanceAccount> accounts;
  final List<OpenSessionOption> sessions;
  final int? preferredSessionId;

  factory PaymentSourceOptions.fromJson(Map<String, dynamic> j) => PaymentSourceOptions(
        sources: (j['sources'] as List? ?? const []).map((e) => '$e').toList(),
        accounts: (j['accounts'] as List? ?? const [])
            .map((e) => FinanceAccount.fromJson(e as Map<String, dynamic>))
            .toList(),
        sessions: (j['open_sessions'] as List? ?? const [])
            .map((e) => OpenSessionOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        preferredSessionId: j['preferred_session_id'] as int?,
      );
}

/// Un proveedor.
class SupplierItem {
  const SupplierItem({
    required this.id,
    required this.name,
    this.taxId,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.active = true,
    this.purchasesCount = 0,
    this.debt = 0,
  });

  final int id;
  final String name;
  final String? taxId;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool active;
  final int purchasesCount;

  /// Lo que se le debe.
  final double debt;

  factory SupplierItem.fromJson(Map<String, dynamic> j) => SupplierItem(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        taxId: j['tax_id'] as String?,
        contactName: j['contact_name'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        notes: j['notes'] as String?,
        active: j['active'] as bool? ?? true,
        purchasesCount: j['purchases_count'] as int? ?? 0,
        debt: _d(j['debt']),
      );
}

/// Una compra (en la lista y, con detalle, en su ficha).
class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.number,
    required this.purchasedOn,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    required this.statusLabel,
    this.supplier,
    this.warehouse,
    this.invoiceNumber,
    this.dueOn,
    this.subtotal = 0,
    this.discount = 0,
    this.notes,
    this.cancelReason,
    this.lines = const [],
    this.payments = const [],
  });

  final int id;
  final String number;
  final DateTime purchasedOn;
  final double total;
  final double paid;

  /// Lo que se debe todavía.
  final double balance;
  final String status;
  final String statusLabel;
  final String? supplier;
  final String? warehouse;
  final String? invoiceNumber;
  final DateTime? dueOn;
  final double subtotal;
  final double discount;
  final String? notes;
  final String? cancelReason;
  final List<PurchaseLine> lines;
  final List<PurchasePaymentItem> payments;

  bool get isCancelled => status == 'anulada';

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
        id: j['id'] as int,
        number: j['number'] as String? ?? '',
        purchasedOn: DateTime.parse(j['purchased_on'] as String),
        total: _d(j['total']),
        paid: _d(j['paid']),
        balance: _d(j['balance']),
        status: j['status'] as String? ?? 'pendiente',
        statusLabel: j['status_label'] as String? ?? '',
        supplier: j['supplier'] as String?,
        warehouse: j['warehouse'] as String?,
        invoiceNumber: j['invoice_number'] as String?,
        dueOn: j['due_on'] == null ? null : DateTime.parse(j['due_on'] as String),
        subtotal: _d(j['subtotal']),
        discount: _d(j['discount']),
        notes: j['notes'] as String?,
        cancelReason: j['cancel_reason'] as String?,
        lines: (j['items'] as List? ?? const [])
            .map((e) => PurchaseLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: (j['payments'] as List? ?? const [])
            .map((e) => PurchasePaymentItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PurchaseLine {
  const PurchaseLine({required this.product, required this.quantity, required this.unitCost, required this.total});

  final String product;
  final double quantity;
  final double unitCost;
  final double total;

  factory PurchaseLine.fromJson(Map<String, dynamic> j) => PurchaseLine(
        product: j['product'] as String? ?? '',
        quantity: _d(j['quantity']),
        unitCost: _d(j['unit_cost']),
        total: _d(j['total']),
      );
}

class PurchasePaymentItem {
  const PurchasePaymentItem({
    required this.amount,
    required this.paidOn,
    required this.sourceLabel,
    this.reference,
    this.cancelled = false,
  });

  final double amount;
  final DateTime paidOn;
  final String sourceLabel;
  final String? reference;
  final bool cancelled;

  factory PurchasePaymentItem.fromJson(Map<String, dynamic> j) => PurchasePaymentItem(
        amount: _d(j['amount']),
        paidOn: DateTime.parse(j['paid_on'] as String),
        sourceLabel: j['source_label'] as String? ?? '',
        reference: j['reference'] as String?,
        cancelled: j['cancelled'] as bool? ?? false,
      );
}

/// Un producto para comprar, con su último costo.
class PurchasableProduct {
  const PurchasableProduct({required this.id, required this.name, this.cost = 0, this.trackStock = true});

  final int id;
  final String name;
  final double cost;
  final bool trackStock;

  factory PurchasableProduct.fromJson(Map<String, dynamic> j) => PurchasableProduct(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        cost: _d(j['cost']),
        trackStock: j['track_stock'] as bool? ?? true,
      );
}

/// Fecha para la API: «2026-11-03».
String apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Fecha para la pantalla: «03/11/2026».
String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Un servicio básico en el control del mes (`GET /finance/basics`).
class BasicServiceStatus {
  const BasicServiceStatus({
    required this.id,
    required this.name,
    required this.paid,
    this.annual = false,
    this.amount = 0,
    this.lastAmount,
    this.nextDueOn,
  });

  final int id;
  final String name;
  final bool paid;
  final bool annual;

  /// Lo pagado en el mes (o, si es anual, en los últimos 12 meses).
  final double amount;

  /// El último pago, como sugerencia del importe.
  final double? lastAmount;

  /// Anual: cuándo vuelve a tocar.
  final DateTime? nextDueOn;

  factory BasicServiceStatus.fromJson(Map<String, dynamic> j) => BasicServiceStatus(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        paid: j['status'] == 'pagado',
        annual: j['frequency'] == 'anual',
        amount: (j['paid'] as num?)?.toDouble() ?? 0,
        lastAmount: (j['last_amount'] as num?)?.toDouble(),
        nextDueOn: j['next_due_on'] is String ? DateTime.parse(j['next_due_on'] as String) : null,
      );
}

/// El control de los servicios básicos de un mes.
class BasicServicesMonth {
  const BasicServicesMonth({
    required this.month,
    required this.label,
    this.previous,
    this.next,
    this.services = const [],
    this.paidCount = 0,
    this.pendingCount = 0,
    this.totalPaid = 0,
  });

  /// YYYY-MM
  final String month;
  final String label;
  final String? previous;

  /// null si es el mes en curso (no se mira el futuro).
  final String? next;
  final List<BasicServiceStatus> services;
  final int paidCount;
  final int pendingCount;
  final double totalPaid;

  factory BasicServicesMonth.fromJson(Map<String, dynamic> j) => BasicServicesMonth(
        month: j['month'] as String? ?? '',
        label: j['label'] as String? ?? '',
        previous: j['previous'] as String?,
        next: j['next'] as String?,
        services: (j['services'] as List? ?? [])
            .map((e) => BasicServiceStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        paidCount: (j['paid_count'] as num?)?.toInt() ?? 0,
        pendingCount: (j['pending_count'] as num?)?.toInt() ?? 0,
        totalPaid: (j['total_paid'] as num?)?.toDouble() ?? 0,
      );
}

/// Lo que se le debe a una persona en comisiones (`GET /commissions/pending`),
/// de cualquier fecha: no depende del periodo que se mire.
class PendingCommission {
  const PendingCommission({
    required this.personalId,
    required this.name,
    required this.count,
    required this.total,
    this.tips = 0,
    required this.since,
  });

  final int personalId;
  final String name;

  /// Cuántas comisiones sin liquidar.
  final int count;
  final double total;

  /// Propinas del mismo tramo: se pueden sumar al pago.
  final double tips;

  /// La comisión pendiente más antigua.
  final DateTime since;

  factory PendingCommission.fromJson(Map<String, dynamic> j) => PendingCommission(
        personalId: j['personal_id'] as int,
        name: j['name'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        tips: (j['tips'] as num?)?.toDouble() ?? 0,
        since: DateTime.parse(j['since'] as String),
      );
}

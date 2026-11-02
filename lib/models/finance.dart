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
    this.active = true,
    this.expensesCount = 0,
  });

  final int id;
  final String name;
  final String payee;
  final bool active;
  final int expensesCount;

  factory ExpenseCategoryItem.fromJson(Map<String, dynamic> j) => ExpenseCategoryItem(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        payee: j['payee'] as String? ?? 'ninguno',
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

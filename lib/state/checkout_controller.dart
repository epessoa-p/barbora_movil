import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/service.dart';

/// La comanda: lo que se va a cobrar.
///
/// **La clave de idempotencia se genera una sola vez por comanda**, no por
/// intento. Ése es el punto: si el cobro se va por un agujero de red y el
/// barbero le da otra vez, llega la misma clave y el servidor devuelve la venta
/// original en lugar de cobrar dos veces. Sólo al vaciar la comanda se genera
/// una nueva.
class CheckoutController extends ChangeNotifier {
  CheckoutController({required this.api});

  final ApiClient api;

  /// Barberos a los que atribuir un servicio en la comanda (para comisiones).
  List<StaffMember> staff = const [];

  /// Carga los barberos una sola vez; si falla, la comanda igual se puede cobrar
  /// (la atribución por línea es opcional).
  Future<void> loadStaff() async {
    if (staff.isNotEmpty) return;
    try {
      final body = await api.get('/staff');
      staff = (body['data'] as List? ?? [])
          .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } on ApiException {
      // Silencioso: sin barberos cargados, la línea simplemente no se atribuye.
    }
  }

  StaffMember? staffById(int? id) =>
      id == null ? null : staff.where((s) => s.id == id).firstOrNull;

  /// Atribuye (o quita) el barbero de una línea de servicio.
  void setLinePersonal(CartLine line, int? personalId) {
    line.personalId = personalId;
    notifyListeners();
  }

  final List<CartLine> _lines = [];
  List<CartLine> get lines => List.unmodifiable(_lines);

  double _discount = 0;
  double get discount => _discount;

  double _tip = 0;
  double get tip => _tip;

  int? _clientId;
  String? _clientName;
  int? get clientId => _clientId;
  String? get clientName => _clientName;

  int? _personalId;
  int? get personalId => _personalId;

  int? _appointmentId;
  int? get appointmentId => _appointmentId;

  String? _notes;

  bool _busy = false;
  bool get busy => _busy;

  Sale? _lastSale;
  Sale? get lastSale => _lastSale;

  /// Se crea con la comanda y sobrevive a los reintentos.
  String _idempotencyKey = _newKey();

  bool get isEmpty => _lines.isEmpty;

  double get subtotal => _lines.fold(0, (sum, l) => sum + l.total);

  double get total => (subtotal - _discount + _tip).clamp(0, double.infinity);

  /// Lo que se ha repartido entre los métodos de pago.
  double paid(Map<String, double> payments) =>
      payments.values.fold(0, (sum, v) => sum + v);

  // ── Comanda ─────────────────────────────────────────────────────────────

  void addService(Service service, {int? personalId}) {
    final existing = _lines
        .where((l) => l.type == 'servicio' && l.id == service.id)
        .firstOrNull;

    if (existing != null) {
      existing.quantity += 1;
    } else {
      _lines.add(CartLine(
        type: 'servicio',
        id: service.id,
        name: service.name,
        unitPrice: service.price,
        personalId: personalId ?? _personalId,
      ));
    }

    notifyListeners();
  }

  /// Añade un producto. Si el producto lleva control de stock, no se deja
  /// pasar de lo que queda: el servidor lo rechazaría igual, pero es mejor
  /// avisar antes de que el barbero se lo prometa al cliente.
  ///
  /// Devuelve false si no había suficiente.
  bool addProduct(Product product) {
    final existing = _lines
        .where((l) => l.type == 'producto' && l.id == product.id)
        .firstOrNull;

    final wanted = (existing?.quantity ?? 0) + 1;

    if (product.tracksStock && wanted > (product.stock ?? 0)) {
      return false;
    }

    if (existing != null) {
      existing.quantity = wanted;
    } else {
      _lines.add(CartLine(
        type: 'producto',
        id: product.id,
        name: product.name,
        unitPrice: product.price,
        personalId: _personalId,
      ));
    }

    notifyListeners();
    return true;
  }

  void addLine(CartLine line) {
    _lines.add(line);
    notifyListeners();
  }

  void removeLine(CartLine line) {
    _lines.remove(line);
    notifyListeners();
  }

  void changeQuantity(CartLine line, double quantity) {
    if (quantity <= 0) {
      _lines.remove(line);
    } else {
      line.quantity = quantity;
    }

    notifyListeners();
  }

  void setDiscount(double value) {
    _discount = value.clamp(0, subtotal);
    notifyListeners();
  }

  void setTip(double value) {
    _tip = value < 0 ? 0 : value;
    notifyListeners();
  }

  void setClient(int? id, String? name) {
    _clientId = id;
    _clientName = name;
    notifyListeners();
  }

  void setPersonal(int? id) {
    _personalId = id;
    notifyListeners();
  }

  void setNotes(String? notes) => _notes = notes;

  /// Arranca una comanda desde una cita: cliente, barbero y servicios ya puestos.
  void startFromAppointment({
    required int appointmentId,
    int? clientId,
    String? clientName,
    int? personalId,
    required List<CartLine> lines,
  }) {
    reset();

    _appointmentId = appointmentId;
    _clientId = clientId;
    _clientName = clientName;
    _personalId = personalId;
    _lines.addAll(lines);

    notifyListeners();
  }

  /// Vacía la comanda y genera una clave nueva: a partir de aquí es otro cobro.
  void reset() {
    _lines.clear();
    _discount = 0;
    _tip = 0;
    _clientId = null;
    _clientName = null;
    _personalId = null;
    _appointmentId = null;
    _notes = null;
    _lastSale = null;
    _idempotencyKey = _newKey();

    notifyListeners();
  }

  // ── Cobro ───────────────────────────────────────────────────────────────

  /// Cobra. Devuelve null si salió bien (la venta queda en [lastSale]), o el
  /// error para que lo muestre la pantalla.
  Future<ApiException?> checkout(Map<String, double> payments) async {
    if (_lines.isEmpty) return null;

    _busy = true;
    notifyListeners();

    try {
      final body = await api.post(
        '/sales',
        // La misma clave en cada reintento de ESTA comanda.
        headers: {'Idempotency-Key': _idempotencyKey},
        body: {
          'items': _lines.map((l) => l.toRequest()).toList(),
          'payments': payments.entries
              .where((e) => e.value > 0)
              .map((e) => {'payment_method': e.key, 'amount': e.value})
              .toList(),
          'client_id': ?_clientId,
          'personal_id': ?_personalId,
          'appointment_id': ?_appointmentId,
          if (_discount > 0) 'discount': _discount,
          if (_tip > 0) 'tip': _tip,
          'notes': ?_notes,
        },
      );

      _lastSale = Sale.fromJson(body['data'] as Map<String, dynamic>);

      return null;
    } on ApiException catch (e) {
      return e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Clave única de la comanda. No hace falta un UUID criptográfico: sólo tiene
  /// que ser distinta de las demás claves de esta barbería.
  static String _newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

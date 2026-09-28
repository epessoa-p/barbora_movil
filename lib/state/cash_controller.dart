import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/cash.dart';

/// El turno de caja: abrirlo, mover dinero y arquearlo.
class CashController extends ChangeNotifier {
  CashController({required this.api});

  final ApiClient api;

  CashSession? _session;
  CashSession? get session => _session;

  List<Caja> _cajas = const [];
  List<Caja> get cajas => _cajas;

  bool _loading = false;
  bool get loading => _loading;

  bool _busy = false;
  bool get busy => _busy;

  ApiException? _error;
  ApiException? get error => _error;

  bool get hasOpenSession => _session?.isOpen ?? false;

  /// Cajas en las que se puede abrir turno ahora mismo.
  List<Caja> get availableCajas => _cajas.where((c) => !c.isOpen).toList();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final body = await api.get('/cash/session');
      final data = body['data'] as Map<String, dynamic>?;

      _session = data == null ? null : CashSession.fromJson(data);

      // Las cajas solo hacen falta si no hay turno: son para elegir cuál abrir.
      if (_session == null) {
        final cajas = await api.get('/cash/cajas');
        _cajas = (cajas['data'] as List? ?? [])
            .map((e) => Caja.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } on ApiException catch (e) {
      _error = e;
      _session = null;
      _cajas = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Devuelve null si salió bien, o el error para que lo muestre la pantalla.
  Future<ApiException?> open({
    required int cajaId,
    required double openingAmount,
    String? notes,
  }) async {
    return _run(() async {
      final body = await api.post('/cash/session', body: {
        'caja_id': cajaId,
        'opening_amount': openingAmount,
        'opening_notes': ?notes,
      });

      _session = CashSession.fromJson(body['data'] as Map<String, dynamic>);
    });
  }

  Future<ApiException?> close({required double countedAmount, String? notes}) async {
    final session = _session;
    if (session == null) return null;

    return _run(() async {
      final body = await api.put('/cash/session/${session.id}/close', body: {
        'closing_amount': countedAmount,
        'closing_notes': ?notes,
      });

      // El turno cerrado se conserva un momento para poder enseñar el arqueo.
      _session = CashSession.fromJson(body['data'] as Map<String, dynamic>);
    });
  }

  Future<ApiException?> addMovement({
    required String type,
    required String paymentMethod,
    required String concept,
    required double amount,
    String? reference,
  }) async {
    return _run(() async {
      await api.post('/cash/movements', body: {
        'type': type,
        'payment_method': paymentMethod,
        'concept': concept,
        'amount': amount,
        'reference': ?reference,
      });

      // Se recarga entero: el movimiento cambia los totales y el esperado.
      await _reload();
    });
  }

  /// Tras cobrar hay que refrescar: la venta metió dinero en el cajón.
  Future<void> refreshAfterSale() async {
    try {
      await _reload();
      notifyListeners();
    } on ApiException {
      // Si falla el refresco da igual: la venta ya está registrada y la caja
      // se vuelve a leer la próxima vez que se abra la pantalla.
    }
  }

  Future<void> _reload() async {
    final body = await api.get('/cash/session');
    final data = body['data'] as Map<String, dynamic>?;
    _session = data == null ? null : CashSession.fromJson(data);
  }

  /// Deja atrás el turno cerrado y vuelve a la pantalla de abrir.
  Future<void> dismissClosed() async {
    if (_session?.isOpen ?? true) return;

    _session = null;
    await load();
  }

  Future<ApiException?> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await action();
      return null;
    } on ApiException catch (e) {
      return e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

import 'dart:convert';

import 'package:barbora_movil/core/api_client.dart';
import 'package:barbora_movil/core/session.dart';
import 'package:barbora_movil/models/cash.dart';
import 'package:barbora_movil/models/me.dart';
import 'package:barbora_movil/models/product.dart';
import 'package:barbora_movil/models/sale.dart';
import 'package:barbora_movil/models/service.dart';
import 'package:barbora_movil/state/checkout_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// La comanda y el cobro.
///
/// Lo importante aquí es la clave de idempotencia: tiene que ser **la misma**
/// en cada reintento de una comanda y **distinta** entre comandas. Si se
/// generara por intento, la protección del servidor no serviría de nada.
void main() {
  late _FakeSession session;

  setUp(() => session = _FakeSession());

  /// Cliente que recuerda las cabeceras de cada POST a /sales.
  (ApiClient, List<String?>) clientRecordingKeys({int status = 201}) {
    final keys = <String?>[];

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sales') && request.method == 'POST') {
        keys.add(request.headers['Idempotency-Key']);

        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'number': 'V-000001',
              'status': 'pagada',
              'sold_at': '2026-09-26T10:00:00-04:00',
              'subtotal': 100.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 100.0,
              'items': <dynamic>[],
              'payments': <dynamic>[],
            },
          }),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });

    return (ApiClient(session: session, client: client), keys);
  }

  const corte = Service(id: 5, name: 'Corte clásico', durationMinutes: 30, price: 50);
  const barba = Service(id: 7, name: 'Barba', durationMinutes: 15, price: 20);

  group('Comanda', () {
    test('sumar el mismo servicio dos veces sube la cantidad', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.addService(corte);

      expect(checkout.lines, hasLength(1));
      expect(checkout.lines.first.quantity, 2);
      expect(checkout.subtotal, 100.0);
    });

    test('el total descuenta y suma la propina', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.addService(barba);
      checkout.setDiscount(10);
      checkout.setTip(5);

      expect(checkout.subtotal, 70.0);
      expect(checkout.total, 65.0);
    });

    test('el descuento no puede pasarse del subtotal', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.setDiscount(999);

      expect(checkout.discount, 50.0);
      expect(checkout.total, 0.0);
    });

    test('bajar la cantidad a cero quita la línea', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.changeQuantity(checkout.lines.first, 0);

      expect(checkout.isEmpty, isTrue);
    });
  });

  group('Productos en la comanda', () {
    const cera = Product(
      id: 20,
      name: 'Cera moldeadora',
      unit: 'unidad',
      price: 45,
      stock: 2,
    );

    test('se añade si hay stock', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      expect(checkout.addProduct(cera), isTrue);
      expect(checkout.addProduct(cera), isTrue);

      expect(checkout.lines.single.quantity, 2);
      expect(checkout.subtotal, 90.0);
    });

    test('no se añade más de lo que queda', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addProduct(cera);
      checkout.addProduct(cera);

      // Solo quedan 2: el tercero no entra.
      expect(checkout.addProduct(cera), isFalse,
          reason: 'Prometerle al cliente algo que no hay es peor que decir que no.');
      expect(checkout.lines.single.quantity, 2);
    });

    test('un producto sin control de stock no tiene tope', () {
      const servicio = Product(
        id: 21,
        name: 'Domicilio',
        unit: 'unidad',
        price: 100,
        tracksStock: false,
      );

      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      for (var i = 0; i < 5; i++) {
        expect(checkout.addProduct(servicio), isTrue);
      }

      expect(checkout.lines.single.quantity, 5);
    });

    test('servicios y productos conviven en la misma comanda', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.addProduct(cera);

      expect(checkout.lines, hasLength(2));
      expect(checkout.subtotal, 95.0);
    });

    test('la línea de producto viaja con su tipo', () async {
      final sent = <Map<String, dynamic>>[];

      final client = MockClient((request) async {
        if (request.method == 'POST') {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        }

        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'number': 'V-1',
              'status': 'pagada',
              'sold_at': '2026-09-26T10:00:00-04:00',
              'subtotal': 45.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 45.0,
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final checkout = CheckoutController(api: ApiClient(session: session, client: client))
        ..addProduct(cera);

      await checkout.checkout({'efectivo': 45});

      final item = (sent.first['items'] as List).first as Map<String, dynamic>;

      expect(item['type'], 'producto');
      expect(item['id'], 20);
    });
  });

  group('Cobrar una cita', () {
    test('la comanda nace con el cliente, el barbero y los servicios', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.startFromAppointment(
        appointmentId: 12,
        clientId: 3,
        clientName: 'Carlos Mendoza',
        personalId: 3,
        lines: [
          CartLine(type: 'servicio', id: 5, name: 'Corte clásico', unitPrice: 50),
          CartLine(type: 'servicio', id: 7, name: 'Barba', unitPrice: 20),
        ],
      );

      expect(checkout.appointmentId, 12);
      expect(checkout.clientName, 'Carlos Mendoza');
      expect(checkout.personalId, 3);
      expect(checkout.total, 70.0);
    });

    test('el cobro manda el id de la cita para que se marque atendida', () async {
      final sent = <Map<String, dynamic>>[];

      final client = MockClient((request) async {
        if (request.method == 'POST') {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        }

        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'number': 'V-1',
              'status': 'pagada',
              'sold_at': '2026-09-26T10:00:00-04:00',
              'subtotal': 50.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 50.0,
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final checkout = CheckoutController(api: ApiClient(session: session, client: client))
        ..startFromAppointment(
          appointmentId: 12,
          clientId: 3,
          personalId: 3,
          lines: [CartLine(type: 'servicio', id: 5, name: 'Corte', unitPrice: 50)],
        );

      await checkout.checkout({'efectivo': 50});

      expect(sent.first['appointment_id'], 12);
      expect(sent.first['client_id'], 3);
      expect(sent.first['personal_id'], 3);
    });

    test('empezar desde una cita limpia lo anterior', () {
      final (api, _) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      checkout.setTip(20);

      checkout.startFromAppointment(
        appointmentId: 12,
        lines: [CartLine(type: 'servicio', id: 7, name: 'Barba', unitPrice: 20)],
      );

      expect(checkout.lines, hasLength(1));
      expect(checkout.tip, 0.0, reason: 'La propina anterior no es de esta cita.');
      expect(checkout.total, 20.0);
    });
  });

  group('Idempotencia', () {
    test('reintentar la misma comanda manda la misma clave', () async {
      final (api, keys) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);

      // Dos intentos del mismo cobro: el primero «se pierde» y se reintenta.
      await checkout.checkout({'efectivo': 50});
      await checkout.checkout({'efectivo': 50});

      expect(keys, hasLength(2));
      expect(keys[0], isNotNull);
      expect(keys[0], keys[1],
          reason: 'Con claves distintas el servidor cobraría dos veces.');
    });

    test('una comanda nueva estrena clave', () async {
      final (api, keys) = clientRecordingKeys();
      final checkout = CheckoutController(api: api);

      checkout.addService(corte);
      await checkout.checkout({'efectivo': 50});

      // Se cierra la comanda y se empieza otra.
      checkout.reset();
      checkout.addService(barba);
      await checkout.checkout({'efectivo': 20});

      expect(keys[0], isNot(keys[1]),
          reason: 'Reutilizar la clave haría que el segundo cobro no se registre.');
    });

    test('la clave tiene pinta de clave', () async {
      final (api, keys) = clientRecordingKeys();
      final checkout = CheckoutController(api: api)..addService(corte);

      await checkout.checkout({'efectivo': 50});

      expect(keys.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('Cobro', () {
    test('solo se mandan los métodos con importe', () async {
      final sent = <Map<String, dynamic>>[];

      final client = MockClient((request) async {
        if (request.method == 'POST') {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        }

        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'number': 'V-1',
              'status': 'pagada',
              'sold_at': '2026-09-26T10:00:00-04:00',
              'subtotal': 50.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 50.0,
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final checkout = CheckoutController(api: ApiClient(session: session, client: client))
        ..addService(corte);

      await checkout.checkout({'efectivo': 50, 'tarjeta': 0, 'qr': 0});

      final payments = sent.first['payments'] as List;

      expect(payments, hasLength(1));
      expect(payments.first['payment_method'], 'efectivo');
    });

    test('no se manda el precio: lo pone el servidor', () async {
      final sent = <Map<String, dynamic>>[];

      final client = MockClient((request) async {
        if (request.method == 'POST') {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        }

        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'number': 'V-1',
              'status': 'pagada',
              'sold_at': '2026-09-26T10:00:00-04:00',
              'subtotal': 50.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 50.0,
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final checkout = CheckoutController(api: ApiClient(session: session, client: client))
        ..addService(corte);

      await checkout.checkout({'efectivo': 50});

      final item = (sent.first['items'] as List).first as Map<String, dynamic>;

      expect(item.containsKey('unit_price'), isFalse,
          reason: 'El precio lo decide el catálogo del servidor, no el móvil.');
      expect(item['id'], 5);
      expect(item['quantity'], 1);
    });

    test('un error del servidor se devuelve, no se traga', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'message': 'Los pagos no cuadran.',
              'errors': {
                'payments': ['Los pagos suman Bs 40.00 y el total es Bs 50.00.'],
              },
            }),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));

      final checkout = CheckoutController(api: ApiClient(session: session, client: client))
        ..addService(corte);

      final error = await checkout.checkout({'efectivo': 40});

      expect(error, isNotNull);
      expect(error!.message, 'Los pagos no cuadran.');
      expect(checkout.lastSale, isNull, reason: 'No hubo venta.');
    });
  });

  group('Modelos de caja', () {
    test('el turno abierto se lee con sus totales', () {
      final session = CashSession.fromJson({
        'id': 3,
        'status': 'abierta',
        'is_open': true,
        'caja': {'id': 1, 'name': 'Caja principal'},
        'opened_at': '2026-09-26T08:00:00-04:00',
        'opened_by': 'Tania Molina',
        'opening_amount': 100.0,
        'duration': '3 h',
        'totals': {
          'income': 250.0,
          'expense': 30.0,
          'cash_income': 200.0,
          'cash_expense': 30.0,
          'expected_cash': 270.0,
          'net': 220.0,
        },
        'by_payment_method': <String, dynamic>{},
        'movements_count': 4,
      });

      expect(session.isOpen, isTrue);
      expect(session.openedAt.hour, 8, reason: 'La hora es la de la barbería.');
      expect(session.totals.expectedCash, 270.0);
      expect(session.isShort, isNull, reason: 'Un turno abierto no tiene diferencia.');
    });

    test('el turno cerrado trae el arqueo', () {
      final session = CashSession.fromJson({
        'id': 3,
        'status': 'cerrada',
        'is_open': false,
        'caja': {'id': 1, 'name': 'Caja principal'},
        'opened_at': '2026-09-26T08:00:00-04:00',
        'opening_amount': 100.0,
        'duration': '8 h',
        'totals': {'expected_cash': 270.0},
        'by_payment_method': <String, dynamic>{},
        'closed_at': '2026-09-26T16:00:00-04:00',
        'closing_amount': 265.0,
        'expected_amount': 270.0,
        'difference': -5.0,
        'difference_label': 'Faltante',
      });

      expect(session.isOpen, isFalse);
      expect(session.difference, -5.0);
      expect(session.isShort, isTrue);
      expect(session.differenceLabel, 'Faltante');
    });

    test('los métodos de pago llegan de la sesión, no escritos en la app', () {
      final me = Me.fromJson({
        'user': {'id': 1, 'name': 'Tania', 'email': 't@x.test'},
        'permissions': <dynamic>[],
        'payment_methods': [
          {'slug': 'efectivo', 'name': 'Efectivo', 'counts_as_cash': true, 'requires_reference': false},
          {'slug': 'tigo_money', 'name': 'Tigo Money', 'counts_as_cash': false, 'requires_reference': true},
        ],
      });

      expect(me.paymentMethods, hasLength(2));
      expect(me.paymentMethods.last.name, 'Tigo Money');

      // Solo el efectivo entra al cajón: Tigo Money está en la billetera.
      expect(me.cashMethods.map((m) => m.slug).toList(), ['efectivo']);
      expect(me.paymentMethods.last.requiresReference, isTrue);
    });

    test('sin métodos en la sesión hay un arranque en frío', () {
      final me = Me.fromJson({
        'user': {'id': 1, 'name': 'Tania', 'email': 't@x.test'},
        'permissions': <dynamic>[],
      });

      expect(me.paymentMethods, isEmpty);
      // La pantalla cae al fallback para no quedarse sin nada que enseñar.
      expect(PaymentMethod.fallback.first.slug, 'efectivo');
      expect(PaymentMethod.fallback.first.countsAsCash, isTrue);
    });

    test('un movimiento de salida se firma en negativo', () {
      final movement = CashMovement.fromJson({
        'id': 1,
        'type': 'egreso',
        'payment_method': 'efectivo',
        'payment_method_label': 'Efectivo',
        'concept': 'Compra de toallas',
        'amount': 35.0,
        'created_at': '2026-09-26T11:00:00-04:00',
      });

      expect(movement.isIncome, isFalse);
      expect(movement.signedAmount, -35.0);
    });
  });
}

class _FakeSession implements Session {
  @override
  String? get token => 'token';

  @override
  int? get companyId => 1;

  @override
  bool get hasToken => true;

  @override
  Future<void> load() async {}

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> saveCompanyId(int? companyId) async {}

  @override
  Future<void> clear() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

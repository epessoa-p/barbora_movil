import 'dart:convert';

import 'package:barbora_movil/core/api_client.dart';
import 'package:barbora_movil/core/session.dart';
import 'package:barbora_movil/main.dart';
import 'package:barbora_movil/screens/new_appointment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// El menú lateral según permisos, y reservar una cita de punta a punta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Peticiones que llegaron al servidor simulado: «GET /path?query».
  late List<String> seen;

  /// Cuerpo del último POST /appointments.
  Map<String, dynamic>? booked;

  Future<void> pumpApp(WidgetTester tester, Map<String, Object> me,
      {Map<String, Object>? agenda}) async {
    seen = [];
    booked = null;

    final session = _FakeSession()..seed(token: 't', companyId: 1);

    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      seen.add('${request.method} $path'
          '${request.url.query.isEmpty ? '' : '?${Uri.decodeQueryComponent(request.url.query)}'}');

      final Object? body = switch ('${request.method} $path') {
        'GET /me' => me,
        'GET /agenda' || 'GET /my/agenda' => agenda ?? _emptyAgenda,
        'GET /appointments/12' => {'data': _cita},
        'GET /staff' => _staff,
        'GET /booking/services' => _services,
        'GET /services' => _services,
        'GET /reports/ventas' => _reporteVentas,
        'GET /personal' => _personal,
        'GET /cargos' => _cargos,
        'GET /personal/options' => {'cargos': _cargos['data'], 'branches': const []},
        'POST /personal' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'ok',
              'data': {
                'id': 99,
                'full_name': booked!['full_name'],
                'cargo_id': booked!['cargo_id'],
                'cargo': 'Barbero',
                'bookable': booked!['bookable'] == 1 || booked!['bookable'] == true,
                'active': booked!['active'] == 1 || booked!['active'] == true,
              },
            };
          }(),
        'PUT /services/5' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'ok',
              'data': {
                'id': 5,
                'name': booked!['name'],
                'duration_minutes': booked!['duration_minutes'],
                'price': (booked!['price'] as num).toDouble(),
                'active': booked!['active'] == 1 || booked!['active'] == true,
              },
            };
          }(),
        'GET /dashboard' => _dashboard,
        'GET /service-categories' => {
            'data': [
              {'id': 1, 'name': 'Cortes'},
              {'id': 2, 'name': 'Barba'},
            ],
          },
        'POST /services' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'ok',
              'data': {
                'id': 9,
                'name': booked!['name'],
                'duration_minutes': booked!['duration_minutes'],
                'price': (booked!['price'] as num).toDouble(),
                'category_id': booked!['service_category_id'],
                'category': 'Barba',
                'active': true,
              },
            };
          }(),
        'GET /cash/session' => {'data': null, 'message': 'No hay ningún turno de caja abierto.'},
        'GET /cash/cajas' => {
            'data': [
              {'id': 1, 'name': 'Caja principal', 'is_open': false},
            ],
          },
        'GET /cash/sessions' => {'data': [_turnoCerrado]},
        'GET /cash/sessions/3' => {'data': _turnoCerrado},
        'GET /inventory/products' => _inventario,
        'GET /inventory/options' => _inventarioOpciones,
        'GET /inventory/products/20' => {'data': _cera},
        'POST /inventory/movements' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'Entrada registrada: «CERA MATE» queda en 12 unidades en «Central».',
              'data': {..._cera, 'stock': 12.0, 'stock_label': '12 unidades', 'low_stock': false},
            };
          }(),
        'GET /sales' => _ventas,
        'GET /sales/7' => {'data': _venta},
        'PATCH /sales/7/cancel' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'Venta V-0007 anulada.',
              'settled_commissions': 0,
              'data': {
                ..._venta,
                'status': 'anulada',
                'cancel_reason': booked!['cancel_reason'],
                'cancelled_by': 'Lucía Recepción',
                'cancelled_at': '2026-10-22T18:00:00-04:00',
              },
            };
          }(),
        'GET /agenda-blocks' => _bloqueos,
        'POST /agenda-blocks' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'Bloqueo creado. Ojo: ya hay 1 cita reservada dentro de ese periodo.',
              'clashes': 1,
              'data': (_bloqueos['data'] as List).first,
            };
          }(),
        'GET /clients/3' => {'data': _clientDetail},
        'PUT /clients/3' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'Cliente actualizado.',
              'data': {..._clientDetail, ...booked!},
            };
          }(),
        'GET /booking/slots' => {'data': ['09:00', '09:30', '10:00']},
        'GET /clients' => _clients,
        'POST /appointments' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {'message': 'ok', 'data': _created};
          }(),
        'PUT /appointments/12' => () {
            booked = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'message': 'ok',
              'data': {..._cita, 'starts_at': '2026-10-02T10:00:00-04:00'},
            };
          }(),
        _ => null,
      };

      if (body == null) {
        return http.Response(jsonEncode({'error': 'not_found'}), 404,
            headers: {'content-type': 'application/json'});
      }

      return http.Response(jsonEncode(body), request.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.pumpWidget(
      BarboraApp(session: session, api: ApiClient(session: session, client: client)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
  }

  Finder inDrawer(String text) =>
      find.descendant(of: find.byType(Drawer), matching: find.text(text));

  /// Abre el menú y toca una sección, haciendo scroll si quedó fuera de vista
  /// (la lista del drawer es perezosa y no construye lo que no se ve).
  Future<void> tapDrawer(WidgetTester tester, String label) async {
    await openDrawer(tester);
    await tester.scrollUntilVisible(
      inDrawer(label),
      120,
      scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(inDrawer(label));
    await tester.pumpAndSettle();
  }

  /// Arranca la app y abre «Administración» (abajo del menú, junto a
  /// «Cerrar sesión»); si se indica, entra además en ese cuadro.
  Future<void> openAdmin(WidgetTester tester, Map<String, Object> me, [String? card]) async {
    await pumpApp(tester, me);
    await openDrawer(tester);
    await tester.tap(inDrawer('Administración'));
    await tester.pumpAndSettle();

    if (card != null) {
      await tester.tap(find.text(card));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('un barbero sin más permisos solo ve lo suyo en el menú', (tester) async {
    await pumpApp(tester, _meBarbero);

    expect(find.text('Nueva cita'), findsNothing, reason: 'Sin appointments.create no hay botón.');

    await openDrawer(tester);

    expect(inDrawer('Agenda'), findsOneWidget);
    expect(inDrawer('Comisiones'), findsOneWidget);
    // El perfil ya no está en el drawer: se abre por el botón del AppBar.
    expect(inDrawer('Mi perfil'), findsNothing);
    expect(inDrawer('Caja'), findsNothing);
    expect(inDrawer('Cobrar'), findsNothing);
    expect(inDrawer('Nueva cita'), findsNothing);
    expect(inDrawer('Cerrar sesión'), findsOneWidget);
    expect(inDrawer('Administración'), findsNothing, reason: 'Sin permisos administrativos no sale.');
  });

  testWidgets('Administración muestra solo los cuadros que el permiso deja ver', (tester) async {
    await openAdmin(tester, _meRecepcion);

    // Recepción: personal sí; empresa, sucursales, cajas y
    // métodos de pago no (no tiene esos permisos).
    expect(find.text('Reportes'), findsNothing, reason: 'Reportes va en el menú, no en Administración.');
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Mi empresa'), findsNothing);
    expect(find.text('Sucursales'), findsNothing);
    expect(find.text('Cajas'), findsNothing);
    expect(find.text('Métodos de pago'), findsNothing);
  });

  testWidgets('el perfil se abre con el botón del AppBar', (tester) async {
    await pumpApp(tester, _meBarbero);

    await tester.tap(find.byTooltip('Mi perfil'));
    await tester.pumpAndSettle();

    // La pantalla de perfil quedó abierta con su propia barra.
    expect(find.widgetWithText(AppBar, 'Mi perfil'), findsOneWidget);
  });

  testWidgets('recepción ve las acciones y la caja, pero no comisiones', (tester) async {
    await pumpApp(tester, _meRecepcion);

    expect(find.widgetWithText(FloatingActionButton, 'Nueva cita'), findsOneWidget);

    await openDrawer(tester);

    expect(inDrawer('Nueva cita'), findsOneWidget);
    expect(inDrawer('Cobrar'), findsOneWidget);

    // El menú ya no cabe entero: lo de abajo se ve haciendo scroll.
    await tester.scrollUntilVisible(
      inDrawer('Caja'),
      120,
      scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first,
    );
    expect(inDrawer('Caja'), findsOneWidget);
    expect(inDrawer('Comisiones'), findsNothing, reason: 'Sin ficha de personal no hay comisiones.');
  });

  testWidgets('el permiso no basta si el plan no incluye el módulo', (tester) async {
    await pumpApp(tester, {
      ..._meRecepcion,
      'plan': {'name': 'Básico', 'modules': ['agenda', 'clientes']},
    });

    await openDrawer(tester);

    expect(inDrawer('Caja'), findsNothing);
    expect(inDrawer('Cobrar'), findsNothing);
    expect(inDrawer('Nueva cita'), findsOneWidget);
  });

  testWidgets('la agenda pasa a semana y se filtra por barbero', (tester) async {
    await pumpApp(tester, _meRecepcion, agenda: {
      ..._emptyAgenda,
      'staff': [
        {'id': 3, 'full_name': 'Tania Molina', 'agenda_color': '#E64A38'},
        {'id': 5, 'full_name': 'Diego Rojas', 'agenda_color': '#3B82F6'},
      ],
    });

    // Semana: pide lunes a domingo de una vez y lista los 7 días.
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    final week = seen.lastWhere((r) => r.startsWith('GET /agenda'));
    expect(week, contains('to='));
    expect(find.text('Sin citas'), findsWidgets);

    // Barbero: el filtro viaja como personal_id.
    await tester.tap(find.byKey(const Key('agenda-barber')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diego Rojas').last);
    await tester.pumpAndSettle();

    final filtered = seen.lastWhere((r) => r.startsWith('GET /agenda'));
    expect(filtered, contains('personal_id=5'));
    expect(filtered, contains('to='), reason: 'Sigue en semana.');

    // «Todos» quita el filtro.
    await tester.tap(find.byKey(const Key('agenda-barber')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos').last);
    await tester.pumpAndSettle();

    expect(seen.lastWhere((r) => r.startsWith('GET /agenda')), isNot(contains('personal_id')));
  });

  testWidgets('inventario: stock bajo, ficha y entrada de mercadería', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await tapDrawer(tester, 'Inventario');

    expect(find.text('CERA MATE'), findsOneWidget);
    expect(find.text('Stock bajo (1)'), findsOneWidget);
    expect(find.text('reponer'), findsOneWidget);

    await tester.tap(find.text('CERA MATE'));
    await tester.pumpAndSettle();

    expect(find.text('2 unidades'), findsOneWidget);
    expect(find.textContaining('reponer · mín. 3'), findsOneWidget);

    await tester.tap(find.text('Entrada'));
    await tester.pumpAndSettle();

    expect(find.text('Registrar entrada'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '10');
    await tester.dragUntilVisible(find.text('Registrar'), find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();

    expect(booked!['type'], 'entrada');
    expect(booked!['product_id'], 20);
    expect(booked!['warehouse_id'], 1, reason: 'Con un solo almacén se usa ese, sin preguntar.');
    expect(booked!['quantity'], 10);
    expect(booked!['reason'], 'compra');
    expect(find.textContaining('queda en 12 unidades'), findsOneWidget);
  });

  testWidgets('el historial de ventas abre el comprobante y anula', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await tapDrawer(tester, 'Ventas');

    expect(seen.any((r) => r.startsWith('GET /sales?from=')), isTrue);
    expect(find.text('V-0007'), findsOneWidget);

    await tester.tap(find.text('V-0007'));
    await tester.pumpAndSettle();

    expect(find.text('Comprobante'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Anular venta'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Anular venta'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Motivo (opcional)'), 'Cobro duplicado');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    expect(booked!['cancel_reason'], 'Cobro duplicado');
    expect(find.text('ANULADA'), findsOneWidget);
    expect(find.text('Anular venta'), findsNothing, reason: 'Una venta anulada no se anula otra vez.');
  });

  testWidgets('se lista y se crea un bloqueo de agenda', (tester) async {
    await pumpApp(tester, _meRecepcion);
    // Los bloqueos son una pestaña de abajo de la agenda.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Bloqueos')));
    await tester.pumpAndSettle();

    expect(find.text('Vacaciones de Tania'), findsOneWidget);
    expect(find.text('02/11/2026 – 06/11/2026'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo bloqueo'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Año nuevo');
    await tester.scrollUntilVisible(find.text('Crear bloqueo'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear bloqueo'));
    await tester.pumpAndSettle();

    expect(booked!['title'], 'Año nuevo');
    expect(booked!['all_day'], isTrue);
    expect(booked!['personal_id'], isNull, reason: 'Recepción sin ficha parte de toda la barbería.');
    expect(booked!.containsKey('start_time'), isFalse, reason: 'Todo el día no manda horas.');

    // El aviso de citas que caen dentro llega a la pantalla.
    expect(find.textContaining('ya hay 1 cita'), findsOneWidget);
  });

  testWidgets('se reserva una cita eligiendo de las horas libres', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nueva cita'));
    await tester.pumpAndSettle();

    expect(find.byType(NewAppointmentScreen), findsOneWidget);
    expect(find.text('Falta el cliente'), findsOneWidget);

    // Cliente, desde el buscador.
    await tester.tap(find.text('Elegir cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carlos Mendoza'));
    await tester.pumpAndSettle();

    // Con dos barberos hay que elegir; con uno se habría preseleccionado.
    expect(find.text('Falta el barbero'), findsOneWidget);
    await tester.tap(find.text('Tania'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corte clásico'));
    await tester.pumpAndSettle();

    // Las horas salen del servidor, con el barbero y los servicios elegidos.
    expect(
      seen.any((r) => r.startsWith('GET /booking/slots') &&
          r.contains('personal_id=3') && r.contains('services[0]=5')),
      isTrue,
    );

    await tester.scrollUntilVisible(
      find.text('09:30'),
      200,
      scrollable: find
          .descendant(of: find.byType(NewAppointmentScreen), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('09:30'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reservar cita'));
    await tester.pumpAndSettle();

    expect(booked, isNotNull);
    expect(booked!['client_id'], 3);
    expect(booked!['personal_id'], 3);
    expect(booked!['time'], '09:30');
    expect(booked!['services'], [5]);

    // De vuelta en la agenda, con aviso.
    expect(find.byType(NewAppointmentScreen), findsNothing);
    expect(find.textContaining('Cita reservada'), findsOneWidget);
  });

  testWidgets('en el cobro se fija descuento y se elige cliente', (tester) async {
    await pumpApp(tester, _meRecepcion);

    // Ir a Cobrar desde el menú.
    await openDrawer(tester);
    await tester.tap(inDrawer('Cobrar'));
    await tester.pumpAndSettle();

    // Añadir un servicio a la comanda (antes de añadirlo solo está en el
    // catálogo, así que el texto es único).
    await tester.tap(find.text('Corte clásico'));
    await tester.pumpAndSettle();
    expect(find.text('Bs 50.00'), findsWidgets);

    // Fijar un descuento de 10 desde el diálogo.
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Aplicar'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '10',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    // El total baja a 40 y el descuento queda a la vista.
    expect(find.text('Bs -10.00'), findsOneWidget);
    expect(find.text('Bs 40.00'), findsOneWidget);

    // Elegir cliente desde la ficha de la comanda.
    await tester.tap(find.text('Cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carlos Mendoza'));
    await tester.pumpAndSettle();
    expect(find.text('Carlos Mendoza'), findsOneWidget);
  });

  testWidgets('se abre la ficha de un cliente desde la sección Clientes', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await openDrawer(tester);
    await tester.tap(inDrawer('Clientes'));
    await tester.pumpAndSettle();

    // La lista de clientes (de /clients).
    expect(find.text('Carlos Mendoza'), findsWidgets);

    await tester.tap(find.text('Carlos Mendoza').first);
    await tester.pumpAndSettle();

    // La ficha, con su resumen y sus últimas citas (de /clients/3).
    expect(find.text('Ficha del cliente'), findsOneWidget);
    expect(find.text('5'), findsOneWidget, reason: 'visitas');
    expect(find.text('Degradado bajo, máquina 1'), findsOneWidget);
    expect(find.text('1 por venir'), findsOneWidget);
    expect(find.textContaining('Corte clásico'), findsWidgets);
  });

  testWidgets('se edita la ficha de un cliente', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await tapDrawer(tester, 'Clientes');

    await tester.tap(find.text('Carlos Mendoza').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    // El formulario llega relleno con lo que ya se sabía.
    expect(find.text('Editar cliente'), findsOneWidget);
    expect(find.text('9876543'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Teléfono'), '70000001');
    await tester.enterText(find.widgetWithText(TextField, 'Alergias'), 'Tinte con amoníaco');
    await tester.dragUntilVisible(find.text('Guardar cambios'), find.byType(ListView).last, const Offset(0, -200));
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(booked!['phone'], '70000001');
    expect(booked!['allergies'], 'Tinte con amoníaco');
    expect(booked!['full_name'], 'CARLOS MENDOZA', reason: 'El nombre se guarda en mayúsculas.');
    expect(booked!['document_number'], '9876543', reason: 'Lo que no se tocó se manda igual.');
    expect(find.text('Ficha del cliente'), findsOneWidget, reason: 'Vuelve a la ficha.');
  });

  testWidgets('la sección Servicios lista el catálogo', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await tapDrawer(tester, 'Servicios');

    expect(find.text('Corte clásico'), findsOneWidget);
    expect(find.text('Barba'), findsOneWidget);
  });

  testWidgets('el jefe (dashboard.view) entra al Inicio', (tester) async {
    await pumpApp(tester, {
      ..._meRecepcion,
      'permissions': [...(_meRecepcion['permissions']! as List), 'dashboard.view'],
    });

    expect(seen.contains('GET /dashboard'), isTrue);
    expect(find.widgetWithText(AppBar, 'Inicio'), findsOneWidget);
    expect(find.text('Bs 320.00'), findsOneWidget);
    expect(find.text('+28 % vs ayer'), findsOneWidget);
    expect(find.text('Citas de hoy'.toUpperCase()), findsOneWidget);

    // La tarjeta de citas lleva a la Agenda.
    await tester.tap(find.text('CITAS DE HOY'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Agenda'), findsOneWidget);
  });

  testWidgets('sin dashboard.view la app abre en la Agenda', (tester) async {
    await pumpApp(tester, _meRecepcion);

    expect(seen.contains('GET /dashboard'), isFalse);
    expect(find.widgetWithText(AppBar, 'Agenda'), findsOneWidget);

    await openDrawer(tester);
    expect(inDrawer('Inicio'), findsNothing);
  });

  testWidgets('se crea un servicio con su categoría', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await tapDrawer(tester, 'Servicios');

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo servicio'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo servicio'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Perfilado de barba');
    await tester.tap(find.text('Sin categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barba').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '25');
    await tester.enterText(find.widgetWithText(TextField, 'Duración (min)'), '20');

    await tester.dragUntilVisible(find.text('Crear servicio'), find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear servicio'));
    await tester.pumpAndSettle();

    expect(seen.contains('POST /services'), isTrue);
    expect(booked!['name'], 'PERFILADO DE BARBA');
    expect(booked!['service_category_id'], 2);
    expect(booked!['price'], 25);
    expect(booked!['duration_minutes'], 20);
    expect(find.textContaining('creado'), findsOneWidget);
  });

  testWidgets('caja: se revisa un turno anterior con su arqueo', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await tapDrawer(tester, 'Caja');

    await tester.dragUntilVisible(find.text('Turnos anteriores'), find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turnos anteriores'));
    await tester.pumpAndSettle();

    expect(find.text('Turnos de caja'), findsOneWidget);
    expect(find.text('Faltante'), findsOneWidget);
    expect(find.text('−Bs 5.00'), findsOneWidget);

    await tester.tap(find.text('Faltante'));
    await tester.pumpAndSettle();

    expect(find.text('Turno de caja'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Venta V-0001'), find.byType(ListView).last, const Offset(0, -200));
    expect(find.text('Faltó cambio'), findsOneWidget);
    expect(find.text('Venta V-0001'), findsOneWidget);
  });

  testWidgets('se edita el precio de un servicio', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await tapDrawer(tester, 'Servicios');

    await tester.tap(find.text('Corte clásico'));
    await tester.pumpAndSettle();

    expect(find.text('Editar servicio'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '65');
    // La galería de fotos deja el botón más abajo: hay que bajar hasta él.
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Guardar cambios'), 200,
        scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    // Se guardó con PUT y el precio nuevo.
    expect(seen.any((r) => r == 'PUT /services/5'), isTrue);
    expect(booked!['price'], 65);
    // De vuelta en la lista.
    expect(find.text('Editar servicio'), findsNothing);
  });

  testWidgets('Reportes (abajo del menú) abre un reporte', (tester) async {
    await pumpApp(tester, _meRecepcion);
    await openDrawer(tester);
    await tester.tap(inDrawer('Reportes'));
    await tester.pumpAndSettle();

    // La portada con las tarjetas.
    expect(find.text('Ventas'), findsOneWidget);
    expect(find.text('Barberos'), findsOneWidget);

    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();

    // El reporte, con su resumen, su gráfico y su tabla.
    expect(seen.any((r) => r.startsWith('GET /reports/ventas')), isTrue);
    expect(find.text('Este mes'), findsWidgets);
    expect(find.text('Bs 840.00'), findsOneWidget);
    expect(find.text('VENTAS POR DÍA'), findsOneWidget);
    expect(find.text('POR MÉTODO DE PAGO'), findsOneWidget);
  });

  testWidgets('Personal (en Administración) lista y abre el alta', (tester) async {
    await openAdmin(tester, _meRecepcion, 'Personal');

    // Lista (activos e inactivos).
    expect(find.text('Tania Molina'), findsOneWidget);
    expect(find.text('Diego Inactivo'), findsOneWidget);

    // Alta de un barbero.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo personal'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo personal'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre completo'), 'Marco Vaca');
    // Elegir cargo del desplegable.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbero').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Crear personal'));
    await tester.pumpAndSettle();

    expect(seen.any((r) => r == 'POST /personal'), isTrue);
    expect(booked!['full_name'], 'MARCO VACA', reason: 'Los nombres se guardan en mayúsculas.');
    expect(booked!['cargo_id'], 1);
    expect(find.text('MARCO VACA'), findsOneWidget);
  });

  testWidgets('en el cobro se asigna un barbero a un servicio', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await openDrawer(tester);
    await tester.tap(inDrawer('Cobrar'));
    await tester.pumpAndSettle();

    // Añadir un servicio a la comanda.
    await tester.tap(find.text('Corte clásico'));
    await tester.pumpAndSettle();

    // La línea de servicio ofrece asignar barbero.
    expect(find.text('Asignar barbero'), findsOneWidget);
    await tester.tap(find.text('Asignar barbero'));
    await tester.pumpAndSettle();

    // La hoja lista los barberos (de /staff) y se elige uno.
    await tester.tap(find.text('Tania Molina').last);
    await tester.pumpAndSettle();

    // El nombre del barbero queda en la línea.
    expect(find.text('Tania Molina'), findsOneWidget);
    expect(find.text('Asignar barbero'), findsNothing);
  });

  testWidgets('se reprograma una cita desde su detalle', (tester) async {
    await pumpApp(tester, _meRecepcion, agenda: _agendaConCita);

    // Entrar al detalle de la cita.
    await tester.tap(find.text('Carlos Mendoza'));
    await tester.pumpAndSettle();

    // Reprogramar abre el formulario con los datos ya puestos.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reprogramar'));
    await tester.pumpAndSettle();

    expect(find.byType(NewAppointmentScreen), findsOneWidget);
    expect(find.text('Reprogramar cita'), findsOneWidget);
    // El cliente viene cargado: el botón de guardar no pide nada más que la hora.
    expect(find.text('Falta el cliente'), findsNothing);

    // Mover a otra hora libre.
    await tester.scrollUntilVisible(
      find.text('10:00'),
      200,
      scrollable: find
          .descendant(of: find.byType(NewAppointmentScreen), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    // Se guardó con PUT sobre la cita, no con un POST nuevo.
    expect(seen.any((r) => r == 'PUT /appointments/12'), isTrue);
    expect(seen.any((r) => r.startsWith('POST /appointments')), isFalse);
    expect(booked!['time'], '10:00');
    expect(booked!['client_id'], 3);
    expect(booked!['services'], [5]);

    expect(find.textContaining('Cita reprogramada'), findsOneWidget);
  });
}

// ── Datos ───────────────────────────────────────────────────────────────────

const _company = {
  'id': 1,
  'name': 'Barbería Demo',
  'currency': 'BOB',
  'currency_symbol': 'Bs',
  'timezone': 'America/La_Paz',
  'country': 'BO',
};

const _meBarbero = <String, Object>{
  'user': {'id': 4, 'name': 'Tania Molina', 'email': 'tania@demo.test'},
  'company': _company,
  'personal': {'id': 3, 'full_name': 'Tania Molina', 'cargo': 'Barbero', 'bookable': true},
  'role': {'slug': 'barber', 'name': 'Barbero'},
  'permissions': ['appointments.view', 'appointments.edit', 'commissions.view'],
  'plan': {'name': 'Premium', 'modules': ['agenda', 'comisiones', 'caja', 'pos']},
};

const _meRecepcion = <String, Object>{
  'user': {'id': 9, 'name': 'Lucía Recepción', 'email': 'lucia@demo.test'},
  'company': _company,
  'role': {'slug': 'receptionist', 'name': 'Recepcionista'},
  'permissions': [
    'appointments.view',
    'appointments.create',
    'appointments.edit',
    'agenda_blocks.view',
    'agenda_blocks.create',
    'clients.view',
    'clients.create',
    'clients.edit',
    'services.view',
    'services.edit',
    'services.create',
    'personal.view',
    'personal.create',
    'personal.edit',
    'cash.view',
    'sales.create',
    'sales.view',
    'sales.delete',
    'reports.view',
    'products.view',
    'products.create',
    'stock.create',
  ],
  'plan': {'name': 'Premium', 'modules': ['agenda', 'clientes', 'caja', 'pos', 'comisiones', 'estadisticas', 'inventario']},
};

const _dashboard = {
  'date': '2026-10-24',
  'agenda': {
    'total': 6,
    'pending': 3,
    'attended': 2,
    'no_show': 1,
    'cancelled': 0,
    'next': [_cita],
  },
  'sales': {
    'today': 320.0,
    'count': 5,
    'tips': 20.0,
    'average': 64.0,
    'yesterday': 250.0,
    'week': {
      'labels': ['Sá', 'Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi'],
      'data': [180.0, 0.0, 210.0, 260.0, 190.0, 250.0, 320.0],
    },
  },
  'cash': {'open': true, 'caja': 'Caja principal', 'opened_by': 'Lucía Recepción', 'expected_cash': 420.0, 'income': 320.0},
  'stock': {
    'low_count': 1,
    'items': [
      {'id': 20, 'name': 'CERA MATE', 'stock_label': '2 unidades'},
    ],
  },
};

const _turnoCerrado = {
  'id': 3,
  'status': 'cerrada',
  'is_open': false,
  'caja': {'id': 1, 'name': 'Caja principal'},
  'opened_at': '2026-10-23T08:00:00-04:00',
  'opened_by': 'Lucía Recepción',
  'opening_amount': 100.0,
  'duration': '10 h',
  'totals': {'income': 80.0, 'expense': 0.0, 'cash_income': 80.0, 'cash_expense': 0.0, 'expected_cash': 180.0, 'net': 80.0},
  'by_payment_method': {
    'efectivo': {'income': 80.0, 'expense': 0.0, 'count': 1},
  },
  'movements_count': 1,
  'closed_at': '2026-10-23T18:00:00-04:00',
  'closed_by': 'Lucía Recepción',
  'closing_amount': 175.0,
  'expected_amount': 180.0,
  'difference': -5.0,
  'difference_label': 'Faltante',
  'closing_notes': 'Faltó cambio',
  'movements': [
    {
      'id': 1,
      'type': 'ingreso',
      'payment_method': 'efectivo',
      'payment_method_label': 'Efectivo',
      'concept': 'Venta V-0001',
      'detail': 'CORTE CLÁSICO',
      'amount': 80.0,
      'reference': 'V-0001',
      'created_at': '2026-10-23T10:00:00-04:00',
      'created_by': 'Lucía Recepción',
    },
  ],
};

const _cera = {
  'id': 20,
  'name': 'CERA MATE',
  'sku': 'CM-01',
  'category_id': 1,
  'category': 'Styling',
  'unit': 'unidad',
  'unit_label': 'Unidad',
  'sale_price': 45.0,
  'cost_price': 20.0,
  'min_stock': 3.0,
  'track_stock': true,
  'is_sellable': true,
  'active': true,
  'stock': 2.0,
  'stock_label': '2 unidades',
  'low_stock': true,
  'margin_percent': 55.6,
  'stocks': [
    {'warehouse_id': 1, 'warehouse': 'Central', 'quantity': 2.0, 'quantity_label': '2 unidades'},
  ],
  'movements': [
    {
      'id': 1,
      'type': 'entrada',
      'type_label': 'Entrada',
      'reason_label': 'Compra a proveedor',
      'quantity': 2.0,
      'quantity_after': 2.0,
      'warehouse': 'Central',
      'created_by': 'Lucía Recepción',
      'created_at': '2026-10-20T10:00:00-04:00',
    },
  ],
};

const _inventario = {
  'low_count': 1,
  'data': [_cera],
};

const _inventarioOpciones = {
  'categories': [
    {'id': 1, 'name': 'Styling'},
  ],
  'warehouses': [
    {'id': 1, 'name': 'Central'},
  ],
  'units': [
    {'value': 'unidad', 'label': 'Unidad'},
    {'value': 'ml', 'label': 'Mililitros'},
  ],
  'types': [
    {'value': 'entrada', 'label': 'Entrada'},
    {'value': 'salida', 'label': 'Salida'},
    {'value': 'ajuste', 'label': 'Ajuste'},
  ],
  'reasons': [
    {'value': 'compra', 'label': 'Compra a proveedor'},
    {'value': 'consumo', 'label': 'Consumo en servicio'},
    {'value': 'merma', 'label': 'Merma o rotura'},
  ],
  'limit': {'reached': false},
};

const _ventas = {
  'summary': {'count': 1, 'total': 70.0, 'tips': 0.0, 'cancelled': 0},
  'data': [
    {
      'id': 7,
      'number': 'V-0007',
      'status': 'pagada',
      'status_label': 'Pagada',
      'total': 70.0,
      'sold_at': '2026-10-22T10:30:00-04:00',
      'client': 'CARLOS MENDOZA',
      'personal': 'TANIA MOLINA',
      'methods': ['Efectivo'],
    },
  ],
};

const _venta = {
  'id': 7,
  'number': 'V-0007',
  'status': 'pagada',
  'status_label': 'Pagada',
  'sold_at': '2026-10-22T10:30:00-04:00',
  'subtotal': 70.0,
  'discount': 0.0,
  'tip': 0.0,
  'total': 70.0,
  'client': {'id': 3, 'full_name': 'CARLOS MENDOZA'},
  'personal': {'id': 3, 'full_name': 'TANIA MOLINA'},
  'items': [
    {'id': 1, 'type': 'servicio', 'description': 'CORTE CLÁSICO', 'quantity': 1.0, 'unit_price': 70.0, 'total': 70.0},
  ],
  'payments': [
    {'payment_method': 'efectivo', 'payment_method_label': 'Efectivo', 'amount': 70.0, 'reference': null},
  ],
};

const _bloqueos = {
  'data': [
    {
      'id': 1,
      'title': 'Vacaciones de Tania',
      'reason': 'vacaciones',
      'reason_label': 'Vacaciones',
      'personal_id': 3,
      'branch_id': null,
      'branch': null,
      'scope': 'TANIA MOLINA',
      'all_day': true,
      'starts_at': '2026-11-02T00:00:00-04:00',
      'ends_at': '2026-11-06T23:59:59-04:00',
      'range_label': '02/11/2026 – 06/11/2026',
      'notes': null,
    },
  ],
  'reasons': [
    {'value': 'vacaciones', 'label': 'Vacaciones'},
    {'value': 'feriado', 'label': 'Feriado'},
    {'value': 'descanso', 'label': 'Descanso'},
  ],
  'staff': [
    {'id': 3, 'full_name': 'TANIA MOLINA'},
  ],
  'branches': [
    {'id': 1, 'name': 'Central'},
  ],
};

const _emptyAgenda = {
  'data': <dynamic>[],
  'summary': {'total': 0, 'pending': 0, 'attended': 0, 'no_show': 0, 'minutes': 0},
  'blocks': <dynamic>[],
};

const _staff = {
  'data': [
    {'id': 3, 'full_name': 'Tania Molina', 'cargo': 'Barbero', 'agenda_color': '#E64A38'},
    {'id': 5, 'full_name': 'Diego Rojas', 'cargo': 'Barbero', 'agenda_color': '#3B82F6'},
  ],
};

const _services = {
  'data': [
    {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
    {'id': 7, 'name': 'Barba', 'duration_minutes': 20, 'price': 20.0},
  ],
};

const _reporteVentas = {
  'key': 'ventas',
  'title': 'Ventas',
  'period': {
    'preset': 'mes',
    'label': 'Este mes',
    'from': '2026-10-01',
    'to': '2026-10-31',
    'presets': [
      {'key': 'hoy', 'label': 'Hoy'},
      {'key': 'mes', 'label': 'Este mes'},
    ],
  },
  'summary': [
    {'label': 'Ventas', 'value': 12, 'kind': 'int'},
    {'label': 'Total', 'value': 840.0, 'kind': 'money'},
  ],
  'charts': [
    {
      'type': 'line',
      'title': 'Ventas por día',
      'labels': ['01/10', '02/10', '03/10'],
      'data': [120.0, 300.0, 420.0],
      'kind': 'money',
    },
  ],
  'tables': [
    {
      'title': 'Por método de pago',
      'columns': [
        {'label': 'Método', 'kind': 'text', 'align': 'start'},
        {'label': 'Total', 'kind': 'money', 'align': 'end'},
      ],
      'rows': [
        ['Efectivo', 600.0],
        ['QR', 240.0],
      ],
    },
  ],
  'note': null,
};

const _cargos = {
  'data': [
    {'id': 1, 'name': 'Barbero'},
    {'id': 2, 'name': 'Recepcionista'},
  ],
};

const _personal = {
  'data': [
    {'id': 3, 'full_name': 'Tania Molina', 'cargo_id': 1, 'cargo': 'Barbero', 'bookable': true, 'active': true, 'specialty': 'Degradados'},
    {'id': 5, 'full_name': 'Diego Inactivo', 'cargo_id': 1, 'cargo': 'Barbero', 'bookable': false, 'active': false},
  ],
};

const _clients = {
  'data': [
    {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '71234567'},
    {'id': 4, 'full_name': 'Jorge Paz', 'phone': null},
  ],
};

/// Una cita viva (reservada) con un servicio, para reprogramar.
const _cita = {
  'id': 12,
  'starts_at': '2026-10-02T09:00:00-04:00',
  'ends_at': '2026-10-02T09:30:00-04:00',
  'duration_minutes': 30,
  'status': 'reservada',
  'status_label': 'Reservada',
  'is_editable': true,
  'client': {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '71234567'},
  'personal': {'id': 3, 'full_name': 'Tania Molina'},
  'services': [
    {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
  ],
  'total': 50.0,
};

const _agendaConCita = {
  'data': [_cita],
  'summary': {'total': 1, 'pending': 1, 'attended': 0, 'no_show': 0, 'minutes': 30},
  'blocks': <dynamic>[],
};

const _clientDetail = {
  'id': 3,
  'full_name': 'Carlos Mendoza',
  'phone': '71234567',
  'email': 'carlos@correo.test',
  'document_number': '9876543',
  'preferences': 'Degradado bajo, máquina 1',
  'allergies': null,
  'stats': {
    'visits': 5,
    'total_spent': 320.0,
    'upcoming': 1,
    'last_visit': '2026-09-20T11:00:00-04:00',
  },
  'recent_appointments': [
    {
      'id': 31,
      'starts_at': '2026-09-20T11:00:00-04:00',
      'ends_at': '2026-09-20T11:30:00-04:00',
      'duration_minutes': 30,
      'status': 'atendida',
      'status_label': 'Atendida',
      'is_editable': false,
      'client': {'id': 3, 'full_name': 'Carlos Mendoza'},
      'personal': {'id': 3, 'full_name': 'Tania Molina'},
      'services': [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
      ],
      'total': 50.0,
    },
  ],
};

const _created = {
  'id': 40,
  'starts_at': '2026-10-02T09:30:00-04:00',
  'ends_at': '2026-10-02T10:00:00-04:00',
  'duration_minutes': 30,
  'status': 'reservada',
  'status_label': 'Reservada',
  'is_editable': true,
  'client': {'id': 3, 'full_name': 'Carlos Mendoza'},
  'personal': {'id': 3, 'full_name': 'Tania Molina'},
  'services': [
    {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
  ],
  'total': 50.0,
};

class _FakeSession implements Session {
  String? _token;
  int? _companyId;

  void seed({String? token, int? companyId}) {
    _token = token;
    _companyId = companyId;
  }

  @override
  String? get token => _token;

  @override
  int? get companyId => _companyId;

  @override
  bool get hasToken => _token != null && _token!.isNotEmpty;

  @override
  Future<void> load() async {}

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> saveCompanyId(int? companyId) async => _companyId = companyId;

  @override
  Future<void> clear() async {
    _token = null;
    _companyId = null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

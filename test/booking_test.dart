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
        'GET /clients/3' => {'data': _clientDetail},
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

  testWidgets('la sección Servicios lista el catálogo', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await openDrawer(tester);
    await tester.tap(inDrawer('Servicios'));
    await tester.pumpAndSettle();

    expect(find.text('Corte clásico'), findsOneWidget);
    expect(find.text('Barba'), findsOneWidget);
  });

  testWidgets('se edita el precio de un servicio', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await openDrawer(tester);
    await tester.tap(inDrawer('Servicios'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corte clásico'));
    await tester.pumpAndSettle();

    expect(find.text('Editar servicio'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '65');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    // Se guardó con PUT y el precio nuevo.
    expect(seen.any((r) => r == 'PUT /services/5'), isTrue);
    expect(booked!['price'], 65);
    // De vuelta en la lista.
    expect(find.text('Editar servicio'), findsNothing);
  });

  testWidgets('la sección Reportes abre un reporte', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await tapDrawer(tester, 'Reportes');

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

  testWidgets('la sección Barberos lista y abre el alta', (tester) async {
    await pumpApp(tester, _meRecepcion);

    await tapDrawer(tester, 'Barberos');

    // Lista (activos e inactivos).
    expect(find.text('Tania Molina'), findsOneWidget);
    expect(find.text('Diego Inactivo'), findsOneWidget);

    // Alta de un barbero.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo barbero'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo barbero'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre completo'), 'Marco Vaca');
    // Elegir cargo del desplegable.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbero').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Crear barbero'));
    await tester.pumpAndSettle();

    expect(seen.any((r) => r == 'POST /personal'), isTrue);
    expect(booked!['full_name'], 'Marco Vaca');
    expect(booked!['cargo_id'], 1);
    expect(find.text('Marco Vaca'), findsOneWidget);
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
    'clients.view',
    'clients.create',
    'services.view',
    'services.edit',
    'personal.view',
    'personal.create',
    'personal.edit',
    'cash.view',
    'sales.create',
    'reports.view',
  ],
  'plan': {'name': 'Premium', 'modules': ['agenda', 'clientes', 'caja', 'pos', 'comisiones', 'estadisticas']},
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

import 'dart:convert';
import 'dart:io';

import 'package:barbora_movil/core/api_client.dart';
import 'package:barbora_movil/core/session.dart';
import 'package:barbora_movil/main.dart';
import 'package:barbora_movil/models/sale.dart';
import 'package:barbora_movil/screens/receipt_screen.dart';
import 'package:barbora_movil/state/auth_controller.dart';
import 'package:barbora_movil/theme/barbora_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Genera capturas de las pantallas en `test/screenshots/`.
///
/// No es un test de verdad: es una forma de MIRAR el resultado sin un
/// emulador. Se ejecuta a mano con:
///
/// ```bash
/// flutter test test/screenshots_test.dart --update-goldens
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sin esto el texto sale como cajas: `flutter test` no carga fuentes, y las
  // capturas no servirían para juzgar el diseño. Se registra Montserrat también
  // bajo los nombres por defecto para que se vea todo el texto.
  setUpAll(() async {
    final data = File('assets/fonts/Montserrat.ttf').readAsBytesSync();

    for (final family in ['Montserrat', 'Roboto', 'packages/Roboto']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(data)));
      await loader.load();
    }
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Map<String, Object> routes,
    _FakeSession? session,
    Future<void> Function(WidgetTester)? afterLoad,
  }) async {
    // Tamaño de un teléfono corriente.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final s = session ?? _FakeSession();

    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      final body = routes[path];

      if (body == null) {
        return http.Response(jsonEncode({'error': 'not_found'}), 404,
            headers: {'content-type': 'application/json'});
      }

      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.pumpWidget(
      BarboraApp(session: s, api: ApiClient(session: s, client: client)),
    );
    await tester.pumpAndSettle();

    if (afterLoad != null) {
      await afterLoad(tester);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('01 acceso', (tester) async {
    await shoot(tester, '01_acceso', routes: {});
  });

  testWidgets('02 elegir barberia', (tester) async {
    await shoot(tester, '02_elegir_barberia', routes: {
      '/login': {
        'token': 't',
        'user': _user,
        'companies': _twoCompanies,
        'default_company_id': null,
      },
      '/companies': {'data': _twoCompanies},
      '/me': _me,
    }, afterLoad: (t) async {
      await t.enterText(find.widgetWithText(TextFormField, 'Correo'), 'tania@demo.test');
      await t.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'x');
      await t.tap(find.widgetWithText(FilledButton, 'Entrar'));
    });
  });

  testWidgets('03 agenda', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '03_agenda',
        session: s,
        routes: {'/me': _me, '/my/agenda': _agenda, '/agenda': _agenda});
  });

  testWidgets('04 agenda de la barberia con bloqueos', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '04_agenda_barberia',
        session: s,
        routes: {'/me': _me, '/my/agenda': _agenda, '/agenda': _agendaShop},
        afterLoad: (t) async {
          await t.tap(find.text('La barbería'));
        });
  });

  testWidgets('05 comisiones', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '05_comisiones',
        session: s,
        routes: {
          '/me': _me,
          '/my/agenda': _agenda,
          '/my/commissions': _commissions,
        },
        afterLoad: (t) async {
          await openSection(t, 'Comisiones');
        });
  });

  testWidgets('06 perfil', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '06_perfil',
        session: s,
        routes: {
          '/me': _me,
          '/my/agenda': _agenda,
          '/my/schedule': _schedule,
        },
        afterLoad: (t) async {
          await t.tap(find.byTooltip('Mi perfil'));
          await t.pumpAndSettle();
        });
  });

  /// El comprobante se pinta solo, sin pasar por el cobro: montar toda la
  /// comanda desde la captura sería frágil y aquí lo que se quiere ver es cómo
  /// queda la hoja que se le enseña al cliente.
  testWidgets('09 comprobante', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final s = _FakeSession()..seed(token: 't', companyId: 1);

    // /me trae los datos de la barbería que van en el encabezado.
    final api = ApiClient(
      session: s,
      client: MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/me') ? _meConComprobante : {}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthController(api: api, session: s)..bootstrap()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BarboraTheme.light(),
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ReceiptScreen(
            sale: Sale.fromJson(_saleReceipt['data']! as Map<String, dynamic>),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/09_comprobante.png'),
    );
  });

  testWidgets('08 caja abierta', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '08_caja',
        session: s,
        routes: {
          '/me': _meCajero,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/cash/session': _cashSession,
        },
        afterLoad: (t) async {
          await openSection(t, 'Caja');
        });
  });

  testWidgets('10 menu lateral', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '10_menu',
        session: s,
        routes: {'/me': _meCompleto, '/my/agenda': _agenda, '/agenda': _agenda},
        afterLoad: (t) async {
          await t.tap(find.byIcon(Icons.menu));
        });
  });

  testWidgets('11 nueva cita', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '11_nueva_cita',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/staff': {
            'data': [
              {'id': 3, 'full_name': 'Tania Molina', 'agenda_color': '#E64A38'},
              {'id': 5, 'full_name': 'Diego Rojas', 'agenda_color': '#3B82F6'},
              {'id': 6, 'full_name': 'Marco Vaca', 'agenda_color': '#10B981'},
            ],
          },
          '/booking/services': {
            'data': [
              {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
              {'id': 7, 'name': 'Barba', 'duration_minutes': 15, 'price': 20.0},
              {'id': 8, 'name': 'Corte + lavado', 'duration_minutes': 45, 'price': 70.0},
            ],
          },
          '/booking/slots': {
            'data': ['09:00', '09:15', '10:30', '10:45', '11:00', '15:00', '15:15', '16:30'],
          },
          '/clients': {
            'data': [
              {
                'id': 3,
                'full_name': 'Carlos Mendoza',
                'phone': '71234567',
                'preferences': 'Degradado bajo, máquina 1',
              },
            ],
          },
        },
        afterLoad: (t) async {
          await t.tap(find.text('Nueva cita').last);
          await t.pumpAndSettle();
          await t.tap(find.text('Elegir cliente'));
          await t.pumpAndSettle();
          await t.tap(find.text('Carlos Mendoza'));
          await t.pumpAndSettle();
          await t.tap(find.text('Corte clásico'));
          await t.pumpAndSettle();
          await t.tap(find.text('Barba'));
          await t.pumpAndSettle();
        });
  });

  testWidgets('12 cobro con descuento', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '12_cobro',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/services': {
            'data': [
              {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
              {'id': 7, 'name': 'Barba', 'duration_minutes': 15, 'price': 20.0},
              {'id': 8, 'name': 'Corte + lavado', 'duration_minutes': 45, 'price': 70.0},
            ],
          },
          '/clients': {
            'data': [
              {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '71234567'},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Cobrar');
          // Dos servicios en la comanda.
          await t.tap(find.text('Corte clásico'));
          await t.pumpAndSettle();
          await t.tap(find.text('Barba'));
          await t.pumpAndSettle();
          // Descuento.
          await t.tap(find.text('Agregar').first);
          await t.pumpAndSettle();
          await t.enterText(
            find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
            '10',
          );
          await t.tap(find.widgetWithText(FilledButton, 'Aplicar'));
          await t.pumpAndSettle();
          // Propina.
          await t.tap(find.text('Agregar'));
          await t.pumpAndSettle();
          await t.enterText(
            find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
            '5',
          );
          await t.tap(find.widgetWithText(FilledButton, 'Aplicar'));
          await t.pumpAndSettle();
          // Cliente.
          await t.tap(find.text('Cliente'));
          await t.pumpAndSettle();
          await t.tap(find.text('Carlos Mendoza'));
          await t.pumpAndSettle();
        });
  });

  testWidgets('13 servicios', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '13_servicios',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/services': {
            'data': [
              {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0, 'category': 'Cortes', 'description': 'Tijera y máquina, lavado incluido.'},
              {'id': 6, 'name': 'Corte + diseño', 'duration_minutes': 45, 'price': 85.0, 'category': 'Cortes'},
              {'id': 7, 'name': 'Barba', 'duration_minutes': 15, 'price': 20.0, 'category': 'Barba'},
              {'id': 8, 'name': 'Perfilado con navaja', 'duration_minutes': 20, 'price': 30.0, 'category': 'Barba'},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Servicios');
        });
  });

  testWidgets('14 ficha de cliente', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '14_ficha_cliente',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/clients': {
            'data': [
              {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '71234567', 'document_number': '9876543'},
            ],
          },
          '/clients/3': {
            'data': {
              'id': 3,
              'full_name': 'Carlos Mendoza',
              'phone': '71234567',
              'email': 'carlos@correo.test',
              'document_number': '9876543',
              'preferences': 'Degradado bajo, máquina 1. Sin cera.',
              'allergies': 'Alcohol en lociones',
              'stats': {
                'visits': 8,
                'total_spent': 540.0,
                'upcoming': 1,
                'last_visit': '2026-09-20T11:00:00-04:00',
              },
              'recent_appointments': [
                {
                  'id': 31,
                  'starts_at': '2026-09-20T11:00:00-04:00',
                  'ends_at': '2026-09-20T11:40:00-04:00',
                  'duration_minutes': 40,
                  'status': 'atendida',
                  'status_label': 'Atendida',
                  'is_editable': false,
                  'client': {'id': 3, 'full_name': 'Carlos Mendoza'},
                  'personal': {'id': 3, 'full_name': 'Tania Molina'},
                  'services': [
                    {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
                    {'id': 7, 'name': 'Barba', 'duration_minutes': 10, 'price': 20.0},
                  ],
                  'total': 70.0,
                },
              ],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Clientes');
          await t.tap(find.text('Carlos Mendoza').first);
          await t.pumpAndSettle();
        });
  });

  testWidgets('15 reportes', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '15_reportes',
        session: s,
        routes: {'/me': _meCompleto, '/my/agenda': _agenda, '/agenda': _agenda},
        afterLoad: (t) async {
          await openSection(t, 'Reportes');
        });
  });

  testWidgets('16 reporte de ventas', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '16_reporte_ventas',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/reports/ventas': {
            'key': 'ventas',
            'title': 'Ventas',
            'period': {
              'preset': 'mes',
              'label': 'Este mes',
              'from': '2026-10-01',
              'to': '2026-10-31',
              'presets': [
                {'key': 'hoy', 'label': 'Hoy'},
                {'key': 'semana', 'label': 'Esta semana'},
                {'key': 'mes', 'label': 'Este mes'},
                {'key': 'mes_pasado', 'label': 'Mes pasado'},
                {'key': 'anio', 'label': 'Este año'},
              ],
            },
            'summary': [
              {'label': 'Ventas', 'value': 48, 'kind': 'int'},
              {'label': 'Total', 'value': 3240.0, 'kind': 'money'},
              {'label': 'Ticket medio', 'value': 67.5, 'kind': 'money'},
              {'label': 'Propinas', 'value': 180.0, 'kind': 'money'},
              {'label': 'Descuentos', 'value': 90.0, 'kind': 'money'},
              {'label': 'Anuladas', 'value': 2, 'kind': 'int'},
            ],
            'charts': [
              {
                'type': 'line',
                'title': 'Ventas por día',
                'labels': ['01/10', '05/10', '10/10', '15/10', '20/10', '25/10', '30/10'],
                'data': [120.0, 380.0, 210.0, 520.0, 300.0, 640.0, 410.0],
                'kind': 'money',
              },
              {
                'type': 'bar',
                'title': 'Por método de pago',
                'labels': ['Efectivo', 'QR', 'Tarjeta'],
                'data': [1980.0, 900.0, 360.0],
                'kind': 'money',
              },
            ],
            'tables': [
              {
                'title': 'Por método de pago',
                'columns': [
                  {'label': 'Método', 'kind': 'text', 'align': 'start'},
                  {'label': 'Cobros', 'kind': 'int', 'align': 'end'},
                  {'label': 'Total', 'kind': 'money', 'align': 'end'},
                ],
                'rows': [
                  ['Efectivo', 30, 1980.0],
                  ['QR', 12, 900.0],
                  ['Tarjeta', 6, 360.0],
                ],
              },
            ],
            'note': null,
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Reportes');
          await t.tap(find.text('Ventas'));
          await t.pumpAndSettle();
        });
  });

  testWidgets('17 barberos', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '17_barberos',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/personal': {
            'data': [
              {'id': 3, 'full_name': 'Tania Molina', 'cargo': 'Barbero', 'bookable': true, 'active': true, 'specialty': 'Degradados', 'agenda_color': '#E64A38'},
              {'id': 5, 'full_name': 'Diego Rojas', 'cargo': 'Barbero', 'bookable': true, 'active': true, 'agenda_color': '#3B82F6'},
              {'id': 6, 'full_name': 'Lucía Recepción', 'cargo': 'Recepcionista', 'bookable': false, 'active': true, 'agenda_color': '#10B981'},
              {'id': 7, 'full_name': 'Marco Antiguo', 'cargo': 'Barbero', 'bookable': false, 'active': false},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Barberos');
        });
  });

  testWidgets('07 detalle de cita', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '07_detalle_cita',
        session: s,
        routes: {
          '/me': _me,
          '/my/agenda': _agenda,
          '/appointments/12': {'data': (_agenda['data']! as List).first},
        },
        afterLoad: (t) async {
          await t.tap(find.text('Carlos Mendoza'));
        });
  });
}

// ── Datos de ejemplo ────────────────────────────────────────────────────────

const _user = {
  'id': 4,
  'name': 'Tania Molina',
  'email': 'tania.molina@barberiademo.test',
  'phone': null,
  'is_super_admin': false,
};

const _twoCompanies = [
  {'id': 1, 'name': 'Barbería Demo', 'currency': 'BOB'},
  {'id': 2, 'name': 'Barbería Norte', 'currency': 'BOB'},
];

const _me = {
  'user': _user,
  'company': {
    'id': 1,
    'name': 'Barbería Demo',
    'currency': 'BOB',
    'currency_symbol': 'Bs',
    'timezone': 'America/La_Paz',
    'country': 'BO',
  },
  'personal': {
    'id': 3,
    'full_name': 'Tania Molina',
    'cargo': 'Barbero',
    'bookable': true,
    'photo_url': null,
    'agenda_color': '#E64A38',
  },
  'role': {'slug': 'barber', 'name': 'Barbero'},
  'permissions': ['appointments.view', 'appointments.edit', 'commissions.view'],
  'plan': {
    'name': 'Premium',
    'modules': ['agenda', 'comisiones'],
    'module_labels': <String, String>{},
  },
  'subscription': {
    'status': 'active',
    'on_trial': false,
    'allows_write': true,
    'trial_ends_at': null,
    'current_period_end': '2026-10-22T00:00:00-04:00',
  },
};

Map<String, Object?> _cita({
  required int id,
  required String hora,
  required String fin,
  required int minutos,
  required String cliente,
  required String estado,
  required String estadoLabel,
  required List<Map<String, Object>> servicios,
  required double total,
  String barbero = 'Tania Molina',
}) =>
    {
      'id': id,
      'starts_at': '2026-09-26T$hora:00-04:00',
      'ends_at': '2026-09-26T$fin:00-04:00',
      'duration_minutes': minutos,
      'status': estado,
      'status_label': estadoLabel,
      'is_editable': estado != 'atendida' && estado != 'cancelada',
      'notes': null,
      'client': {'id': id, 'full_name': cliente, 'phone': '59171234567'},
      'personal': {'id': 3, 'full_name': barbero},
      'branch': 'Centro',
      'services': servicios,
      'total': total,
      'reminded_at': null,
    };

final _agenda = <String, Object>{
  'day': '2026-09-26',
  'personal_id': 3,
  'data': [
    _cita(
      id: 12,
      hora: '09:00',
      fin: '09:40',
      minutos: 40,
      cliente: 'Carlos Mendoza',
      estado: 'confirmada',
      estadoLabel: 'Confirmada',
      servicios: [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
        {'id': 7, 'name': 'Barba', 'duration_minutes': 10, 'price': 20.0},
      ],
      total: 70.0,
    ),
    _cita(
      id: 13,
      hora: '10:00',
      fin: '10:30',
      minutos: 30,
      cliente: 'Luis Vargas',
      estado: 'atendida',
      estadoLabel: 'Atendida',
      servicios: [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
      ],
      total: 50.0,
    ),
    _cita(
      id: 14,
      hora: '11:30',
      fin: '12:15',
      minutos: 45,
      cliente: 'Andrés Rojas',
      estado: 'reservada',
      estadoLabel: 'Reservada',
      servicios: [
        {'id': 9, 'name': 'Corte + diseño', 'duration_minutes': 45, 'price': 85.0},
      ],
      total: 85.0,
    ),
    _cita(
      id: 15,
      hora: '15:00',
      fin: '15:30',
      minutos: 30,
      cliente: 'Pedro Quiroga',
      estado: 'no_show',
      estadoLabel: 'No se presentó',
      servicios: [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
      ],
      total: 50.0,
    ),
  ],
  'summary': {'total': 4, 'pending': 2, 'attended': 1, 'no_show': 1, 'minutes': 115},
  'blocks': <dynamic>[],
};

final _agendaShop = <String, Object>{
  ..._agenda,
  'data': [
    ...(_agenda['data']! as List),
    _cita(
      id: 20,
      hora: '09:30',
      fin: '10:00',
      minutos: 30,
      cliente: 'Marco Salazar',
      estado: 'confirmada',
      estadoLabel: 'Confirmada',
      barbero: 'Iván Céspedes',
      servicios: [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
      ],
      total: 50.0,
    ),
  ],
  'blocks': [
    {
      'id': 1,
      'title': 'Almuerzo',
      'reason': 'descanso',
      'reason_label': 'Descanso',
      'personal_id': 1,
      'scope': 'Iván Céspedes',
      'all_day': false,
      'starts_at': '2026-09-26T13:00:00-04:00',
      'ends_at': '2026-09-26T14:00:00-04:00',
    },
  ],
};

const _commissions = {
  'period': {
    'from': '2026-09-01',
    'to': '2026-09-30',
    'label': '01/09/2026 – 30/09/2026',
  },
  'totals': {
    'earned': 342.50,
    'pending': 129.50,
    'settled': 213.00,
    'tips': 45.00,
    'currency': 'BOB',
    'currency_symbol': 'Bs',
  },
  'data': [
    {
      'id': 1,
      'earned_at': '2026-09-24T10:30:00-04:00',
      'description': 'Corte clásico',
      'base_amount': 50.0,
      'rate_label': '15%',
      'amount': 7.5,
      'settled': false,
    },
    {
      'id': 2,
      'earned_at': '2026-09-23T16:00:00-04:00',
      'description': 'Corte + diseño',
      'base_amount': 85.0,
      'rate_label': '15%',
      'amount': 12.75,
      'settled': false,
    },
    {
      'id': 3,
      'earned_at': '2026-09-18T11:15:00-04:00',
      'description': 'Barba',
      'base_amount': 20.0,
      'rate_label': '15%',
      'amount': 3.0,
      'settled': true,
    },
  ],
};

const _schedule = {
  'data': [
    {
      'id': 1,
      'weekday': 1,
      'weekday_label': 'Lunes',
      'start_time': '09:00',
      'end_time': '13:00',
      'branch': null,
    },
    {
      'id': 2,
      'weekday': 1,
      'weekday_label': 'Lunes',
      'start_time': '15:00',
      'end_time': '20:00',
      'branch': null,
    },
    {
      'id': 3,
      'weekday': 3,
      'weekday_label': 'Miércoles',
      'start_time': '09:00',
      'end_time': '18:00',
      'branch': null,
    },
    {
      'id': 4,
      'weekday': 5,
      'weekday_label': 'Viernes',
      'start_time': '10:00',
      'end_time': '19:00',
      'branch': null,
    },
    {
      'id': 5,
      'weekday': 6,
      'weekday_label': 'Sábado',
      'start_time': '09:00',
      'end_time': '14:00',
      'branch': null,
    },
  ],
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

/// Mismo usuario, pero con permisos y plan de caja, para la captura del cajón.
final _meCajero = <String, Object>{
  ..._me,
  'permissions': [
    'appointments.view',
    'appointments.edit',
    'commissions.view',
    'cash.view',
    'cash.create',
    'cash.edit',
    'sales.create',
  ],
  'plan': {
    'name': 'Premium',
    'modules': ['agenda', 'comisiones', 'caja', 'pos'],
    'module_labels': <String, String>{},
  },
};

const _cashSession = {
  'data': {
    'id': 3,
    'status': 'abierta',
    'is_open': true,
    'caja': {'id': 1, 'name': 'Caja principal'},
    'opened_at': '2026-09-26T08:00:00-04:00',
    'opened_by': 'Tania Molina',
    'opening_amount': 100.0,
    'duration': '3 h 20 min',
    'totals': {
      'income': 280.0,
      'expense': 35.0,
      'cash_income': 230.0,
      'cash_expense': 35.0,
      'expected_cash': 295.0,
      'net': 245.0,
    },
    'by_payment_method': <String, dynamic>{},
    'movements_count': 4,
    'movements': [
      {
        'id': 4,
        'type': 'egreso',
        'payment_method': 'efectivo',
        'payment_method_label': 'Efectivo',
        'concept': 'Compra de toallas',
        'amount': 35.0,
        'created_at': '2026-09-26T11:20:00-04:00',
        'created_by': 'Tania Molina',
      },
      {
        'id': 3,
        'type': 'ingreso',
        'payment_method': 'tarjeta',
        'payment_method_label': 'Tarjeta',
        'concept': 'Venta V-000012',
        'amount': 50.0,
        'created_at': '2026-09-26T10:45:00-04:00',
        'created_by': 'Tania Molina',
      },
      {
        'id': 2,
        'type': 'ingreso',
        'payment_method': 'efectivo',
        'payment_method_label': 'Efectivo',
        'concept': 'Venta V-000011',
        'amount': 85.0,
        'created_at': '2026-09-26T10:10:00-04:00',
        'created_by': 'Tania Molina',
      },
      {
        'id': 1,
        'type': 'ingreso',
        'payment_method': 'efectivo',
        'payment_method_label': 'Efectivo',
        'concept': 'Venta V-000010',
        'amount': 145.0,
        'created_at': '2026-09-26T09:30:00-04:00',
        'created_by': 'Tania Molina',
      },
    ],
  },
};

const _saleReceipt = {
  'data': {
    'id': 12,
    'number': 'V-000012',
    'status': 'pagada',
    'sold_at': '2026-09-26T10:45:00-04:00',
    'subtotal': 95.0,
    'discount': 5.0,
    'tip': 10.0,
    'total': 100.0,
    'notes': null,
    'client': {'id': 3, 'full_name': 'Carlos Mendoza'},
    'personal': {'id': 3, 'full_name': 'Tania Molina'},
    'branch': 'Centro',
    'appointment_id': 12,
    'items': [
      {
        'id': 1,
        'type': 'servicio',
        'description': 'Corte clásico',
        'quantity': 1.0,
        'unit_price': 50.0,
        'total': 50.0,
        'personal': 'Tania Molina',
      },
      {
        'id': 2,
        'type': 'producto',
        'description': 'Cera moldeadora',
        'quantity': 1.0,
        'unit_price': 45.0,
        'total': 45.0,
        'personal': 'Tania Molina',
      },
    ],
    'payments': [
      {
        'payment_method': 'efectivo',
        'payment_method_label': 'Efectivo',
        'amount': 60.0,
        'reference': null,
      },
      {
        'payment_method': 'tarjeta',
        'payment_method_label': 'Tarjeta',
        'amount': 40.0,
        'reference': null,
      },
    ],
  },
};

/// El mismo usuario, con los datos de comprobante de la barbería cargados.
final _meConComprobante = <String, Object>{
  ..._me,
  'company': {
    'id': 1,
    'name': 'Barbería Demo',
    'currency': 'BOB',
    'currency_symbol': 'Bs',
    'timezone': 'America/La_Paz',
    'country': 'BO',
    'tax_id': '1023456789',
    'tax_id_label': 'NIT',
    'address': 'Av. Arce 1234, Sopocachi',
    'phone': '71234567',
    'email': 'hola@barberiademo.test',
    'logo_url': null,
    'receipt_footer': 'Síguenos en @barberiademo',
  },
};

/// Abre el menú lateral y entra en una sección.
Future<void> openSection(WidgetTester t, String label) async {
  await t.tap(find.byIcon(Icons.menu));
  await t.pumpAndSettle();
  final item = find.descendant(of: find.byType(Drawer), matching: find.text(label));
  // El drawer es una lista perezosa: si la sección quedó fuera de vista, se
  // hace scroll hasta ella antes de tocarla.
  await t.scrollUntilVisible(
    item,
    120,
    scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first,
  );
  await t.tap(item);
  await t.pumpAndSettle();
}

/// Tania con permisos de recepción y caja: el menú con todo a la vista.
final _meCompleto = {
  ..._me,
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
    'commissions.view',
    'reports.view',
  ],
  'plan': {
    'name': 'Premium',
    'modules': ['agenda', 'clientes', 'caja', 'pos', 'comisiones', 'estadisticas'],
  },
};

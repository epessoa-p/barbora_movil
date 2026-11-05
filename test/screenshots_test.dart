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

  testWidgets('04c agenda del mes', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '04c_agenda_mes',
        session: s,
        routes: {'/me': _me, '/my/agenda': _agenda, '/agenda': _agendaShop},
        afterLoad: (t) async {
          await t.tap(find.text('La barbería'));
          await t.pumpAndSettle();
          await t.tap(find.text('Mes'));
          await t.pumpAndSettle();

          // Las citas de prueba son de septiembre de 2026: se retrocede hasta
          // ese mes, sea cual sea el día en que corre el test.
          final now = DateTime.now();
          final months = (now.year - 2026) * 12 + now.month - 9;
          for (var i = 0; i < months; i++) {
            await t.tap(find.byIcon(Icons.chevron_left));
            await t.pumpAndSettle();
          }
        });
  });

  testWidgets('04d recordatorios', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final meReservas = <String, Object>{
      ..._me,
      'plan': {
        'name': 'Premium',
        'modules': [...((_me['plan']! as Map)['modules'] as List), 'reservas_online'],
      },
    };
    final cita = (_agendaShop['data']! as List).first as Map<String, dynamic>;

    await shoot(tester, '04d_recordatorios',
        session: s,
        routes: {
          '/me': meReservas,
          '/my/agenda': _agenda,
          '/agenda': _agendaShop,
          '/reminders': {
            'days': 1,
            'data': [
              {...cita, 'whatsapp_url': 'https://wa.me/59171234567?text=Hola'},
              {...cita, 'id': 999, 'reminded_at': '2026-09-25T18:00:00-04:00', 'whatsapp_url': null},
            ],
          },
        },
        afterLoad: (t) async {
          await openAgendaTab(t, 'Recordatorios');
        });
  });

  testWidgets('04b agenda de la semana', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '04b_agenda_semana',
        session: s,
        routes: {'/me': _me, '/my/agenda': _agenda, '/agenda': _agendaShop},
        afterLoad: (t) async {
          await t.tap(find.text('La barbería'));
          await t.pumpAndSettle();
          await t.tap(find.text('Semana'));
          await t.pumpAndSettle();

          // Las citas de prueba son del sábado 26/09/2026: se retrocede hasta
          // esa semana, sea cual sea el día en que corre el test.
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final monday = today.subtract(Duration(days: today.weekday - 1));
          final weeks = monday.difference(DateTime(2026, 9, 21)).inDays ~/ 7;
          for (var i = 0; i < weeks; i++) {
            await t.tap(find.byIcon(Icons.chevron_left));
            await t.pumpAndSettle();
          }
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

  testWidgets('08b cerrar caja contando billetes', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final me = <String, Object>{
      ..._meCajero,
      'company': {
        ...(_meCajero['company']! as Map<String, dynamic>),
        'cash_count_mode': 'denominations',
        'cash_denominations': {
          'bills': [200.0, 100.0, 50.0, 20.0, 10.0],
          'coins': [5.0, 2.0, 1.0, 0.5, 0.2, 0.1],
        },
      },
    };
    final session = {
      ...(_cashSession['data']! as Map<String, dynamic>),
      'by_payment_method': {
        'efectivo': {'income': 230.0, 'expense': 35.0, 'count': 4, 'label': 'Efectivo', 'counts_as_cash': true},
        'qr': {'income': 120.0, 'expense': 0.0, 'count': 2, 'label': 'QR', 'counts_as_cash': false},
        'tarjeta': {'income': 50.0, 'expense': 0.0, 'count': 1, 'label': 'Tarjeta', 'counts_as_cash': false},
      },
    };

    await shoot(tester, '08b_cerrar_caja_billetes',
        session: s,
        routes: {
          '/me': me,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/cash/session': {'data': session},
        },
        afterLoad: (t) async {
          await openSection(t, 'Caja');
          await t.tap(find.text('Cerrar turno'));
          await t.pumpAndSettle();
          await t.enterText(find.widgetWithText(TextField, 'Bs 200'), '1');
          await t.enterText(find.widgetWithText(TextField, 'Bs 50'), '1');
          await t.enterText(find.widgetWithText(TextField, 'Bs 20'), '2');
          await t.pumpAndSettle();
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
          '/me': {
            ..._meCompleto,
            'payment_methods': [
              {'slug': 'efectivo', 'name': 'EFECTIVO', 'counts_as_cash': true, 'requires_reference': false},
              {'slug': 'qr', 'name': 'QR', 'counts_as_cash': false, 'requires_reference': true},
              {'slug': 'tarjeta', 'name': 'TARJETA', 'counts_as_cash': false, 'requires_reference': false},
            ],
          },
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
          // Con la comanda y la forma de pago, el catálogo queda más abajo.
          await t.dragUntilVisible(find.text('Barba'), find.byType(ListView).last, const Offset(0, -200));
          await t.pumpAndSettle();
          await t.tap(find.text('Barba').last);
          await t.pumpAndSettle();
          await t.dragUntilVisible(find.text('Agregar').first, find.byType(ListView).last, const Offset(0, 200));
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
          // Cliente (arriba de todo).
          await t.drag(find.byType(ListView).last, const Offset(0, 600));
          await t.pumpAndSettle();
          await t.tap(find.text('Cliente'));
          await t.pumpAndSettle();
          await t.tap(find.text('Carlos Mendoza'));
          await t.pumpAndSettle();
        });
  });

  final meFinanzas = <String, Object>{
    ..._meCompleto,
    'permissions': [
      ...(_meCompleto['permissions']! as List),
      'expenses.view', 'expenses.create', 'accounts.view', 'accounts.create',
      'expense_categories.view', 'purchases.view', 'purchases.create', 'suppliers.view',
    ],
    'plan': {
      'name': 'Premium',
      'modules': ['agenda', 'clientes', 'caja', 'pos', 'comisiones', 'estadisticas', 'inventario', 'finanzas'],
    },
  };

  testWidgets('28 gastos', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '28_gastos',
        session: s,
        routes: {
          '/me': meFinanzas,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/finance/expenses': {
            'total': 655.0,
            'data': [
              {'id': 3, 'number': 'G-000003', 'description': 'Alquiler de noviembre', 'category': 'ALQUILER', 'amount': 500.0,
                'spent_on': '2026-11-02', 'source': 'account', 'source_label': 'BANCO UNIÓN', 'can_cancel': true},
              {'id': 2, 'number': 'G-000002', 'description': 'Almuerzo del equipo', 'category': 'COMIDA', 'amount': 120.0,
                'spent_on': '2026-11-02', 'source': 'cash', 'source_label': 'Caja · T-000014', 'can_cancel': true},
              {'id': 1, 'number': 'G-000001', 'description': 'Adelanto', 'category': 'PAGO A PERSONAL', 'payee': 'TANIA MOLINA',
                'amount': 35.0, 'spent_on': '2026-11-01', 'source': 'cash', 'source_label': 'Caja · T-000013', 'can_cancel': true},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Gastos');
        });
  });

  testWidgets('28b servicios basicos del mes', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '28b_servicios_basicos',
        session: s,
        routes: {
          '/me': <String, Object>{
            ...meFinanzas,
            'permissions': [...(meFinanzas['permissions']! as List), 'expense_categories.create'],
          },
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/finance/expenses': {
            'total': 680.0,
            'data': [
              {'id': 3, 'number': 'G-000003', 'description': 'ALQUILER · noviembre 2026', 'category': 'ALQUILER', 'amount': 500.0,
                'spent_on': '2026-11-02', 'source': 'account', 'source_label': 'BANCO UNIÓN', 'can_cancel': true},
              {'id': 4, 'number': 'G-000004', 'description': 'LUZ · noviembre 2026', 'category': 'LUZ', 'amount': 180.0,
                'spent_on': '2026-11-03', 'source': 'cash', 'source_label': 'Caja · T-000014', 'can_cancel': true},
            ],
          },
          '/finance/basics': {
            'month': '2026-11',
            'label': 'Noviembre 2026',
            'previous': '2026-10',
            'next': null,
            'paid_count': 3,
            'pending_count': 2,
            'total_paid': 680.0,
            'services': [
              {'id': 3, 'name': 'ALQUILER', 'frequency': 'mensual', 'status': 'pagado', 'paid': 500.0, 'last_amount': 500.0},
              {'id': 4, 'name': 'LUZ', 'frequency': 'mensual', 'status': 'pagado', 'paid': 180.0, 'last_amount': 180.0},
              {'id': 5, 'name': 'AGUA', 'frequency': 'mensual', 'status': 'pendiente', 'paid': 0.0, 'last_amount': 65.0},
              {'id': 6, 'name': 'INTERNET Y TELÉFONO', 'frequency': 'mensual', 'status': 'pendiente', 'paid': 0.0, 'last_amount': 199.0},
              {'id': 9, 'name': 'HOSTING', 'frequency': 'anual', 'status': 'pagado', 'paid': 520.0, 'last_amount': 520.0,
                'next_due_on': '2027-08-05'},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Gastos');
          await t.tap(find.text('Servicios').last);
          await t.pumpAndSettle();
        });
  });


  testWidgets('28c comisiones por pagar en personal', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final me = <String, Object>{
      ...meFinanzas,
      'permissions': [...(meFinanzas['permissions']! as List), 'commissions.view', 'commissions.create'],
    };

    await shoot(tester, '28c_comisiones_por_pagar',
        session: s,
        routes: {
          '/me': me,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/finance/expenses': {
            'total': 320.0,
            'data': [
              {'id': 8, 'number': 'G-000008', 'description': 'Liquidación L-000003 · DIEGO ROJAS', 'category': 'COMISIONES',
                'payee': 'DIEGO ROJAS', 'amount': 320.0, 'spent_on': '2026-11-01', 'source': 'cash', 'source_label': 'Caja · T-000013',
                'can_cancel': false},
            ],
          },
          '/commissions/pending': {
            'summary': {'count': 14, 'total': 612.5, 'people': 2},
            'data': [
              {'personal_id': 3, 'name': 'TANIA MOLINA', 'count': 9, 'total': 412.5, 'tips': 40.0, 'since': '2026-10-12'},
              {'personal_id': 5, 'name': 'DIEGO ROJAS', 'count': 5, 'total': 200.0, 'tips': 0.0, 'since': '2026-11-02'},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Gastos');
          await t.tap(find.text('Personal').last);
          await t.pumpAndSettle();
        });
  });

  testWidgets('17b horario del personal', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final me = <String, Object>{
      ..._meCompleto,
      'permissions': [...(_meCompleto['permissions']! as List), 'schedules.view', 'schedules.edit'],
    };

    await shoot(tester, '17b_horario',
        session: s,
        routes: {
          '/me': me,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/personal': {
            'data': [
              {'id': 6, 'full_name': 'Lucía Recepción', 'cargo': 'Recepcionista', 'cargo_id': 2, 'bookable': false, 'active': true, 'agenda_color': '#10B981'},
            ],
          },
          '/personal/options': {
            'cargos': [{'id': 2, 'name': 'Recepcionista'}],
            'branches': <dynamic>[],
          },
          '/personal/6/schedules': {
            'personal': {'id': 6, 'name': 'Lucía Recepción', 'bookable': false},
            'branches': [{'id': 1, 'name': 'CENTRAL'}],
            'data': [
              for (final d in [1, 2, 3, 4, 5])
                {'id': d, 'weekday': d, 'weekday_label': '', 'start_time': '08:30', 'end_time': '12:30', 'branch_id': null, 'branch': 'Cualquier sucursal'},
              for (final d in [1, 2, 3, 4, 5])
                {'id': 10 + d, 'weekday': d, 'weekday_label': '', 'start_time': '14:30', 'end_time': '19:00', 'branch_id': null, 'branch': 'Cualquier sucursal'},
              {'id': 20, 'weekday': 6, 'weekday_label': 'Sábado', 'start_time': '09:00', 'end_time': '13:00', 'branch_id': null, 'branch': 'Cualquier sucursal'},
            ],
          },
        },
        afterLoad: (t) async {
          await openAdmin(t, 'Personal');
          await t.tap(find.text('Lucía Recepción'));
          await t.pumpAndSettle();
          await t.tap(find.text('Horario'));
          await t.pumpAndSettle();
        });
  });


  testWidgets('29 nueva compra', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '29_nueva_compra',
        session: s,
        routes: {
          '/me': meFinanzas,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/purchases': {'data': <Object>[], 'summary': {'total': 0.0, 'debt': 0.0}},
          '/purchases/options': {
            'suppliers': [{'id': 1, 'name': 'DISTRIBUIDORA NORTE'}],
            'warehouses': [{'id': 1, 'name': 'ALMACÉN CENTRAL'}],
            'default_warehouse_id': 1,
            'products': [{'id': 1, 'name': 'CERA MATE', 'cost': 22.0, 'track_stock': true}],
            'sources': ['account', 'cash'],
            'accounts': [{'id': 1, 'name': 'BANCO UNIÓN', 'type': 'banco', 'type_label': 'Banco', 'balance': 1800.0, 'active': true}],
            'open_sessions': [{'id': 14, 'number': 'T-000014', 'caja': 'CAJA PRINCIPAL', 'expected_cash': 295.0}],
            'preferred_session_id': 14,
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Compras');
          await t.tap(find.widgetWithText(FloatingActionButton, 'Nueva compra'));
          await t.pumpAndSettle();
        });
  });

  testWidgets('13b catalogo publico', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final me = <String, Object>{
      ..._meCompleto,
      'permissions': [
        ...(_meCompleto['permissions']! as List),
        'settings.view',
        'settings.edit',
        'service_categories.view',
      ],
    };

    await shoot(tester, '13b_catalogo',
        session: s,
        routes: {
          '/me': me,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/services': {'data': <Object>[]},
          '/admin/catalog': {
            'data': {
              'enabled': true,
              'show_products': false,
              'url': 'https://barbora.sczsoft.net/catalogo/x7k2m9qp4ab1',
              'poster_url': 'https://barbora.sczsoft.net/catalogo/x7k2m9qp4ab1/afiche',
              'services_count': 12,
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Servicios');
          await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Catálogo')));
          await t.pumpAndSettle();
        });
  });

  testWidgets('12c cobro con pago mixto', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '12c_cobro_mixto',
        session: s,
        routes: {
          '/me': {
            ..._meCompleto,
            'payment_methods': [
              {'slug': 'efectivo', 'name': 'EFECTIVO', 'counts_as_cash': true, 'requires_reference': false},
              {'slug': 'qr', 'name': 'QR', 'counts_as_cash': false, 'requires_reference': true},
              {'slug': 'tarjeta', 'name': 'TARJETA', 'counts_as_cash': false, 'requires_reference': false},
            ],
          },
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/services': {
            'data': [
              {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
            ],
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Cobrar');
          await t.tap(find.text('Corte clásico'));
          await t.pumpAndSettle();
          // Pago mixto: se marcan EFECTIVO (ya elegido) y QR.
          await t.dragUntilVisible(find.text('Pago mixto'), find.byType(ListView).last, const Offset(0, -200));
          await t.tap(find.text('Pago mixto'));
          await t.pumpAndSettle();
          await t.tap(find.widgetWithText(FilterChip, 'QR'));
          await t.pumpAndSettle();
          // La hoja de cobro solo trae las dos formas marcadas.
          await t.tap(find.byType(FilledButton).last);
          await t.pumpAndSettle();
          expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('TARJETA')), findsNothing);
          expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('QR')), findsOneWidget);
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

  testWidgets('16b reporte de ganancias', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    Map<String, Object> totals(double revenue, double cost) => {
          'revenue': revenue,
          'cost': cost,
          'profit': revenue - cost,
          'margin_pct': ((revenue - cost) / revenue * 1000).round() / 10,
        };

    await shoot(tester, '16b_reporte_ganancias',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/reports/profit': {
            'period': {
              'preset': 'mes',
              'label': 'Este mes',
              'presets': [
                {'key': 'hoy', 'label': 'Hoy'},
                {'key': 'semana', 'label': 'Esta semana'},
                {'key': 'semana_pasada', 'label': 'Semana anterior'},
                {'key': 'mes', 'label': 'Este mes'},
              ],
            },
            'scope': 'ambos',
            'include_quick': false,
            'summary': totals(3240, 1180),
            'products': {...totals(640, 380), 'sales': 14},
            'services': {...totals(2600, 800), 'sales': 41},
            'quick': {'revenue': 45.0, 'count': 2},
            'daily': [
              {'date': '2026-10-30', ...totals(410, 150)},
              {'date': '2026-10-29', ...totals(520, 190)},
            ],
            'top_products': [
              {'name': 'CERA MATE', 'quick': false, 'quantity': 8.0, ...totals(320, 160)},
              {'name': 'SHAMPOO', 'quick': false, 'quantity': 4.0, ...totals(160, 110)},
            ],
            'low_margin_products': <dynamic>[],
            'sales': [
              {
                'id': 1,
                'number': 'V-000048',
                'sold_at': '2026-10-30T18:20:00-04:00',
                'client': 'JUAN PÉREZ',
                ...totals(95, 30),
              },
            ],
            'estimated': false,
            'result': {'expenses': 900.0, 'net': 1160.0},
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Reportes');
          await t.tap(find.text('Ganancias'));
          await t.pumpAndSettle();
        });
  });

  Map<String, Object?> balanceReport() => {
        'period': {
          'preset': 'mes',
          'label': 'Este mes',
          'presets': [
            {'key': 'hoy', 'label': 'Hoy'},
            {'key': 'semana', 'label': 'Esta semana'},
            {'key': 'mes', 'label': 'Este mes'},
            {'key': 'mes_pasado', 'label': 'Mes pasado'},
          ],
        },
        'source': 'caja',
        'type': null,
        'results': {
          'income': {
            'lines': [
              {'key': 'servicios', 'label': 'Servicios', 'total': 5523.69},
              {'key': 'productos', 'label': 'Productos', 'total': 1846.0},
            ],
            'total': 7369.69,
            'by_source': {'caja': 7369.69, 'tesoreria': 0.0},
          },
          'expense': {
            'lines': [
              {'key': 'proveedor', 'label': 'Pago a proveedor', 'total': 1725.0},
              {'key': 'personal', 'label': 'Pago a personal', 'total': 805.0},
              {'key': 'gasto', 'label': 'Gasto', 'total': 505.0},
              {'key': 'devolucion_venta', 'label': 'Devolución de venta', 'total': 51.0},
            ],
            'total': 3086.0,
            'by_source': {'caja': 1636.0, 'tesoreria': 1450.0},
          },
          'profit': 4283.69,
          'capital': {'contributions': 10500.0, 'withdrawals': 0.0},
        },
        'flow': {
          'income': 7369.69,
          'expense': 1636.0,
          'balance': 5733.69,
          'categories': [
            {'key': 'venta', 'label': 'Venta', 'type': 'ingreso', 'total': 7369.69},
            {'key': 'proveedor', 'label': 'Pago a proveedor', 'type': 'egreso', 'total': 800.0},
          ],
          'items': [
            {
              'id': 'c1', 'source': 'caja', 'type': 'ingreso', 'category': 'venta', 'category_label': 'Venta',
              'concept': 'Venta V-000052', 'amount': 74.5, 'at': '2026-10-27T17:05:00-04:00',
              'place': 'CAJA 1 · LAS AMÉRICAS', 'method': 'Efectivo', 'services': 50.0,
            },
          ],
          'count': 1,
        },
        'closings': [
          {
            'id': 1, 'number': 'T-0001', 'caja': 'CAJA 1', 'branch': 'LAS AMÉRICAS', 'status': 'abierta',
            'opened_at': '2026-10-27T17:28:00-04:00', 'opened_by': 'demo', 'closed_at': null, 'closed_by': null,
            'opening': 0.0, 'cash_income': 15.0, 'cash_expense': 0.0, 'expected': 15.0,
            'counted': null, 'difference': null, 'other_methods': <dynamic>[],
          },
          {
            'id': 2, 'number': 'T-0002', 'caja': 'CAJA 1', 'branch': 'LAS AMÉRICAS', 'status': 'cerrada',
            'opened_at': '2026-10-17T08:55:00-04:00', 'opened_by': 'demo', 'closed_at': '2026-10-17T19:55:00-04:00',
            'closed_by': 'demo', 'opening': 0.0, 'cash_income': 1164.37, 'cash_expense': 251.0, 'expected': 913.37,
            'counted': 900.37, 'difference': -13.0,
            'other_methods': [
              {'label': 'QR', 'amount': 394.0},
            ],
          },
        ],
      };

  for (final (name, tab) in [('16c_balance_resultados', null), ('16d_balance_cierres', 'Cierres')]) {
    testWidgets(name.replaceAll('_', ' '), (tester) async {
      final s = _FakeSession()..seed(token: 't', companyId: 1);

      await shoot(tester, name,
          session: s,
          routes: {
            '/me': _meCompleto,
            '/my/agenda': _agenda,
            '/agenda': _agenda,
            '/reports/balance': balanceReport(),
          },
          afterLoad: (t) async {
            await openSection(t, 'Reportes');
            await t.ensureVisible(find.text('Balance'));
            await t.pumpAndSettle();
            await t.tap(find.text('Balance'));
            await t.pumpAndSettle();
            if (tab != null) {
              await t.tap(find.text(tab));
              await t.pumpAndSettle();
            }
          });
    });
  }


  testWidgets('16e analisis', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    Map<String, Object?> metric(double scale) => {
          'week': 1240 * scale,
          'week_change': 12.5,
          'month': 8450 * scale,
          'month_change': -8.2,
          'daily': [
            for (final (i, d) in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'].indexed)
              {'label': d, 'current': i < 3 ? (300 + i * 120) * scale : 0.0, 'previous': (260 + i * 90) * scale},
          ],
          'weeks': [
            for (final (i, l) in ['14/09', '21/09', '28/09', '05/10', '12/10', '19/10', '26/10', '02/11'].indexed)
              {'label': l, 'value': (1500 + i * 210) * scale},
          ],
          'months': [
            for (final (i, l) in ['Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov'].indexed)
              {'label': l, 'value': (5200 + i * 700) * scale},
          ],
        };

    await shoot(tester, '16e_analisis',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/reports/analysis': {
            'series': {
              for (final k in ['servicios', 'ventas', 'compras']) k: {'amount': metric(1), 'count': metric(.02)},
            },
            'top': {
              'services': [
                {'name': 'CORTE CLÁSICO', 'amount': 2400.0, 'count': 48.0},
              ],
              'products': <dynamic>[],
              'clients': <dynamic>[],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Reportes');
          await t.ensureVisible(find.text('Análisis'));
          await t.pumpAndSettle();
          await t.tap(find.text('Análisis'));
          await t.pumpAndSettle();
        });
  });


  testWidgets('16f reporte de productos', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '16f_reporte_productos',
        session: s,
        routes: {
          '/me': _meCompleto,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/reports/productos': {
            'key': 'productos',
            'title': 'Productos',
            'period': {
              'preset': 'mes',
              'label': 'Este mes',
              'presets': [
                {'key': 'hoy', 'label': 'Hoy'},
                {'key': 'semana', 'label': 'Esta semana'},
                {'key': 'mes', 'label': 'Este mes'},
                {'key': 'mes_pasado', 'label': 'Mes pasado'},
              ],
            },
            'summary': [
              {'label': 'Cantidad', 'value': 24, 'kind': 'int'},
              {'label': 'Ingresos', 'value': 1240.0, 'kind': 'money'},
              {'label': 'Costo', 'value': 610.0, 'kind': 'money'},
              {'label': 'Margen', 'value': 630.0, 'kind': 'money'},
            ],
            'charts': <dynamic>[],
            'tables': <dynamic>[],
            'note': null,
            'inventory': {'products': 39, 'units': 802.0, 'cost': 42101.0, 'sale': 72876.94, 'potential': 30775.94},
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Reportes');
          await t.tap(find.text('Productos'));
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
          await openAdmin(t, 'Personal');
        });
  });

  testWidgets('27 administracion', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);
    final meAdmin = <String, Object>{
      ..._meCompleto,
      'permissions': [
        ...(_meCompleto['permissions']! as List),
        'settings.view',
        'branches.view',
        'cajas.view',
      ],
    };

    await shoot(tester, '27_administracion',
        session: s,
        routes: {'/me': meAdmin, '/my/agenda': _agenda, '/agenda': _agenda},
        afterLoad: (t) async {
          await openAdmin(t);
        });
  });

  final meBloqueos = <String, Object>{
    ..._meCompleto,
    'permissions': [
      ...(_meCompleto['permissions']! as List),
      'agenda_blocks.view',
      'agenda_blocks.create',
      'agenda_blocks.edit',
      'agenda_blocks.delete',
    ],
  };

  const bloqueos = {
    'data': [
      {
        'id': 1,
        'title': 'Año nuevo',
        'reason': 'feriado',
        'reason_label': 'Feriado',
        'personal_id': null,
        'scope': 'Toda la barbería',
        'all_day': true,
        'starts_at': '2027-01-01T00:00:00-04:00',
        'ends_at': '2027-01-01T23:59:59-04:00',
        'range_label': '01/01/2027 · todo el día',
      },
      {
        'id': 2,
        'title': 'Vacaciones de Tania',
        'reason': 'vacaciones',
        'reason_label': 'Vacaciones',
        'personal_id': 3,
        'scope': 'Tania Molina',
        'all_day': true,
        'starts_at': '2026-11-02T00:00:00-04:00',
        'ends_at': '2026-11-15T23:59:59-04:00',
        'range_label': '02/11/2026 – 15/11/2026',
      },
      {
        'id': 3,
        'title': 'Almuerzo',
        'reason': 'descanso',
        'reason_label': 'Descanso',
        'personal_id': 5,
        'scope': 'Diego Rojas',
        'all_day': false,
        'starts_at': '2026-10-24T13:00:00-04:00',
        'ends_at': '2026-10-24T14:00:00-04:00',
        'range_label': '24/10/2026 13:00 – 14:00',
      },
    ],
    'reasons': [
      {'value': 'vacaciones', 'label': 'Vacaciones'},
      {'value': 'feriado', 'label': 'Feriado'},
      {'value': 'descanso', 'label': 'Descanso'},
      {'value': 'permiso', 'label': 'Permiso'},
      {'value': 'otro', 'label': 'Otro'},
    ],
    'staff': [
      {'id': 3, 'full_name': 'Tania Molina'},
      {'id': 5, 'full_name': 'Diego Rojas'},
    ],
    'branches': [
      {'id': 1, 'name': 'Central'},
    ],
  };

  testWidgets('18 bloqueos', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '18_bloqueos',
        session: s,
        routes: {'/me': meBloqueos, '/my/agenda': _agenda, '/agenda': _agenda, '/agenda-blocks': bloqueos},
        afterLoad: (t) async {
          await openAgendaTab(t, 'Bloqueos');
        });
  });

  testWidgets('19 nuevo bloqueo', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '19_nuevo_bloqueo',
        session: s,
        routes: {'/me': meBloqueos, '/my/agenda': _agenda, '/agenda': _agenda, '/agenda-blocks': bloqueos},
        afterLoad: (t) async {
          await openAgendaTab(t, 'Bloqueos');
          await t.tap(find.text('Nuevo bloqueo'));
          await t.pumpAndSettle();
          await t.enterText(find.widgetWithText(TextField, 'Nombre'), 'Almuerzo');
          await t.tap(find.text('Todo el día'));
        });
  });

  final meVentas = <String, Object>{
    ..._meCompleto,
    'permissions': [
      ...(_meCompleto['permissions']! as List),
      'sales.view',
      'sales.delete',
    ],
  };

  Map<String, Object?> fila(int id, String hora, String cliente, String barbero, double total,
          {String status = 'pagada', List<String> methods = const ['Efectivo'], int services = 1, int products = 0}) =>
      {
        'id': id,
        'number': 'V-${id.toString().padLeft(4, '0')}',
        'status': status,
        'total': total,
        'sold_at': '2026-10-22T$hora:00-04:00',
        'client': cliente,
        'personal': barbero,
        'methods': methods,
        'services': services,
        'products': products,
      };

  final ventas = {
    'summary': {'count': 4, 'total': 285.0, 'tips': 15.0, 'cancelled': 1},
    'data': [
      fila(41, '17:40', 'CARLOS MENDOZA', 'TANIA MOLINA', 85.0, methods: ['QR'], products: 1),
      fila(40, '16:05', 'LUIS VARGAS', 'DIEGO ROJAS', 50.0),
      fila(39, '12:20', 'ANDRÉS ROJAS', 'TANIA MOLINA', 50.0, status: 'anulada'),
      fila(38, '11:10', 'PEDRO QUIROGA', 'DIEGO ROJAS', 70.0, methods: ['Efectivo', 'Tarjeta'], services: 0, products: 2),
      fila(37, '09:30', 'MARCO SALAZAR', 'TANIA MOLINA', 80.0),
    ],
  };

  testWidgets('20 ventas', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '20_ventas',
        session: s,
        routes: {'/me': meVentas, '/my/agenda': _agenda, '/agenda': _agenda, '/sales': ventas},
        afterLoad: (t) async {
          await openSection(t, 'Ventas');
        });
  });

  testWidgets('21 venta anulada', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '21_venta_anulada',
        session: s,
        routes: {
          '/me': meVentas,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/sales': ventas,
          '/sales/39': {
            'data': {
              'id': 39,
              'number': 'V-0039',
              'status': 'anulada',
              'status_label': 'Anulada',
              'sold_at': '2026-10-22T12:20:00-04:00',
              'cancel_reason': 'Se cobró dos veces',
              'cancelled_at': '2026-10-22T12:35:00-04:00',
              'cancelled_by': 'Lucía Recepción',
              'subtotal': 50.0,
              'discount': 0.0,
              'tip': 0.0,
              'total': 50.0,
              'client': {'id': 4, 'full_name': 'ANDRÉS ROJAS'},
              'personal': {'id': 3, 'full_name': 'TANIA MOLINA'},
              'items': [
                {'id': 1, 'type': 'servicio', 'description': 'CORTE CLÁSICO', 'quantity': 1.0, 'unit_price': 50.0, 'total': 50.0},
              ],
              'payments': [
                {'payment_method': 'efectivo', 'payment_method_label': 'Efectivo', 'amount': 50.0},
              ],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Ventas');
          await t.tap(find.text('V-0039'));
          await t.pumpAndSettle();
          await t.drag(find.byType(ListView).last, const Offset(0, -500));
        });
  });

  testWidgets('22 editar cliente', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '22_editar_cliente',
        session: s,
        routes: {
          '/me': <String, Object>{
            ..._meCompleto,
            'permissions': [...(_meCompleto['permissions']! as List), 'clients.edit'],
          },
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/clients': {
            'data': [
              {'id': 3, 'full_name': 'CARLOS MENDOZA', 'phone': '71234567'},
            ],
          },
          '/clients/3': {
            'data': {
              'id': 3,
              'full_name': 'CARLOS MENDOZA',
              'phone': '71234567',
              'email': 'carlos@correo.test',
              'document_number': '9876543',
              'birth_date': '1994-05-17',
              'preferences': 'Degradado bajo, máquina 1. Sin cera.',
              'allergies': 'Alcohol en lociones',
              'notes': 'Prefiere los sábados por la mañana.',
              'active': true,
              'stats': {'visits': 8, 'total_spent': 540.0, 'upcoming': 0},
              'recent_appointments': <Object>[],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Clientes');
          await t.tap(find.text('CARLOS MENDOZA').first);
          await t.pumpAndSettle();
          await t.tap(find.byTooltip('Editar'));
        });
  });

  final meInventario = <String, Object>{
    ..._meCompleto,
    'permissions': [
      ...(_meCompleto['permissions']! as List),
      'products.view',
      'products.create',
      'products.edit',
      'stock.create',
    ],
    'plan': {
      'name': 'Premium',
      'modules': ['agenda', 'clientes', 'caja', 'pos', 'comisiones', 'estadisticas', 'inventario'],
    },
  };

  Map<String, Object?> producto(int id, String nombre, String categoria, double precio, double stock,
          {double minimo = 3, bool vende = true, String unidad = 'unidad', String unidadLabel = 'Unidad'}) =>
      {
        'id': id,
        'name': nombre,
        'category': categoria,
        'unit': unidad,
        'unit_label': unidadLabel,
        'sale_price': precio,
        'cost_price': precio / 2,
        'min_stock': minimo,
        'track_stock': true,
        'is_sellable': vende,
        'active': true,
        'stock': stock,
        'stock_label': '${stock.toStringAsFixed(0)} ${unidad == 'unidad' ? 'unidades' : unidad}',
        'low_stock': stock <= minimo,
      };

  final inventario = {
    'low_count': 2,
    'data': [
      producto(20, 'ACEITE PARA BARBA', 'Barba', 60, 8),
      producto(21, 'CERA MATE', 'Styling', 45, 2),
      producto(22, 'GEL FIJADOR', 'Styling', 35, 14),
      producto(23, 'HOJAS DE AFEITAR', 'Insumos', 2, 40, minimo: 50, vende: false),
      producto(24, 'SHAMPOO ANTICASPA', 'Cuidado', 55, 6),
      producto(25, 'TALCO', 'Insumos', 15, 900, minimo: 200, vende: false, unidad: 'gr', unidadLabel: 'Gramos'),
    ],
  };

  const opcionesInventario = {
    'categories': [
      {'id': 1, 'name': 'Styling'},
    ],
    'warehouses': [
      {'id': 1, 'name': 'Central'},
    ],
    'units': [
      {'value': 'unidad', 'label': 'Unidad'},
    ],
    'reasons': [
      {'value': 'compra', 'label': 'Compra a proveedor'},
    ],
    'limit': {'reached': false},
  };

  testWidgets('23 inventario', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '23_inventario',
        session: s,
        routes: {
          '/me': meInventario,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/inventory/products': inventario,
          '/inventory/options': opcionesInventario,
        },
        afterLoad: (t) async {
          await openSection(t, 'Inventario');
        });
  });

  testWidgets('24 ficha de producto', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    Map<String, Object?> mov(int id, String type, String label, String? reason, double qty, double after, String when) => {
          'id': id,
          'type': type,
          'type_label': label,
          'reason_label': reason,
          'quantity': qty,
          'quantity_after': after,
          'warehouse': 'Central',
          'created_by': 'Tania Molina',
          'created_at': '2026-10-$when:00-04:00',
        };

    await shoot(tester, '24_ficha_producto',
        session: s,
        routes: {
          '/me': meInventario,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/inventory/products': inventario,
          '/inventory/options': opcionesInventario,
          '/inventory/products/21': {
            'data': {
              ...producto(21, 'CERA MATE', 'Styling', 45, 2),
              'sku': 'CM-01',
              'margin_percent': 50.0,
              'stocks': [
                {'warehouse_id': 1, 'warehouse': 'Central', 'quantity': 2.0, 'quantity_label': '2 unidades'},
              ],
              'movements': [
                mov(4, 'salida', 'Salida', 'Venta', -3, 2, '23T17:40'),
                mov(3, 'salida', 'Salida', 'Venta', -1, 5, '22T11:10'),
                mov(2, 'ajuste', 'Ajuste', 'Recuento físico', -1, 6, '20T09:00'),
                mov(1, 'entrada', 'Entrada', 'Compra a proveedor', 7, 7, '15T10:30'),
              ],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Inventario');
          await t.tap(find.text('CERA MATE'));
        });
  });

  Map<String, Object?> turno(int id, String dia, double esperado, double contado, String label,
          {double ingresos = 0, int movs = 0, String? notas}) =>
      {
        'id': id,
        'status': 'cerrada',
        'is_open': false,
        'caja': {'id': 1, 'name': 'Caja principal'},
        'opened_at': '2026-10-${dia}T08:30:00-04:00',
        'opened_by': 'Tania Molina',
        'opening_amount': 100.0,
        'duration': '10 h 15 min',
        'totals': {
          'income': ingresos,
          'expense': 40.0,
          'cash_income': esperado - 60,
          'cash_expense': 40.0,
          'expected_cash': esperado,
          'net': ingresos - 40,
        },
        'by_payment_method': {
          'efectivo': {'income': esperado - 60, 'expense': 40.0, 'count': movs - 2, 'label': 'Efectivo'},
          'qr': {'income': ingresos - (esperado - 60), 'expense': 0.0, 'count': 2, 'label': 'QR'},
        },
        'movements_count': movs,
        'closed_at': '2026-10-${dia}T18:45:00-04:00',
        'closed_by': 'Tania Molina',
        'closing_amount': contado,
        'expected_amount': esperado,
        'difference': contado - esperado,
        'difference_label': label,
        'closing_notes': notas,
      };

  final turnos = {
    'data': [
      turno(12, '23', 640, 640, 'Cuadrada', ingresos: 780, movs: 14),
      turno(11, '22', 515, 505, 'Faltante', ingresos: 610, movs: 11, notas: 'Faltó dar cambio a un cliente.'),
      turno(10, '21', 720, 730, 'Sobrante', ingresos: 845, movs: 16),
      turno(9, '20', 430, 430, 'Cuadrada', ingresos: 505, movs: 9),
    ],
  };

  testWidgets('25 turnos de caja', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '25_turnos_caja',
        session: s,
        routes: {
          '/me': _meCajero,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/cash/session': _cashSession,
          '/cash/sessions': turnos,
        },
        afterLoad: (t) async {
          await openSection(t, 'Caja');
          await t.dragUntilVisible(find.text('Turnos anteriores'), find.byType(ListView).last, const Offset(0, -300));
          await t.pumpAndSettle();
          await t.tap(find.text('Turnos anteriores'));
        });
  });

  testWidgets('26 detalle de turno', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    await shoot(tester, '26_detalle_turno',
        session: s,
        routes: {
          '/me': _meCajero,
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/cash/session': _cashSession,
          '/cash/sessions': turnos,
          '/cash/sessions/11': {
            'data': {
              ...turno(11, '22', 515, 505, 'Faltante', ingresos: 610, movs: 11, notas: 'Faltó dar cambio a un cliente.'),
              'movements': (_cashSession['data']! as Map)['movements'],
            },
          },
        },
        afterLoad: (t) async {
          await openSection(t, 'Caja');
          await t.dragUntilVisible(find.text('Turnos anteriores'), find.byType(ListView).last, const Offset(0, -300));
          await t.pumpAndSettle();
          await t.tap(find.text('Turnos anteriores'));
          await t.pumpAndSettle();
          await t.tap(find.text('Faltante'));
        });
  });

  testWidgets('00 inicio del jefe', (tester) async {
    final s = _FakeSession()..seed(token: 't', companyId: 1);

    final citas = (_agenda['data']! as List).cast<Map<String, Object?>>();

    await shoot(tester, '00_inicio',
        session: s,
        routes: {
          '/me': <String, Object>{
            ...meInventario,
            'permissions': [
              ...(meInventario['permissions']! as List),
              'dashboard.view',
              'sales.view',
              'appointments.create',
            ],
          },
          '/my/agenda': _agenda,
          '/agenda': _agenda,
          '/dashboard': {
            'date': '2026-10-24',
            'agenda': {
              'total': 9,
              'pending': 4,
              'attended': 4,
              'no_show': 1,
              'cancelled': 0,
              'next': [citas[0], citas[2]],
            },
            'sales': {
              'today': 640.0,
              'count': 9,
              'tips': 35.0,
              'average': 71.11,
              'yesterday': 515.0,
              'week': {
                'labels': ['Sá', 'Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi'],
                'data': [705.0, 0.0, 430.0, 505.0, 845.0, 610.0, 640.0],
              },
            },
            'cash': {
              'open': true,
              'caja': 'Caja principal',
              'opened_by': 'Tania Molina',
              'expected_cash': 520.0,
              'income': 640.0,
            },
            'stock': {
              'low_count': 2,
              'items': [
                {'id': 21, 'name': 'CERA MATE', 'stock_label': '2 unidades'},
                {'id': 23, 'name': 'HOJAS DE AFEITAR', 'stock_label': '40 unidades'},
              ],
            },
          },
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
  'staff': [
    {'id': 1, 'full_name': 'Iván Céspedes', 'agenda_color': '#3B82F6'},
    {'id': 2, 'full_name': 'Tania Molina', 'agenda_color': '#E64A38'},
  ],
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

/// Toca una pestaña de la barra inferior de la agenda (Recordatorios, Bloqueos).
Future<void> openAgendaTab(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await t.pumpAndSettle();
}

/// Abre «Administración» (abajo del menú) y, si se indica, uno de sus cuadros.
Future<void> openAdmin(WidgetTester t, [String? card]) async {
  await t.tap(find.byIcon(Icons.menu));
  await t.pumpAndSettle();
  await t.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Administración')));
  await t.pumpAndSettle();

  if (card != null) {
    await t.tap(find.text(card));
    await t.pumpAndSettle();
  }
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

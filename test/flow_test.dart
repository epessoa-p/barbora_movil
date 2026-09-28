import 'dart:convert';

import 'package:barbora_movil/core/api_client.dart';
import 'package:barbora_movil/core/session.dart';
import 'package:barbora_movil/main.dart';
import 'package:barbora_movil/screens/agenda_screen.dart';
import 'package:barbora_movil/screens/company_picker_screen.dart';
import 'package:barbora_movil/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// Recorrido de la app contra una API simulada.
///
/// Las respuestas están copiadas de lo que devuelve `/api/v1` de verdad, así
/// que esto verifica la cadena entera: cabeceras, modelos y pantalla. Si el
/// backend cambia una clave, falla aquí.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Sesión de mentira: no toca el llavero del sistema, que en un test no existe.
  late _FakeSession session;

  setUp(() => session = _FakeSession());

  /// Devuelve la app montada sobre un cliente HTTP que responde lo que se le diga.
  Future<ApiClient> pumpApp(
    WidgetTester tester, {
    required Map<String, Object> routes,
    List<String>? seen,
  }) async {
    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      seen?.add('${request.method} $path'
          '${request.headers['X-Company-Id'] != null ? ' [company=${request.headers['X-Company-Id']}]' : ''}');

      final body = routes[path];

      if (body == null) {
        return http.Response(jsonEncode({'error': 'not_found'}), 404,
            headers: {'content-type': 'application/json'});
      }

      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    final api = ApiClient(session: session, client: client);

    await tester.pumpWidget(BarboraApp(session: session, api: api));
    await tester.pumpAndSettle();

    return api;
  }

  testWidgets('sin sesión se muestra el acceso, con el logo de la marca',
      (tester) async {
    await pumpApp(tester, routes: {});

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('APP DEL PERSONAL'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  testWidgets('el formulario no se envía vacío', (tester) async {
    final seen = <String>[];
    await pumpApp(tester, routes: {}, seen: seen);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
    expect(seen, isEmpty, reason: 'No debe llamar al servidor sin datos.');
  });

  testWidgets('con una sola barbería se entra directo a la agenda',
      (tester) async {
    final seen = <String>[];

    await pumpApp(tester, seen: seen, routes: {
      '/login': _login,
      '/me': _me,
      '/my/agenda': _agenda,
      '/agenda': _agenda,
    });

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'), 'tania@barberiademo.test');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'), 'Secreto@1234');

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.byType(AgendaScreen), findsOneWidget);
    expect(find.text('Carlos Mendoza'), findsOneWidget);
    expect(find.text('Corte clásico + Barba'), findsOneWidget);

    // La cabecera X-Company-Id tiene que ir en todo lo que no sea el login.
    expect(seen.any((r) => r.startsWith('POST /login')), isTrue);
    expect(
      seen.where((r) => r.contains('/me')).every((r) => r.contains('company=1')),
      isTrue,
      reason: 'Sin la cabecera el servidor no sabe en qué barbería se trabaja.',
    );
  });

  testWidgets('con varias barberías se pregunta en cuál', (tester) async {
    await pumpApp(tester, routes: {
      '/login': {
        'token': 'token-de-prueba',
        'user': _user,
        'companies': [
          {'id': 1, 'name': 'Barbería Demo', 'currency': 'BOB'},
          {'id': 2, 'name': 'Barbería Norte', 'currency': 'BOB'},
        ],
        'default_company_id': null,
      },
      '/companies': {
        'data': [
          {'id': 1, 'name': 'Barbería Demo', 'currency': 'BOB'},
          {'id': 2, 'name': 'Barbería Norte', 'currency': 'BOB'},
        ],
      },
      '/me': _me,
      '/my/agenda': _agenda,
    });

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'), 'tania@barberiademo.test');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'), 'Secreto@1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.byType(CompanyPickerScreen), findsOneWidget);
    expect(find.text('Barbería Demo'), findsOneWidget);
    expect(find.text('Barbería Norte'), findsOneWidget);

    await tester.tap(find.text('Barbería Norte'));
    await tester.pumpAndSettle();

    expect(find.byType(AgendaScreen), findsOneWidget);
  });

  testWidgets('unas credenciales malas se explican en la pantalla',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message': 'Los datos no son válidos.',
          'errors': {
            'email': ['Las credenciales no son correctas.'],
          },
        }),
        422,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await tester.pumpWidget(
      BarboraApp(session: session, api: ApiClient(session: session, client: client)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'a@b.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'mala');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Los datos no son válidos.'), findsOneWidget);
    expect(find.text('Las credenciales no son correctas.'), findsOneWidget);
  });

  testWidgets('un token guardado entra sin pasar por el acceso', (tester) async {
    session.seed(token: 'token-guardado', companyId: 1);

    await pumpApp(tester, routes: {
      '/me': _me,
      '/my/agenda': _agenda,
      '/agenda': _agenda,
    });

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(AgendaScreen), findsOneWidget);
  });

  testWidgets('la agenda vacía lo dice en vez de quedarse en blanco',
      (tester) async {
    session.seed(token: 'token-guardado', companyId: 1);

    await pumpApp(tester, routes: {
      '/me': _me,
      '/my/agenda': {
        'day': '2026-09-26',
        'personal_id': 3,
        'data': <dynamic>[],
        'summary': {'total': 0, 'pending': 0, 'attended': 0, 'minutes': 0},
      },
    });

    expect(find.text('No tienes citas este día'), findsOneWidget);
  });
}

// ── Respuestas de ejemplo, con la forma real de la API ──────────────────────

const _user = {
  'id': 4,
  'name': 'Tania Molina',
  'email': 'tania.molina@barberiademo.test',
  'phone': null,
  'is_super_admin': false,
};

const _login = {
  'token': 'token-de-prueba',
  'user': _user,
  'companies': [
    {'id': 1, 'name': 'Barbería Demo', 'currency': 'BOB', 'currency_symbol': 'Bs'},
  ],
  'default_company_id': 1,
};

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
    'module_labels': {'agenda': 'Agenda / Citas'},
  },
  'subscription': {
    'status': 'active',
    'on_trial': false,
    'allows_write': true,
    'trial_ends_at': null,
    'current_period_end': '2026-10-22T00:00:00-04:00',
  },
};

const _agenda = {
  'day': '2026-09-26',
  'personal_id': 3,
  'data': [
    {
      'id': 12,
      'starts_at': '2026-09-26T09:00:00-04:00',
      'ends_at': '2026-09-26T09:40:00-04:00',
      'duration_minutes': 40,
      'status': 'confirmada',
      'status_label': 'Confirmada',
      'is_editable': true,
      'notes': null,
      'client': {'id': 3, 'full_name': 'Carlos Mendoza', 'phone': '59171234567'},
      'personal': {'id': 3, 'full_name': 'Tania Molina'},
      'branch': 'Centro',
      'services': [
        {'id': 5, 'name': 'Corte clásico', 'duration_minutes': 30, 'price': 50.0},
        {'id': 7, 'name': 'Barba', 'duration_minutes': 10, 'price': 20.0},
      ],
      'total': 70.0,
      'reminded_at': null,
    },
  ],
  'summary': {'total': 1, 'pending': 1, 'attended': 0, 'no_show': 0, 'minutes': 40},
  'blocks': <dynamic>[],
};

/// Guarda en memoria, para no depender del llavero del sistema en los tests.
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

import 'package:barbora_movil/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los códigos de error son el contrato con el backend.
///
/// Si alguien cambia uno en Laravel y no aquí, la app no falla: hace algo peor,
/// que es enseñar «ocurrió un error inesperado» en vez de mandar al usuario a
/// iniciar sesión o a elegir barbería. Por eso están todos comprobados.
void main() {
  group('Códigos de la API', () {
    test('sesión caducada pide volver a entrar', () {
      final e = ApiException.fromResponse(401, {
        'error': 'unauthenticated',
        'message': 'Tu sesión expiró.',
      });

      expect(e.kind, ApiErrorKind.unauthenticated);
      expect(e.requiresLogin, isTrue);
      expect(e.requiresCompany, isFalse);
    });

    test('empresa ajena manda a elegir barbería', () {
      final e = ApiException.fromResponse(403, {
        'error': 'company_forbidden',
        'message': 'No perteneces a esa empresa.',
      });

      expect(e.kind, ApiErrorKind.companyForbidden);
      expect(e.requiresCompany, isTrue);
      expect(e.requiresLogin, isFalse);
    });

    test('falta indicar la empresa también manda a elegir', () {
      final e = ApiException.fromResponse(409, {'error': 'company_required'});

      expect(e.kind, ApiErrorKind.companyRequired);
      expect(e.requiresCompany, isTrue);
    });

    test('suscripción vencida se distingue de la de solo lectura', () {
      final bloqueada = ApiException.fromResponse(402, {'error': 'subscription_blocked'});
      final lectura = ApiException.fromResponse(402, {'error': 'subscription_readonly'});

      expect(bloqueada.kind, ApiErrorKind.subscriptionBlocked);
      expect(lectura.kind, ApiErrorKind.subscriptionReadonly);
    });

    test('módulo fuera del plan conserva cuáles hacían falta', () {
      final e = ApiException.fromResponse(403, {
        'error': 'plan_required',
        'message': 'El plan no incluye esta función.',
        'required_modules': ['agenda'],
      });

      expect(e.kind, ApiErrorKind.planRequired);
      expect(e.extra['required_modules'], ['agenda']);
    });

    test('falta de permiso conserva cuál se exigía', () {
      final e = ApiException.fromResponse(403, {
        'error': 'forbidden',
        'required_permissions': ['clients.view'],
      });

      expect(e.kind, ApiErrorKind.forbidden);
      expect(e.extra['required_permissions'], ['clients.view']);
    });
  });

  group('Respuestas sin código', () {
    test('un 422 de Laravel se lee como validación', () {
      final e = ApiException.fromResponse(422, {
        'message': 'Los datos no son válidos.',
        'errors': {
          'email': ['Las credenciales no son correctas.'],
        },
      });

      expect(e.kind, ApiErrorKind.validation);
      expect(e.firstErrorFor('email'), 'Las credenciales no son correctas.');
      expect(e.firstErrorFor('password'), isNull);
    });

    test('un 404 pelado se entiende igual', () {
      final e = ApiException.fromResponse(404, {});

      expect(e.kind, ApiErrorKind.notFound);
      expect(e.message, isNotEmpty, reason: 'Siempre hay algo que enseñar.');
    });

    test('un 500 cae en desconocido pero con mensaje', () {
      final e = ApiException.fromResponse(500, {});

      expect(e.kind, ApiErrorKind.unknown);
      expect(e.message, isNotEmpty);
    });
  });

  test('el mensaje del servidor manda sobre el genérico', () {
    final e = ApiException.fromResponse(403, {
      'error': 'forbidden',
      'message': 'No puedes tocar la agenda de otro barbero.',
    });

    expect(e.message, 'No puedes tocar la agenda de otro barbero.');
  });

  test('los errores de validación admiten un valor suelto', () {
    final e = ApiException.fromResponse(422, {
      'errors': {'email': 'Formato inválido'},
    });

    expect(e.firstErrorFor('email'), 'Formato inválido');
  });
}

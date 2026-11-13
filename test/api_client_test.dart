import 'package:barbora_movil/core/api_client.dart';
import 'package:barbora_movil/core/api_exception.dart';
import 'package:barbora_movil/core/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Cuando el hosting se cae un momento responde 503 «PHP service unavailable»
/// (texto, no JSON): la app tiene que decir que el servidor no está
/// disponible y que se reintente, no «algo que no se entiende».
void main() {
  ApiClient client(int status, String body, {String type = 'text/html'}) => ApiClient(
        session: Session(),
        client: MockClient((_) async => http.Response(body, status, headers: {'content-type': type})),
      );

  Future<ApiException> errorOf(ApiClient api) async {
    try {
      await api.get('/reports/profit');
    } on ApiException catch (e) {
      return e;
    }
    throw TestFailure('Tenía que fallar');
  }

  test('503 del hosting: el servidor no está disponible, reintentar', () async {
    final e = await errorOf(client(503, 'PHP service unavailable'));

    expect(e.statusCode, 503);
    expect(e.message, contains('no está disponible'));
    expect(e.message, contains('Intenta de nuevo'));
  });

  test('502 y 504 se explican igual', () async {
    for (final status in [502, 504]) {
      expect((await errorOf(client(status, '<html>Bad gateway</html>'))).message, contains('no está disponible'));
    }
  });

  test('otro error que no es JSON sigue mostrando el estado', () async {
    expect((await errorOf(client(500, '<html>Error</html>'))).message, contains('HTTP 500'));
  });

  test('si el servidor manda su propio mensaje, se respeta', () async {
    final e = await errorOf(client(503, '{"message":"En mantenimiento hasta las 10."}', type: 'application/json'));
    expect(e.message, 'En mantenimiento hasta las 10.');
  });
}

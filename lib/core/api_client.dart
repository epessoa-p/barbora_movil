import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'config.dart';
import 'session.dart';

/// Único punto por el que la app habla con la API.
///
/// Se encarga de tres cosas y nada más: poner las cabeceras, convertir la
/// respuesta en un mapa, y convertir cualquier fallo en un [ApiException]. Las
/// pantallas nunca ven un `http.Response` ni un código de estado.
class ApiClient {
  ApiClient({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  final Session session;
  final http.Client _client;

  /// Se avisa cuando el servidor dice que el token ya no vale, para que la app
  /// cierre sesión desde un solo sitio en vez de comprobarlo en cada pantalla.
  void Function()? onUnauthenticated;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool withCompany = true,
  }) =>
      _send('GET', path, query: query, withCompany: withCompany);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool withCompany = true,
    bool withAuth = true,
    Map<String, String>? headers,
  }) =>
      _send('POST', path,
          body: body, withCompany: withCompany, withAuth: withAuth, headers: headers);

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool withCompany = true,
  }) =>
      _send('PUT', path, body: body, withCompany: withCompany);

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    bool withCompany = true,
  }) =>
      _send('PATCH', path, body: body, withCompany: withCompany);

  Future<Map<String, dynamic>> delete(String path, {bool withCompany = true}) =>
      _send('DELETE', path, withCompany: withCompany);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    bool withCompany = true,
    bool withAuth = true,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${Config.apiUrl}$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );

    final request = http.Request(method, uri)
      ..headers.addAll(_headers(withCompany: withCompany, withAuth: withAuth))
      // Cabeceras propias de la llamada, como Idempotency-Key al cobrar.
      ..headers.addAll(headers ?? const {});

    if (body != null) {
      request.body = jsonEncode(body);
    }

    late http.Response response;

    try {
      final streamed = await _client.send(request).timeout(Config.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on SocketException {
      // En producción el problema casi siempre es la conexión del teléfono;
      // en desarrollo, que el servidor local no está encendido o no se ve.
      throw ApiException.network(
        Config.isProduction
            ? 'No se pudo conectar con Barbora. Revisa tu conexión a internet '
                'e inténtalo de nuevo.'
            : 'No se pudo conectar con ${Config.apiBaseUrl}. Comprueba que el '
                'servidor esté encendido y que el móvil esté en la misma red.',
      );
    } on HttpException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    return _decode(response);
  }

  Map<String, String> _headers({required bool withCompany, required bool withAuth}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (withAuth && session.hasToken) {
      headers['Authorization'] = 'Bearer ${session.token}';
    }

    // Sin esta cabecera el servidor no sabe en qué barbería se trabaja, y si el
    // usuario pertenece a varias responde 409 company_required.
    if (withCompany && session.companyId != null) {
      headers['X-Company-Id'] = '${session.companyId}';
    }

    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> body;

    if (response.body.isEmpty) {
      body = <String, dynamic>{};
    } else {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        body = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
      } on FormatException {
        // Respuesta que no es JSON: casi siempre una página de error de PHP.
        // Se dice cuál fue el estado en vez de un «error inesperado» a secas.
        throw ApiException(
          kind: ApiErrorKind.unknown,
          statusCode: response.statusCode,
          message: 'El servidor respondió algo que no se entiende '
              '(HTTP ${response.statusCode}).',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final error = ApiException.fromResponse(response.statusCode, body);

    if (error.requiresLogin) {
      onUnauthenticated?.call();
    }

    throw error;
  }

  void close() => _client.close();
}

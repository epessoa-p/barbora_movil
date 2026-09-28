/// Un error de la API, ya traducido a algo que la app puede tratar.
///
/// La API devuelve un código estable (`error`) y un mensaje para la persona
/// (`message`). El código es lo que se mira en el `switch`; el mensaje es lo
/// que se enseña. Así, si mañana cambia la redacción del backend, la app no se
/// rompe.
///
/// Los códigos están documentados en barbora_web/README.md, sección «API móvil».
enum ApiErrorKind {
  /// Sin token, o el token ya no vale. Hay que volver a iniciar sesión.
  unauthenticated,

  /// La cabecera X-Company-Id apunta a una barbería que no es del usuario.
  companyForbidden,

  /// El usuario pertenece a varias barberías y no dijo en cuál trabaja.
  companyRequired,

  /// La suscripción de la barbería no permite entrar (402).
  subscriptionBlocked,

  /// La suscripción permite leer pero no escribir (402).
  subscriptionReadonly,

  /// El plan contratado no incluye el módulo.
  planRequired,

  /// Falta un permiso dentro de la barbería.
  forbidden,

  /// El servidor rechazó los datos enviados (422).
  validation,

  /// No existe, o no es visible para esta barbería.
  notFound,

  /// No hubo forma de hablar con el servidor.
  network,

  /// Cualquier otra cosa.
  unknown,
}

class ApiException implements Exception {
  ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.errors = const {},
    this.extra = const {},
  });

  final ApiErrorKind kind;

  /// Mensaje listo para enseñar. Viene del servidor cuando lo manda.
  final String message;

  final int? statusCode;

  /// El código crudo del servidor, por si hace falta distinguir algo nuevo.
  final String? code;

  /// Errores de validación por campo, tal como los manda Laravel.
  final Map<String, List<String>> errors;

  /// Datos extra del error: por ejemplo los módulos que exige el plan.
  final Map<String, dynamic> extra;

  /// ¿Conviene devolver al usuario a la pantalla de inicio de sesión?
  bool get requiresLogin => kind == ApiErrorKind.unauthenticated;

  /// ¿Hay que volver a elegir barbería?
  bool get requiresCompany =>
      kind == ApiErrorKind.companyRequired || kind == ApiErrorKind.companyForbidden;

  /// El primer error de validación, que es el que se enseña bajo el campo.
  String? firstErrorFor(String field) {
    final list = errors[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  factory ApiException.network([String? detail]) => ApiException(
        kind: ApiErrorKind.network,
        message: detail ??
            'No se pudo conectar con el servidor. Revisa tu conexión '
                'e inténtalo de nuevo.',
      );

  /// Construye la excepción a partir de la respuesta del servidor.
  factory ApiException.fromResponse(int status, Map<String, dynamic> body) {
    final code = body['error'] as String?;
    final message = body['message'] as String?;

    final kind = switch (code) {
      'unauthenticated' => ApiErrorKind.unauthenticated,
      'company_forbidden' => ApiErrorKind.companyForbidden,
      'company_required' => ApiErrorKind.companyRequired,
      'subscription_blocked' => ApiErrorKind.subscriptionBlocked,
      'subscription_readonly' => ApiErrorKind.subscriptionReadonly,
      'plan_required' => ApiErrorKind.planRequired,
      'forbidden' => ApiErrorKind.forbidden,
      // Algunos errores no llevan código y hay que deducirlos del estado.
      _ => switch (status) {
          401 => ApiErrorKind.unauthenticated,
          403 => ApiErrorKind.forbidden,
          404 => ApiErrorKind.notFound,
          422 => ApiErrorKind.validation,
          _ => ApiErrorKind.unknown,
        },
    };

    return ApiException(
      kind: kind,
      message: message ?? _defaultMessage(kind),
      statusCode: status,
      code: code,
      errors: _parseErrors(body['errors']),
      extra: Map<String, dynamic>.from(body)
        ..remove('error')
        ..remove('message')
        ..remove('errors'),
    );
  }

  static Map<String, List<String>> _parseErrors(dynamic raw) {
    if (raw is! Map) return const {};

    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        (value is List) ? value.map((e) => e.toString()).toList() : <String>[value.toString()],
      ),
    );
  }

  static String _defaultMessage(ApiErrorKind kind) => switch (kind) {
        ApiErrorKind.unauthenticated => 'Tu sesión expiró. Vuelve a iniciar sesión.',
        ApiErrorKind.companyForbidden => 'No tienes acceso a esa barbería.',
        ApiErrorKind.companyRequired => 'Elige en qué barbería estás trabajando.',
        ApiErrorKind.subscriptionBlocked =>
          'La suscripción de la barbería está vencida. Habla con el administrador.',
        ApiErrorKind.subscriptionReadonly =>
          'La suscripción venció: puedes consultar, pero no registrar cambios.',
        ApiErrorKind.planRequired => 'El plan contratado no incluye esta función.',
        ApiErrorKind.forbidden => 'No tienes permiso para hacer esto.',
        ApiErrorKind.validation => 'Revisa los datos e inténtalo de nuevo.',
        ApiErrorKind.notFound => 'No se encontró lo que buscabas.',
        ApiErrorKind.network => 'No se pudo conectar con el servidor.',
        ApiErrorKind.unknown => 'Ocurrió un error inesperado.',
      };

  @override
  String toString() => 'ApiException(${kind.name}, $statusCode): $message';
}

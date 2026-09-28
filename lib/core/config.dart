import 'package:flutter/foundation.dart';

/// Configuración del entorno.
///
/// A qué servidor habla la app se decide así, en este orden:
///
///   1. Lo que se pase al compilar con `--dart-define`, que siempre manda:
///      ```bash
///      flutter run --dart-define=BARBORA_API_URL=http://192.168.1.50:8070
///      ```
///   2. En un build **release** (el APK que se instala), producción.
///   3. En desarrollo, el `localhost` de la máquina tal como lo ve el emulador
///      de Android (10.0.2.2). En un teléfono físico eso no sirve: hay que
///      pasar la IP del PC con `--dart-define`.
///
/// Aquí solo va la URL. **Ninguna credencial del servidor va dentro de la app**:
/// un APK se puede desempaquetar, y todo lo que lleve dentro es público.
class Config {
  const Config._();

  static const String production = 'https://barbora.sczsoft.net';
  static const String development = 'http://10.0.2.2:8070';

  static const String _override = String.fromEnvironment('BARBORA_API_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _stripSlash(_override);

    return kReleaseMode ? production : development;
  }

  static String get apiUrl => '$apiBaseUrl/api/v1';

  /// ¿Apunta a producción? La pantalla de acceso lo usa para no enseñar la URL
  /// del servidor a los usuarios finales.
  static bool get isProduction => apiBaseUrl == production;

  /// Nombre con el que este dispositivo aparece en la lista de sesiones.
  /// La API revoca el token anterior del mismo nombre al volver a entrar.
  static const String deviceNameFallback = 'Dispositivo Barbora';

  static const Duration requestTimeout = Duration(seconds: 20);

  static String _stripSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

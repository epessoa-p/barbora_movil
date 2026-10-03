/// Configuración del entorno.
///
/// Aquí solo va la URL del servidor. **Ninguna credencial del servidor va
/// dentro de la app**: un APK se puede desempaquetar, y todo lo que lleve
/// dentro es público.
class Config {
  const Config._();

  // ╔═══════════════════════════════════════════════════════════════════════╗
  // ║  SERVIDOR AL QUE APUNTA LA APP                                         ║
  // ║                                                                        ║
  // ║  Deja UNA sola línea sin comentar. Para cambiar de servidor:           ║
  // ║    1. Comenta la línea activa (pon // delante).                        ║
  // ║    2. Descomenta la que quieras usar (quita el //).                    ║
  // ║    3. Si la app ya estaba abierta, reiníciala del todo (hot restart,   ║
  // ║       no hot reload), o recompila el APK si es para instalar.          ║
  // ║                                                                        ║
  // ║  Vale para `flutter run` y para `flutter build apk` por igual.         ║
  // ╚═══════════════════════════════════════════════════════════════════════╝

  // ── PRODUCCIÓN ─────────────────────────────────────────────────────────────
  // El servidor real. Es lo que debe llevar todo APK que se instale en los
  // teléfonos de las barberías.
  static const String _selected = production;

  // ── DESARROLLO ─────────────────────────────────────────────────────────────
  // El servidor local (`php artisan serve --port=8070` en barbora_web).
  // 10.0.2.2 es cómo el EMULADOR de Android ve el localhost del PC. En un
  // teléfono físico no sirve: usa la IP del PC en la red, por ejemplo
  // 'http://192.168.1.50:8070', y que el teléfono esté en el mismo wifi.
  // static const String _selected = development;

  // ── Direcciones ────────────────────────────────────────────────────────────
  static const String production = 'https://barbora.sczsoft.net';
  static const String development = 'http://10.0.2.2:8070';

  /// Atajo sin tocar el código: si se compila con
  /// `--dart-define=BARBORA_API_URL=http://...`, esa dirección manda sobre la
  /// línea elegida arriba. Útil para una prueba puntual.
  static const String _override = String.fromEnvironment('BARBORA_API_URL');

  static String get apiBaseUrl =>
      _override.isNotEmpty ? _stripSlash(_override) : _selected;

  static String get apiUrl => '$apiBaseUrl/api/v1';

  /// ¿Apunta a producción? La pantalla de acceso lo usa para no enseñar la URL
  /// del servidor a los usuarios finales, y los mensajes de error para no
  /// hablar de «la red local».
  static bool get isProduction => apiBaseUrl == production;

  /// Nombre con el que este dispositivo aparece en la lista de sesiones.
  /// La API revoca el token anterior del mismo nombre al volver a entrar.
  static const String deviceNameFallback = 'Dispositivo Barbora';

  static const Duration requestTimeout = Duration(seconds: 20);

  static String _stripSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

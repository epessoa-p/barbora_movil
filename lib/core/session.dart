import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lo que sobrevive a cerrar la app: el token y la barbería elegida.
///
/// Van al almacenamiento seguro del sistema (Keychain en iOS, EncryptedShared
/// Preferences en Android) porque el token da acceso a los datos del negocio.
/// En SharedPreferences quedaría en texto plano y sería legible en un móvil
/// con root.
class Session {
  Session({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'barbora.token';
  static const _companyKey = 'barbora.company_id';

  String? _token;
  int? _companyId;

  String? get token => _token;
  int? get companyId => _companyId;
  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Lee lo guardado. Se llama una vez al arrancar.
  Future<void> load() async {
    _token = await _storage.read(key: _tokenKey);

    final rawCompany = await _storage.read(key: _companyKey);
    _companyId = rawCompany == null ? null : int.tryParse(rawCompany);
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> saveCompanyId(int? companyId) async {
    _companyId = companyId;

    if (companyId == null) {
      await _storage.delete(key: _companyKey);
      return;
    }

    await _storage.write(key: _companyKey, value: companyId.toString());
  }

  /// Borra todo. Se usa al cerrar sesión y cuando el servidor devuelve 401.
  Future<void> clear() async {
    _token = null;
    _companyId = null;

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _companyKey);
  }
}

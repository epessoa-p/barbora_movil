import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/session.dart';
import '../models/company.dart';
import '../models/me.dart';

/// En qué punto está la app. La pantalla raíz solo mira esto.
enum AuthStage {
  /// Leyendo el token guardado al arrancar.
  loading,

  /// No hay sesión: hay que iniciarla.
  loggedOut,

  /// Hay token, pero el usuario trabaja en varias barberías y falta elegir.
  choosingCompany,

  /// Todo listo.
  ready,

  /// Hay sesión, pero la suscripción de la barbería no deja entrar.
  subscriptionBlocked,
}

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.session}) {
    // Si el servidor dice que el token caducó, se cierra la sesión desde aquí
    // y no desde cada pantalla.
    api.onUnauthenticated = () => _forceLogout();
  }

  final ApiClient api;
  final Session session;

  AuthStage _stage = AuthStage.loading;
  AuthStage get stage => _stage;

  Me? _me;
  Me? get me => _me;

  List<Company> _companies = const [];
  List<Company> get companies => _companies;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  Map<String, List<String>> _fieldErrors = const {};
  String? fieldError(String field) {
    final list = _fieldErrors[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  Company? get company => _me?.company;

  /// Arranque: si hay token guardado, se intenta entrar directo.
  Future<void> bootstrap() async {
    await session.load();

    if (!session.hasToken) {
      _set(AuthStage.loggedOut);
      return;
    }

    await refreshMe();
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _busy = true;
    _error = null;
    _fieldErrors = const {};
    notifyListeners();

    try {
      final body = await api.post(
        '/login',
        withAuth: false,
        withCompany: false,
        body: {
          'email': email.trim(),
          'password': password,
          'device_name': _deviceName(),
        },
      );

      await session.saveToken(body['token'] as String);

      _companies = (body['companies'] as List? ?? [])
          .map((e) => Company.fromJson(e as Map<String, dynamic>))
          .toList();

      final defaultCompany = body['default_company_id'] as int?;

      if (defaultCompany != null) {
        await session.saveCompanyId(defaultCompany);
        await refreshMe();
      } else {
        // Varias barberías: hay que preguntar en cuál está trabajando.
        _set(AuthStage.choosingCompany);
      }

      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _fieldErrors = e.errors;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> chooseCompany(Company company) async {
    await session.saveCompanyId(company.id);
    await refreshMe();
  }

  /// Vuelve a preguntar por la barbería, sin cerrar sesión.
  Future<void> changeCompany() async {
    if (_companies.isEmpty) {
      await _loadCompanies();
    }

    await session.saveCompanyId(null);
    _set(AuthStage.choosingCompany);
  }

  Future<void> refreshMe() async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final body = await api.get('/me');
      _me = Me.fromJson(body);

      // El servidor manda la empresa resuelta; se guarda por si se entró sin
      // cabecera por tener una sola.
      if (_me?.company != null) {
        await session.saveCompanyId(_me!.company!.id);
      }

      if (_me?.company == null) {
        await _loadCompanies();
        _set(AuthStage.choosingCompany);
        return;
      }

      _set(AuthStage.ready);
    } on ApiException catch (e) {
      if (e.requiresLogin) {
        await _forceLogout();
        return;
      }

      if (e.requiresCompany) {
        await _loadCompanies();
        await session.saveCompanyId(null);
        _set(AuthStage.choosingCompany);
        return;
      }

      if (e.kind == ApiErrorKind.subscriptionBlocked) {
        _error = e.message;
        _set(AuthStage.subscriptionBlocked);
        return;
      }

      _error = e.message;
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/logout', withCompany: false);
    } on ApiException {
      // Si el servidor no contesta da igual: lo importante es soltar el token
      // de este teléfono. El de servidor caduca o se revoca al volver a entrar.
    }

    await _forceLogout();
  }

  Future<void> _loadCompanies() async {
    try {
      final body = await api.get('/companies', withCompany: false);
      _companies = (body['data'] as List? ?? [])
          .map((e) => Company.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    }
  }

  Future<void> _forceLogout() async {
    await session.clear();
    _me = null;
    _companies = const [];
    _set(AuthStage.loggedOut);
  }

  void _set(AuthStage stage) {
    _stage = stage;
    notifyListeners();
  }

  /// Nombre con el que esta sesión aparece en el servidor.
  String _deviceName() {
    try {
      return '${Platform.operatingSystem} · ${Platform.localHostname}';
    } catch (_) {
      return Config.deviceNameFallback;
    }
  }
}

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';

/// La agenda del día.
///
/// Dos modos: la de toda la barbería (`/agenda`) y la del propio barbero
/// (`/my/agenda`). Cambian la ruta y poco más, así que comparten estado.
class AgendaController extends ChangeNotifier {
  AgendaController({required this.api});

  final ApiClient api;

  DateTime _day = DateTime.now();
  DateTime get day => DateTime(_day.year, _day.month, _day.day);

  bool _onlyMine = false;
  bool get onlyMine => _onlyMine;

  List<Appointment> _appointments = const [];
  List<Appointment> get appointments => _appointments;

  List<AgendaBlock> _blocks = const [];
  List<AgendaBlock> get blocks => _blocks;

  AgendaSummary _summary = const AgendaSummary();
  AgendaSummary get summary => _summary;

  bool _loading = false;
  bool get loading => _loading;

  ApiException? _error;
  ApiException? get error => _error;

  bool get isToday {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  Future<void> load({DateTime? day, bool? onlyMine}) async {
    if (day != null) _day = day;
    if (onlyMine != null) _onlyMine = onlyMine;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final path = _onlyMine ? '/my/agenda' : '/agenda';
      final body = await api.get(path, query: {'day': _dateParam(this.day)});

      _appointments = (body['data'] as List? ?? [])
          .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
          .toList();

      _summary = AgendaSummary.fromJson(
        body['summary'] as Map<String, dynamic>? ?? const {},
      );

      // «Mi agenda» no devuelve bloqueos: son de la barbería, no del día propio.
      _blocks = (body['blocks'] as List? ?? [])
          .map((e) => AgendaBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _error = e;
      _appointments = const [];
      _blocks = const [];
      _summary = const AgendaSummary();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> goToDay(DateTime day) => load(day: day);

  Future<void> previousDay() => load(day: day.subtract(const Duration(days: 1)));

  Future<void> nextDay() => load(day: day.add(const Duration(days: 1)));

  Future<void> goToToday() => load(day: DateTime.now());

  Future<void> toggleScope(bool onlyMine) => load(onlyMine: onlyMine);

  /// Cambia el estado de una cita y actualiza la lista en el sitio, sin
  /// recargar todo: el barbero está mirando la pantalla mientras lo hace.
  ///
  /// Devuelve null si salió bien, o el error para que la pantalla lo muestre.
  Future<ApiException?> updateStatus(
    Appointment appointment,
    String status, {
    String? cancelReason,
  }) async {
    try {
      final body = await api.patch(
        '/appointments/${appointment.id}/status',
        body: {
          'status': status,
          'cancel_reason': ?cancelReason,
        },
      );

      final updated = Appointment.fromJson(body['data'] as Map<String, dynamic>);

      _appointments = [
        for (final a in _appointments) a.id == updated.id ? updated : a,
      ];

      _recountSummary();
      notifyListeners();

      return null;
    } on ApiException catch (e) {
      return e;
    }
  }

  /// El resumen lo calcula el servidor, pero tras un cambio local hay que
  /// recalcularlo aquí o las cifras de arriba se quedarían desfasadas.
  void _recountSummary() {
    final blocking = _appointments.where((a) => !a.isReleased);

    _summary = AgendaSummary(
      total: _appointments.length,
      pending: _appointments
          .where((a) => a.status == 'reservada' || a.status == 'confirmada')
          .length,
      attended: _appointments.where((a) => a.status == 'atendida').length,
      noShow: _appointments.where((a) => a.status == 'no_show').length,
      minutes: blocking.fold(0, (sum, a) => sum + a.durationMinutes),
    );
  }

  static String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

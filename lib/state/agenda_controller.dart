import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/client.dart';

/// La agenda: de un día o de una semana.
///
/// Dos alcances: la de toda la barbería (`/agenda`) y la del propio barbero
/// (`/my/agenda`). Cambian la ruta y poco más, así que comparten estado. En la
/// de la barbería se puede filtrar por barbero.
///
/// En modo semana, [day] es el lunes de esa semana y se piden los 7 días de una
/// vez (`day` + `to`); las citas se agrupan por fecha en [byDay].
class AgendaController extends ChangeNotifier {
  AgendaController({required this.api});

  final ApiClient api;

  DateTime _day = DateTime.now();
  DateTime get day => DateTime(_day.year, _day.month, _day.day);

  bool _onlyMine = false;
  bool get onlyMine => _onlyMine;

  bool _week = false;
  bool get isWeek => _week;

  /// Barbero por el que se filtra la agenda de la barbería (null = todos).
  int? _personalId;
  int? get personalId => _personalId;

  /// Barberos que atienden, para el filtro (llegan con la agenda).
  List<StaffMember> _staff = const [];
  List<StaffMember> get staff => _staff;

  /// Los 7 días de la semana mostrada (lunes a domingo).
  List<DateTime> get weekDays =>
      [for (var i = 0; i < 7; i++) day.add(Duration(days: i))];

  /// Último día del rango pedido.
  DateTime get rangeEnd => _week ? day.add(const Duration(days: 6)) : day;

  /// Citas agrupadas por fecha (para la vista de semana).
  Map<DateTime, List<Appointment>> get byDay {
    final map = <DateTime, List<Appointment>>{};
    for (final a in _appointments) {
      final d = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
      map.putIfAbsent(d, () => []).add(a);
    }
    return map;
  }

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

  /// ¿El día (o la semana) mostrado contiene hoy?
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(day) && !today.isAfter(rangeEnd);
  }

  static DateTime _monday(DateTime d) {
    final only = DateTime(d.year, d.month, d.day);
    return only.subtract(Duration(days: only.weekday - DateTime.monday));
  }

  Future<void> load({DateTime? day, bool? onlyMine, bool? week, int? personalId, bool clearPersonal = false}) async {
    if (week != null) _week = week;
    if (day != null) _day = day;
    if (onlyMine != null) _onlyMine = onlyMine;
    if (personalId != null) _personalId = personalId;
    if (clearPersonal) _personalId = null;

    // En semana, el día ancla siempre es el lunes.
    if (_week) _day = _monday(_day);

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final path = _onlyMine ? '/my/agenda' : '/agenda';
      final body = await api.get(path, query: {
        'day': _dateParam(this.day),
        if (_week) 'to': _dateParam(rangeEnd),
        // El filtro por barbero solo aplica a la agenda de la barbería.
        if (!_onlyMine && _personalId != null) 'personal_id': _personalId,
      });

      if (body['staff'] is List) {
        _staff = (body['staff'] as List)
            .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
            .toList();
      }

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

  /// Atrás/adelante: un día, o una semana en modo semana.
  Future<void> previousDay() => load(day: day.subtract(Duration(days: _week ? 7 : 1)));

  Future<void> nextDay() => load(day: day.add(Duration(days: _week ? 7 : 1)));

  Future<void> goToToday() => load(day: DateTime.now());

  Future<void> toggleScope(bool onlyMine) => load(onlyMine: onlyMine);

  /// Día ↔ semana. Al volver a día se queda en hoy si hoy está en la semana,
  /// si no en el lunes que se veía.
  Future<void> setWeek(bool week) {
    if (week == _week) return Future.value();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = !week && isToday ? today : day;
    return load(week: week, day: target);
  }

  /// Filtra por barbero (null = todos).
  Future<void> setPersonal(int? id) =>
      id == null ? load(clearPersonal: true) : load(personalId: id);

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

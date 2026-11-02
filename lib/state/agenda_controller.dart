import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/client.dart';

/// Cuánto abarca la agenda que se ve.
enum AgendaView { day, week, month }

/// La agenda: de un día, de una semana o de un mes (calendario).
///
/// Dos alcances: la de toda la barbería (`/agenda`) y la del propio barbero
/// (`/my/agenda`). Cambian la ruta y poco más, así que comparten estado. En la
/// de la barbería se puede filtrar por barbero.
///
/// En semana, [day] es el lunes; en mes, el día 1. Se pide todo el rango de
/// una vez (`day` + `to`) y las citas se agrupan por fecha en [byDay].
class AgendaController extends ChangeNotifier {
  AgendaController({required this.api});

  final ApiClient api;

  DateTime _day = DateTime.now();
  DateTime get day => DateTime(_day.year, _day.month, _day.day);

  bool _onlyMine = false;
  bool get onlyMine => _onlyMine;

  AgendaView _view = AgendaView.day;
  AgendaView get view => _view;
  bool get isWeek => _view == AgendaView.week;
  bool get isMonth => _view == AgendaView.month;

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
  DateTime get rangeEnd => switch (_view) {
        AgendaView.day => day,
        AgendaView.week => day.add(const Duration(days: 6)),
        AgendaView.month => DateTime(day.year, day.month + 1, 0),
      };

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

  Future<void> load({DateTime? day, bool? onlyMine, AgendaView? view, int? personalId, bool clearPersonal = false}) async {
    if (view != null) _view = view;
    if (day != null) _day = day;
    if (onlyMine != null) _onlyMine = onlyMine;
    if (personalId != null) _personalId = personalId;
    if (clearPersonal) _personalId = null;

    // El día ancla: el lunes en semana, el día 1 en mes.
    if (_view == AgendaView.week) _day = _monday(_day);
    if (_view == AgendaView.month) _day = DateTime(_day.year, _day.month, 1);

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final path = _onlyMine ? '/my/agenda' : '/agenda';
      final body = await api.get(path, query: {
        'day': _dateParam(this.day),
        if (_view != AgendaView.day) 'to': _dateParam(rangeEnd),
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

  /// Atrás/adelante: un día, una semana o un mes, según la vista.
  Future<void> previousDay() => load(day: _shift(-1));

  Future<void> nextDay() => load(day: _shift(1));

  DateTime _shift(int step) => switch (_view) {
        AgendaView.day => day.add(Duration(days: step)),
        AgendaView.week => day.add(Duration(days: 7 * step)),
        AgendaView.month => DateTime(day.year, day.month + step, 1),
      };

  Future<void> goToToday() => load(day: DateTime.now());

  Future<void> toggleScope(bool onlyMine) => load(onlyMine: onlyMine);

  /// Cambia de vista. Si hoy cae en lo que se veía, la nueva vista arranca
  /// en hoy; si no, en el primer día de lo que se veía.
  Future<void> setView(AgendaView view) {
    if (view == _view) return Future.value();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return load(view: view, day: isToday ? today : day);
  }

  /// Desde el calendario: abre ese día en la vista de día.
  Future<void> openDay(DateTime day) => load(view: AgendaView.day, day: day);

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

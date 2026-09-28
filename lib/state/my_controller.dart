import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/commission.dart';

/// Lo del propio barbero: su horario y sus comisiones.
///
/// La API acota estas rutas a la ficha de personal del usuario, así que aquí no
/// hace falta filtrar nada: lo que llega ya es suyo.
class MyController extends ChangeNotifier {
  MyController({required this.api});

  final ApiClient api;

  // ── Horario ─────────────────────────────────────────────────────────────
  List<WorkSlot> _schedule = const [];
  List<WorkSlot> get schedule => _schedule;

  bool _loadingSchedule = false;
  bool get loadingSchedule => _loadingSchedule;

  ApiException? _scheduleError;
  ApiException? get scheduleError => _scheduleError;

  /// Agrupado por día de la semana, en orden de lunes a domingo.
  Map<int, List<WorkSlot>> get scheduleByWeekday {
    final map = <int, List<WorkSlot>>{};
    for (final slot in _schedule) {
      map.putIfAbsent(slot.weekday, () => []).add(slot);
    }
    return map;
  }

  int get weeklyMinutes => _schedule.fold(0, (sum, s) => sum + _minutesOf(s));

  Future<void> loadSchedule() async {
    _loadingSchedule = true;
    _scheduleError = null;
    notifyListeners();

    try {
      final body = await api.get('/my/schedule');
      _schedule = (body['data'] as List? ?? [])
          .map((e) => WorkSlot.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _scheduleError = e;
      _schedule = const [];
    } finally {
      _loadingSchedule = false;
      notifyListeners();
    }
  }

  // ── Comisiones ──────────────────────────────────────────────────────────
  CommissionReport? _commissions;
  CommissionReport? get commissions => _commissions;

  bool _loadingCommissions = false;
  bool get loadingCommissions => _loadingCommissions;

  ApiException? _commissionsError;
  ApiException? get commissionsError => _commissionsError;

  /// Atajo de periodo activo: mes, mes_pasado, semana…
  String _preset = 'mes';
  String get preset => _preset;

  Future<void> loadCommissions({String? preset}) async {
    if (preset != null) _preset = preset;

    _loadingCommissions = true;
    _commissionsError = null;
    notifyListeners();

    try {
      final body = await api.get('/my/commissions', query: {'preset': _preset});
      _commissions = CommissionReport.fromJson(body);
    } on ApiException catch (e) {
      _commissionsError = e;
      _commissions = null;
    } finally {
      _loadingCommissions = false;
      notifyListeners();
    }
  }

  static int _minutesOf(WorkSlot slot) {
    final start = _toMinutes(slot.startTime);
    final end = _toMinutes(slot.endTime);
    return (end - start).clamp(0, 24 * 60);
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/client.dart';
import '../models/service.dart';

/// El formulario de una cita: crear una nueva o reprogramar una existente.
///
/// Vive solo mientras está abierta la pantalla (se crea con ella), así que al
/// salir no queda nada a medias para la próxima reserva.
///
/// El flujo: cliente → barbero → servicios → día → hora. La hora sale de
/// `GET /booking/slots`, que aplica las mismas reglas que al reservar: así el
/// usuario elige de una lista de horas que funcionan, en vez de probar.
///
/// Al reprogramar ([editing]) se rellena con lo que ya tenía la cita. El
/// servidor ignora el hueco de la propia cita al calcular las horas libres, así
/// que su hora actual sigue apareciendo como elegible.
class BookingController extends ChangeNotifier {
  BookingController({required this.api, DateTime? day, int? personalId, Appointment? editing})
      : _editingId = editing?.id,
        _day = _onlyDate(editing?.startsAt ?? day ?? DateTime.now()),
        _personalId = editing?.personal?.id ?? personalId,
        _time = editing == null ? null : _hhmm(editing.startsAt),
        notes = editing?.notes ?? '' {
    if (editing != null) {
      _client = editing.client == null
          ? null
          : Client(
              id: editing.client!.id,
              fullName: editing.client!.fullName,
              phone: editing.client!.phone,
            );
      _serviceIds.addAll(editing.services.map((s) => s.id));
    }
  }

  final ApiClient api;

  /// Id de la cita que se reprograma, o null si es nueva.
  final int? _editingId;

  bool get isEditing => _editingId != null;

  // ── Catálogos ───────────────────────────────────────────────────────────
  List<StaffMember> staff = const [];
  List<Service> services = const [];

  bool loadingCatalog = true;
  ApiException? catalogError;

  // ── Lo elegido ──────────────────────────────────────────────────────────
  Client? _client;
  Client? get client => _client;

  int? _personalId;
  int? get personalId => _personalId;

  final Set<int> _serviceIds = {};
  Set<int> get serviceIds => _serviceIds;

  DateTime _day;
  DateTime get day => _day;

  String? _time;
  String? get time => _time;

  String notes;

  // ── Huecos ──────────────────────────────────────────────────────────────
  List<String> slots = const [];
  bool loadingSlots = false;
  ApiException? slotsError;

  // ── Envío ───────────────────────────────────────────────────────────────
  bool saving = false;

  StaffMember? get barber =>
      staff.where((s) => s.id == _personalId).firstOrNull;

  List<Service> get selectedServices =>
      services.where((s) => _serviceIds.contains(s.id)).toList();

  int get durationMinutes =>
      selectedServices.fold(0, (sum, s) => sum + s.durationMinutes);

  double get total => selectedServices.fold(0, (sum, s) => sum + s.price);

  /// ¿Hay lo necesario para pedir huecos?
  bool get canLookForSlots => _personalId != null && _serviceIds.isNotEmpty;

  bool get canSubmit =>
      _client != null && canLookForSlots && _time != null && !saving;

  Future<void> loadCatalog() async {
    loadingCatalog = true;
    catalogError = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        api.get('/staff'),
        // No /services: ese pide services.view, y recepción reserva sin él.
        api.get('/booking/services'),
      ]);

      staff = (results[0]['data'] as List? ?? [])
          .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
          .toList();

      services = (results[1]['data'] as List? ?? [])
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList();

      // Si el barbero que venía preseleccionado no atiende citas, se olvida.
      if (_personalId != null && barber == null) _personalId = null;

      // Con un solo barbero no hay nada que elegir.
      if (_personalId == null && staff.length == 1) _personalId = staff.first.id;

      // Al reprogramar se arrastran los servicios de la cita; se conservan solo
      // los que siguen en el catálogo, para que duración y total cuadren con lo
      // que se ve en pantalla.
      final ids = services.map((s) => s.id).toSet();
      _serviceIds.retainWhere(ids.contains);

      // Si ya hay con qué (reprogramando), se piden las horas de arranque.
      if (canLookForSlots) await loadSlots();
    } on ApiException catch (e) {
      catalogError = e;
    } finally {
      loadingCatalog = false;
      notifyListeners();
    }
  }

  // ── Cambios en el formulario ────────────────────────────────────────────
  // Todo lo que cambia la duración, el barbero o el día invalida la hora
  // elegida: un hueco libre para 30 minutos puede no estarlo para 60.

  void setClient(Client? client) {
    _client = client;
    notifyListeners();
  }

  void setPersonal(int id) {
    if (_personalId == id) return;
    _personalId = id;
    _refreshSlots();
  }

  void toggleService(int id) {
    _serviceIds.contains(id) ? _serviceIds.remove(id) : _serviceIds.add(id);
    _refreshSlots();
  }

  void setDay(DateTime day) {
    _day = _onlyDate(day);
    _refreshSlots();
  }

  void setTime(String time) {
    _time = time;
    notifyListeners();
  }

  void _refreshSlots() {
    _time = null;
    notifyListeners();
    loadSlots();
  }

  Future<void> loadSlots() async {
    if (!canLookForSlots) {
      slots = const [];
      notifyListeners();
      return;
    }

    loadingSlots = true;
    slotsError = null;
    notifyListeners();

    // Se recuerda qué se pidió: si el usuario cambia algo mientras llega la
    // respuesta, la respuesta vieja no debe pisar la nueva.
    final request = '$_personalId|$_day|${_serviceIds.join(',')}';

    try {
      final body = await api.get('/booking/slots', query: {
        'personal_id': _personalId,
        'date': _dateParam(_day),
        // El cliente HTTP manda la lista como «services[]=1&services[]=2».
        for (final (i, id) in _serviceIds.indexed) 'services[$i]': id,
      });

      if (request != '$_personalId|$_day|${_serviceIds.join(',')}') return;

      slots = (body['data'] as List? ?? []).map((e) => '$e').toList();

      // Una hora preseleccionada (al reprogramar) que ya no esté libre se
      // suelta, para no enviar algo que el servidor rechazaría.
      if (_time != null && !slots.contains(_time)) _time = null;
    } on ApiException catch (e) {
      slotsError = e;
      slots = const [];
    } finally {
      loadingSlots = false;
      notifyListeners();
    }
  }

  /// Reserva (o reprograma). Devuelve la cita resultante, o lanza [ApiException].
  Future<Appointment> submit() async {
    saving = true;
    notifyListeners();

    try {
      final payload = {
        'client_id': _client!.id,
        'personal_id': _personalId,
        'date': _dateParam(_day),
        'time': _time,
        'services': _serviceIds.toList(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

      final body = isEditing
          ? await api.put('/appointments/$_editingId', body: payload)
          : await api.post('/appointments', body: payload);

      return Appointment.fromJson(body['data'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      // Si el hueco se ocupó mientras tanto, se refresca la lista para que el
      // usuario vea las horas que siguen libres.
      if (e.errors.containsKey('time')) {
        _time = null;
        loadSlots();
      }
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  static DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

import '../core/shop_time.dart';

/// Una cita, tal como llega de `GET /agenda`.
///
/// `startsAt` viene con la zona horaria de la barbería (la API usa ShopTime),
/// así que se conserva tal cual: NO se convierte a la hora del teléfono. Una
/// cita de las 15:00 es a las 15:00 en la barbería aunque el barbero tenga el
/// móvil en otra zona.
class Appointment {
  const Appointment({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.durationMinutes,
    required this.status,
    required this.statusLabel,
    this.isEditable = true,
    this.notes,
    this.client,
    this.personal,
    this.branch,
    this.services = const [],
    this.total,
    this.remindedAt,
  });

  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
  final int durationMinutes;

  /// reservada · confirmada · atendida · no_show · cancelada
  final String status;
  final String statusLabel;

  final bool isEditable;
  final String? notes;
  final AppointmentPerson? client;
  final AppointmentPerson? personal;
  final String? branch;
  final List<AppointmentService> services;
  final double? total;
  final DateTime? remindedAt;

  /// Los estados que ya no ocupan hueco en la agenda.
  bool get isReleased => status == 'cancelada' || status == 'no_show';

  bool get isDone => status == 'atendida';

  String get servicesLabel =>
      services.isEmpty ? 'Sin servicios' : services.map((s) => s.name).join(' + ');

  /// «09:00 – 09:30», con la hora tal como vino del servidor.
  String get timeRange => '${_hhmm(startsAt)} – ${_hhmm(endsAt)}';

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as int,
        // ShopTime y no DateTime.parse: éste devolvería el instante en UTC y
        // una cita de las 09:00 se vería a las 13:00. Ver core/shop_time.dart.
        startsAt: ShopTime.parse(json['starts_at'] as String),
        endsAt: ShopTime.parse(json['ends_at'] as String),
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        status: json['status'] as String? ?? '',
        statusLabel: json['status_label'] as String? ?? '',
        isEditable: json['is_editable'] as bool? ?? true,
        notes: json['notes'] as String?,
        client: json['client'] == null
            ? null
            : AppointmentPerson.fromJson(json['client'] as Map<String, dynamic>),
        personal: json['personal'] == null
            ? null
            : AppointmentPerson.fromJson(json['personal'] as Map<String, dynamic>),
        branch: json['branch'] as String?,
        services: (json['services'] as List?)
                ?.map((e) => AppointmentService.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        total: (json['total'] as num?)?.toDouble(),
        remindedAt: ShopTime.tryParse(json['reminded_at'] as String?),
      );
}

class AppointmentPerson {
  const AppointmentPerson({required this.id, required this.fullName, this.phone});

  final int id;
  final String fullName;
  final String? phone;

  factory AppointmentPerson.fromJson(Map<String, dynamic> json) => AppointmentPerson(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String?,
      );
}

class AppointmentService {
  const AppointmentService({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
  });

  final int id;
  final String name;

  /// Duración y precio congelados el día de la reserva, no los del catálogo.
  final int durationMinutes;
  final double price;

  factory AppointmentService.fromJson(Map<String, dynamic> json) => AppointmentService(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0,
      );
}

/// Resumen del día que acompaña a la lista de citas.
class AgendaSummary {
  const AgendaSummary({
    this.total = 0,
    this.pending = 0,
    this.attended = 0,
    this.noShow = 0,
    this.minutes = 0,
  });

  final int total;
  final int pending;
  final int attended;
  final int noShow;
  final int minutes;

  String get workloadLabel {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }

  factory AgendaSummary.fromJson(Map<String, dynamic> json) => AgendaSummary(
        total: json['total'] as int? ?? 0,
        pending: json['pending'] as int? ?? 0,
        attended: json['attended'] as int? ?? 0,
        noShow: json['no_show'] as int? ?? 0,
        minutes: json['minutes'] as int? ?? 0,
      );
}

/// Vacaciones, feriados y descansos que afectan al día.
class AgendaBlock {
  const AgendaBlock({
    required this.id,
    required this.title,
    required this.reason,
    required this.reasonLabel,
    required this.scope,
    this.personalId,
    this.allDay = false,
    required this.startsAt,
    required this.endsAt,
  });

  final int id;
  final String title;
  final String reason;
  final String reasonLabel;

  /// A quién afecta: el nombre del barbero, o «Toda la barbería».
  final String scope;
  final int? personalId;
  final bool allDay;
  final DateTime startsAt;
  final DateTime endsAt;

  bool get isCompanyWide => personalId == null;

  factory AgendaBlock.fromJson(Map<String, dynamic> json) => AgendaBlock(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        reasonLabel: json['reason_label'] as String? ?? '',
        scope: json['scope'] as String? ?? '',
        personalId: json['personal_id'] as int?,
        allDay: json['all_day'] as bool? ?? false,
        startsAt: ShopTime.parse(json['starts_at'] as String),
        endsAt: ShopTime.parse(json['ends_at'] as String),
      );
}

import '../core/shop_time.dart';
import 'appointment.dart';

/// Un cliente de la barbería, tal como llega de `GET /clients`.
class Client {
  const Client({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.documentNumber,
    this.preferences,
    this.allergies,
  });

  final int id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? documentNumber;

  /// Corte habitual, máquina, largo… Útil tenerlo a mano al reservar.
  final String? preferences;
  final String? allergies;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        documentNumber: json['document_number'] as String?,
        preferences: json['preferences'] as String?,
        allergies: json['allergies'] as String?,
      );
}

/// La ficha completa de `GET /clients/{id}`: el cliente, su resumen con la
/// barbería y sus últimas citas.
class ClientDetail {
  const ClientDetail({
    required this.client,
    required this.stats,
    this.recentAppointments = const [],
  });

  final Client client;
  final ClientStats stats;
  final List<Appointment> recentAppointments;

  factory ClientDetail.fromJson(Map<String, dynamic> json) => ClientDetail(
        client: Client.fromJson(json),
        stats: ClientStats.fromJson(json['stats'] as Map<String, dynamic>? ?? const {}),
        recentAppointments: (json['recent_appointments'] as List? ?? [])
            .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// El resumen de la relación del cliente con la barbería.
class ClientStats {
  const ClientStats({
    this.visits = 0,
    this.totalSpent = 0,
    this.upcoming = 0,
    this.lastVisit,
  });

  /// Visitas pagadas (comandas cobradas), no citas.
  final int visits;
  final double totalSpent;

  /// Citas por venir que aún ocupan hueco.
  final int upcoming;
  final DateTime? lastVisit;

  factory ClientStats.fromJson(Map<String, dynamic> json) => ClientStats(
        visits: json['visits'] as int? ?? 0,
        totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
        upcoming: json['upcoming'] as int? ?? 0,
        // Con la zona de la barbería (ShopTime), no la del teléfono.
        lastVisit: ShopTime.tryParse(json['last_visit'] as String?),
      );
}

/// Un barbero que atiende citas, de `GET /staff`.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.fullName,
    this.cargo,
    this.photoUrl,
    this.agendaColor,
  });

  final int id;
  final String fullName;
  final String? cargo;
  final String? photoUrl;

  /// Color del barbero en el calendario web, en formato `#RRGGBB`.
  final String? agendaColor;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        cargo: json['cargo'] as String?,
        photoUrl: json['photo_url'] as String?,
        agendaColor: json['agenda_color'] as String?,
      );
}

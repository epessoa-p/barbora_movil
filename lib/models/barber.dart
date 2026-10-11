/// Un barbero (personal), para gestionarlo desde la app. Llega de
/// `GET /personal` y se guarda con `POST`/`PUT /personal`.
class Barber {
  const Barber({
    required this.id,
    required this.fullName,
    this.cargoId,
    this.cargo,
    this.phone,
    this.specialty,
    this.idNumber,
    this.agendaColor,
    this.bookable = false,
    this.active = true,
    this.hasUser = false,
    this.photoUrl,
  });

  final int id;
  final String fullName;
  final int? cargoId;
  final String? cargo;
  final String? phone;
  final String? specialty;
  final String? idNumber;
  final String? agendaColor;

  /// ¿Atiende citas? (aparece al reservar).
  final bool bookable;
  final bool active;

  /// ¿Tiene cuenta de acceso? (la cuenta se gestiona en la web).
  final bool hasUser;
  final String? photoUrl;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  factory Barber.fromJson(Map<String, dynamic> json) => Barber(
        id: json['id'] as int,
        fullName: json['full_name'] as String? ?? '',
        cargoId: json['cargo_id'] as int?,
        cargo: json['cargo'] as String?,
        phone: json['phone'] as String?,
        specialty: json['specialty'] as String?,
        idNumber: json['id_number'] as String?,
        agendaColor: json['agenda_color'] as String?,
        bookable: json['bookable'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        hasUser: json['has_user'] as bool? ?? false,
        photoUrl: json['photo_url'] as String?,
      );
}

/// Un cargo, para el selector al crear/editar un barbero (`GET /cargos`).
class CargoOption {
  const CargoOption({required this.id, required this.name});

  final int id;
  final String name;

  factory CargoOption.fromJson(Map<String, dynamic> json) => CargoOption(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
      );
}

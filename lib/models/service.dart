/// Un servicio del catálogo, tal como llega de `GET /services`.
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
    this.description,
    this.category,
    this.active = true,
  });

  final int id;
  final String name;
  final int durationMinutes;
  final double price;
  final String? description;
  final String? category;
  final bool active;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        category: json['category'] as String?,
        active: json['active'] as bool? ?? true,
      );
}

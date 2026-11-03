/// Un servicio del catálogo, tal como llega de `GET /services`.
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
    this.description,
    this.category,
    this.categoryId,
    this.active = true,
    this.photoUrl,
  });

  /// Foto del servicio (sale también en el catálogo público), o null.
  final String? photoUrl;

  final int id;
  final String name;
  final int durationMinutes;
  final double price;
  final String? description;
  final String? category;
  final int? categoryId;
  final bool active;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        category: json['category'] as String?,
        categoryId: json['category_id'] as int?,
        active: json['active'] as bool? ?? true,
        photoUrl: json['photo_url'] as String?,
      );
}

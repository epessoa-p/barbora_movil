/// Una foto de la galería de un servicio (un corte), con su comentario.
class ServicePhoto {
  const ServicePhoto({required this.id, required this.url, this.caption});

  final int id;
  final String url;
  final String? caption;

  factory ServicePhoto.fromJson(Map<String, dynamic> json) => ServicePhoto(
        id: (json['id'] as num).toInt(),
        url: json['url'] as String? ?? '',
        caption: json['caption'] as String?,
      );
}

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
    this.photos = const [],
  });

  /// La portada (la primera de la galería; sale en el catálogo), o null.
  final String? photoUrl;

  /// La galería: los cortes, con su comentario. La primera es la portada.
  final List<ServicePhoto> photos;

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
        photos: (json['photos'] as List? ?? [])
            .map((e) => ServicePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

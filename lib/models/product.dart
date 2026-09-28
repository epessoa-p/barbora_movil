/// Un producto a la venta, tal como llega de `GET /products`.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.price,
    this.sku,
    this.tracksStock = true,
    this.stock,
    this.lowStock = false,
  });

  final int id;
  final String name;
  final String unit;
  final double price;
  final String? sku;

  final bool tracksStock;

  /// Lo que queda en almacén. **Null cuando no se lleva control**, que no es lo
  /// mismo que cero: un cero diría «se agotó» y no es verdad.
  final double? stock;

  final bool lowStock;

  /// ¿Se puede añadir a la comanda? Sin control de stock, siempre.
  bool get isAvailable => !tracksStock || (stock ?? 0) > 0;

  /// Lo que queda, en la unidad del producto: «3 unidades», «250 ml».
  String get stockLabel {
    if (!tracksStock) return 'Sin control de stock';

    final quantity = stock ?? 0;
    final number = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);

    return '$number ${_pluralUnit(quantity)}';
  }

  String _pluralUnit(double quantity) {
    if (quantity == 1) return unit;

    return switch (unit) {
      'unidad' => 'unidades',
      'par' => 'pares',
      'caja' => 'cajas',
      _ => unit,
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? 'unidad',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        sku: json['sku'] as String?,
        tracksStock: json['tracks_stock'] as bool? ?? true,
        stock: (json['stock'] as num?)?.toDouble(),
        lowStock: json['low_stock'] as bool? ?? false,
      );
}

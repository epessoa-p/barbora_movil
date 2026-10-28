import '../core/shop_time.dart';
import 'block_options.dart';

/// Un producto del inventario (`GET /inventory/products`). A diferencia de
/// [Product] (el catálogo para cobrar), incluye también los que no se venden.
class InventoryProduct {
  const InventoryProduct({
    required this.id,
    required this.name,
    this.sku,
    this.categoryId,
    this.category,
    required this.unit,
    required this.unitLabel,
    required this.salePrice,
    required this.costPrice,
    required this.minStock,
    required this.trackStock,
    required this.isSellable,
    required this.active,
    this.stock,
    this.stockLabel,
    this.lowStock = false,
    this.description,
    this.marginPercent,
    this.stocks = const [],
    this.movements = const [],
  });

  final int id;
  final String name;
  final String? sku;
  final int? categoryId;
  final String? category;
  final String unit;
  final String unitLabel;
  final double salePrice;
  final double costPrice;
  final double minStock;
  final bool trackStock;
  final bool isSellable;
  final bool active;

  /// Null si no lleva control de existencias (no es lo mismo que cero).
  final double? stock;

  /// «13 unidades», «40 ml»: ya formateado por el servidor.
  final String? stockLabel;
  final bool lowStock;

  // Solo en la ficha (`GET /inventory/products/{id}`).
  final String? description;
  final double? marginPercent;
  final List<StockLine> stocks;
  final List<StockMove> movements;

  factory InventoryProduct.fromJson(Map<String, dynamic> json) => InventoryProduct(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String?,
        categoryId: json['category_id'] as int?,
        category: json['category'] as String?,
        unit: json['unit'] as String? ?? 'unidad',
        unitLabel: json['unit_label'] as String? ?? '',
        salePrice: (json['sale_price'] as num?)?.toDouble() ?? 0,
        costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
        minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
        trackStock: json['track_stock'] as bool? ?? true,
        isSellable: json['is_sellable'] as bool? ?? true,
        active: json['active'] as bool? ?? true,
        stock: (json['stock'] as num?)?.toDouble(),
        stockLabel: json['stock_label'] as String?,
        lowStock: json['low_stock'] as bool? ?? false,
        description: json['description'] as String?,
        marginPercent: (json['margin_percent'] as num?)?.toDouble(),
        stocks: (json['stocks'] as List? ?? [])
            .map((e) => StockLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        movements: (json['movements'] as List? ?? [])
            .map((e) => StockMove.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Existencia en un almacén.
class StockLine {
  const StockLine({required this.warehouseId, required this.warehouse, required this.quantity, required this.label});

  final int warehouseId;
  final String warehouse;
  final double quantity;
  final String label;

  factory StockLine.fromJson(Map<String, dynamic> json) => StockLine(
        warehouseId: json['warehouse_id'] as int,
        warehouse: json['warehouse'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        label: json['quantity_label'] as String? ?? '',
      );
}

/// Un movimiento del historial: entrada, salida o ajuste.
class StockMove {
  const StockMove({
    required this.id,
    required this.type,
    required this.typeLabel,
    this.reasonLabel,
    required this.quantity,
    required this.quantityAfter,
    this.warehouse,
    this.reference,
    this.createdBy,
    this.createdAt,
  });

  final int id;
  final String type;
  final String typeLabel;
  final String? reasonLabel;

  /// Con signo: positivo entra, negativo sale.
  final double quantity;
  final double quantityAfter;
  final String? warehouse;
  final String? reference;
  final String? createdBy;
  final DateTime? createdAt;

  factory StockMove.fromJson(Map<String, dynamic> json) => StockMove(
        id: json['id'] as int,
        type: json['type'] as String? ?? '',
        typeLabel: json['type_label'] as String? ?? '',
        reasonLabel: json['reason_label'] as String?,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        quantityAfter: (json['quantity_after'] as num?)?.toDouble() ?? 0,
        warehouse: json['warehouse'] as String?,
        reference: json['reference'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: ShopTime.tryParse(json['created_at'] as String?),
      );
}

/// Lo que necesitan los formularios (`GET /inventory/options`).
class InventoryOptions {
  const InventoryOptions({
    this.categories = const [],
    this.warehouses = const [],
    this.units = const [],
    this.reasons = const [],
    this.limitReached = false,
  });

  final List<Option> categories;
  final List<Option> warehouses;
  final List<Option> units;
  final List<Option> reasons;

  /// El plan ya no admite más productos.
  final bool limitReached;

  factory InventoryOptions.fromJson(Map<String, dynamic> json) {
    List<Option> ids(String key, String label) => (json[key] as List? ?? [])
        .map((e) => Option((e as Map<String, dynamic>)['id'] as int, e[label] as String))
        .toList();
    List<Option> pairs(String key) => (json[key] as List? ?? [])
        .map((e) => Option((e as Map<String, dynamic>)['value'] as String, e['label'] as String))
        .toList();

    return InventoryOptions(
      categories: ids('categories', 'name'),
      warehouses: ids('warehouses', 'name'),
      units: pairs('units'),
      reasons: pairs('reasons'),
      limitReached: (json['limit'] as Map<String, dynamic>?)?['reached'] as bool? ?? false,
    );
  }
}

/// Número sin decimales sobrantes: 13 y no 13.00; 2.5 y no 2.50.
String trimNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

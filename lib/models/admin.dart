// Lo que se administra desde la sección «Administración»: los datos de la
// barbería, sus sucursales, cajas y métodos de pago. Llega de `/admin/...`.

/// Los datos de la barbería que ella misma edita (`GET /admin/company`).
class CompanyProfile {
  const CompanyProfile({
    required this.id,
    required this.name,
    this.taxId,
    this.taxIdLabel,
    this.address,
    this.phone,
    this.email,
    this.receiptFooter,
    this.logoUrl,
    this.cashCountMode = 'total',
  });

  final int id;
  final String name;

  /// El NIT no se edita desde la app: solo se muestra.
  final String? taxId;
  final String? taxIdLabel;
  final String? address;
  final String? phone;
  final String? email;
  final String? receiptFooter;
  final String? logoUrl;

  /// Cierre de caja: «total» o «denominations» (billetes y monedas).
  final String cashCountMode;

  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        taxId: json['tax_id'] as String?,
        taxIdLabel: json['tax_id_label'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        receiptFooter: json['receipt_footer'] as String?,
        logoUrl: json['logo_url'] as String?,
        cashCountMode: json['cash_count_mode'] as String? ?? 'total',
      );
}

class BranchItem {
  const BranchItem({
    required this.id,
    required this.name,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.managerName,
    this.active = true,
    this.cajasCount = 0,
    this.personalCount = 0,
  });

  final int id;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final String? managerName;
  final bool active;
  final int cajasCount;
  final int personalCount;

  factory BranchItem.fromJson(Map<String, dynamic> json) => BranchItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        managerName: json['manager_name'] as String?,
        active: json['active'] as bool? ?? true,
        cajasCount: json['cajas_count'] as int? ?? 0,
        personalCount: json['personal_count'] as int? ?? 0,
      );
}

class CajaItem {
  const CajaItem({
    required this.id,
    required this.name,
    this.code,
    this.description,
    this.branchId,
    this.branch,
    this.personalId,
    this.personal,
    this.active = true,
  });

  final int id;
  final String name;
  final String? code;
  final String? description;
  final int? branchId;
  final String? branch;

  /// Responsable; null = caja general de la sucursal.
  final int? personalId;
  final String? personal;
  final bool active;

  factory CajaItem.fromJson(Map<String, dynamic> json) => CajaItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
        description: json['description'] as String?,
        branchId: json['branch_id'] as int?,
        branch: json['branch'] as String?,
        personalId: json['personal_id'] as int?,
        personal: json['personal'] as String?,
        active: json['active'] as bool? ?? true,
      );
}

/// Un método de pago para administrarlo (a diferencia del de `/me`, trae el
/// id y también los dados de baja).
class PaymentMethodItem {
  const PaymentMethodItem({
    required this.id,
    required this.slug,
    required this.name,
    this.countsAsCash = false,
    this.requiresReference = false,
    this.active = true,
  });

  final int id;
  final String slug;
  final String name;
  final bool countsAsCash;
  final bool requiresReference;
  final bool active;

  factory PaymentMethodItem.fromJson(Map<String, dynamic> json) => PaymentMethodItem(
        id: json['id'] as int,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        countsAsCash: json['counts_as_cash'] as bool? ?? false,
        requiresReference: json['requires_reference'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );
}

/// Una opción de un selector: sucursal, cargo o personal.
class PickOption {
  const PickOption({required this.id, required this.name, this.branchId});

  final int id;
  final String name;

  /// Solo para el personal: su sucursal base.
  final int? branchId;

  factory PickOption.fromJson(Map<String, dynamic> json) => PickOption(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        branchId: json['branch_id'] as int?,
      );

  static List<PickOption> listOf(Object? json) => (json as List? ?? [])
      .map((e) => PickOption.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Una categoría de servicios, para administrarla (`/service-categories/manage`).
class ServiceCategoryItem {
  const ServiceCategoryItem({
    required this.id,
    required this.name,
    this.description,
    this.color = '#6B7280',
    this.active = true,
    this.servicesCount = 0,
  });

  final int id;
  final String name;
  final String? description;

  /// Hexadecimal, «#AA3300».
  final String color;
  final bool active;
  final int servicesCount;

  factory ServiceCategoryItem.fromJson(Map<String, dynamic> json) => ServiceCategoryItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        color: json['color'] as String? ?? '#6B7280',
        active: json['active'] as bool? ?? true,
        servicesCount: json['services_count'] as int? ?? 0,
      );
}

/// El catálogo público de la barbería (`/admin/catalog`).
class CatalogSettings {
  const CatalogSettings({
    required this.enabled,
    required this.showProducts,
    required this.url,
    required this.posterUrl,
    this.servicesCount = 0,
  });

  /// ¿Publicado? Apagado, el enlace y el QR no muestran nada.
  final bool enabled;
  final bool showProducts;

  /// El enlace público (lo que lleva el QR).
  final String url;

  /// El afiche imprimible con el QR (se guarda como PDF desde el navegador).
  final String posterUrl;
  final int servicesCount;

  factory CatalogSettings.fromJson(Map<String, dynamic> json) => CatalogSettings(
        enabled: json['enabled'] as bool? ?? false,
        showProducts: json['show_products'] as bool? ?? false,
        url: json['url'] as String? ?? '',
        posterUrl: json['poster_url'] as String? ?? '',
        servicesCount: json['services_count'] as int? ?? 0,
      );
}

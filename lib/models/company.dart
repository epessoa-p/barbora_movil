class Company {
  const Company({
    required this.id,
    required this.name,
    this.currency,
    this.currencySymbol,
    this.timezone,
    this.country,
    this.taxId,
    this.taxIdLabel,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
    this.receiptFooter,
  });

  final int id;
  final String name;
  final String? currency;
  final String? currencySymbol;
  final String? timezone;
  final String? country;

  // ── Lo que sale en el comprobante ─────────────────────────────────────────
  final String? taxId;

  /// «NIT» en Bolivia, «RUC» en Perú… Lo manda el servidor según el país.
  final String? taxIdLabel;
  final String? address;
  final String? phone;
  final String? email;

  /// URL absoluta, armada con el host por el que llamó el propio móvil.
  final String? logoUrl;
  final String? receiptFooter;

  /// El símbolo con el que se muestran los importes. `Bs` en Bolivia.
  String get symbol => currencySymbol ?? currency ?? '';

  /// «NIT: 1023456789», o null si la barbería no tiene cargado el número.
  String? get taxLine =>
      (taxId == null || taxId!.isEmpty) ? null : '${taxIdLabel ?? 'NIT'}: $taxId';

  String get footer => (receiptFooter == null || receiptFooter!.trim().isEmpty)
      ? '¡Gracias por tu visita!'
      : receiptFooter!;

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        currency: json['currency'] as String?,
        currencySymbol: json['currency_symbol'] as String?,
        timezone: json['timezone'] as String?,
        country: json['country'] as String?,
        taxId: json['tax_id'] as String?,
        taxIdLabel: json['tax_id_label'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        logoUrl: json['logo_url'] as String?,
        receiptFooter: json['receipt_footer'] as String?,
      );
}

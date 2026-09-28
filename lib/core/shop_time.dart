/// Fechas que llegan de la API, leídas como «hora de la barbería».
///
/// La API manda las horas con el desfase del local:
/// `2026-09-26T09:00:00-04:00` significa «las nueve de la mañana en la
/// barbería». Pero `DateTime.parse` devuelve el instante en UTC, así que su
/// `.hour` sería 13 y la agenda mostraría las citas cuatro horas corridas.
///
/// Aquí se hace lo contrario que en un `toLocal()` normal: se conservan los
/// componentes de reloj que mandó el servidor y se descarta la zona. Una cita
/// de las 09:00 se ve a las 09:00 esté donde esté el teléfono, que es lo que
/// quiere quien trabaja en el local.
///
/// Es la contraparte de `App\Support\ShopTime` en barbora_web.
class ShopTime {
  const ShopTime._();

  static final RegExp _zone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Lee una fecha ISO 8601 conservando la hora de pared del servidor.
  static DateTime parse(String iso) {
    // Se quita el desfase y se lee lo que queda como hora local del móvil:
    // los componentes son ya los de la barbería.
    final naive = iso.replaceFirst(_zone, '');

    return DateTime.parse(naive);
  }

  /// Igual, pero tolerando null y cadenas vacías.
  static DateTime? tryParse(String? iso) {
    if (iso == null || iso.isEmpty) return null;

    try {
      return parse(iso);
    } on FormatException {
      return null;
    }
  }
}

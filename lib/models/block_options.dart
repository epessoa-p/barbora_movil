/// Lo que necesita el formulario de bloqueos; llega con `GET /agenda-blocks`.
class BlockOptions {
  const BlockOptions({
    this.reasons = const [],
    this.staff = const [],
    this.branches = const [],
  });

  /// Motivos: vacaciones, feriado, descanso… (valor + etiqueta).
  final List<Option> reasons;

  /// Barberos que atienden.
  final List<Option> staff;
  final List<Option> branches;

  factory BlockOptions.fromJson(Map<String, dynamic> json) => BlockOptions(
        reasons: _list(json['reasons'], (e) => Option(e['value'] as String, e['label'] as String)),
        staff: _list(json['staff'], (e) => Option(e['id'] as int, e['full_name'] as String)),
        branches: _list(json['branches'], (e) => Option(e['id'] as int, e['name'] as String)),
      );

  static List<Option> _list(Object? raw, Option Function(Map<String, dynamic>) map) =>
      (raw as List? ?? []).map((e) => map(e as Map<String, dynamic>)).toList();
}

/// Una opción de lista: el valor que se manda y el texto que se ve.
class Option {
  const Option(this.value, this.label);

  final Object value;
  final String label;
}

import 'package:flutter/services.dart';

/// Los nombres (barbero, servicio, cliente) se escriben siempre en mayúsculas,
/// igual que en la web. Correos, teléfonos y notas no pasan por aquí.
class UpperCaseFormatter extends TextInputFormatter {
  const UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;

    // Con la misma longitud la selección sigue valiendo tal cual; si cambia
    // (la «ß» pasa a «SS») el cursor va al final.
    if (upper.length != newValue.text.length) {
      return TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }

    return newValue.copyWith(text: upper);
  }
}

/// Para lo que se guarda: también los nombres antiguos que se editan sin tocar.
String upperName(String value) => value.trim().toUpperCase();

import 'package:barbora_movil/core/shop_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// La hora que manda el servidor es la de la barbería, no un instante UTC.
///
/// Este archivo existe porque el fallo contrario no se ve: la app no revienta,
/// simplemente muestra todas las citas corridas unas horas, y nadie lo nota
/// hasta que un cliente llega y no hay nadie esperándolo.
void main() {
  test('se conserva la hora de pared, no el instante UTC', () {
    final d = ShopTime.parse('2026-09-26T09:00:00-04:00');

    expect(d.hour, 9);
    expect(d.minute, 0);
    expect(d.day, 26);
  });

  test('DateTime.parse haría justo lo contrario', () {
    // Se deja escrito para que quede claro por qué existe ShopTime.
    expect(DateTime.parse('2026-09-26T09:00:00-04:00').toUtc().hour, 13);
    expect(ShopTime.parse('2026-09-26T09:00:00-04:00').hour, 9);
  });

  test('vale con desfase positivo', () {
    expect(ShopTime.parse('2026-09-26T15:30:00+02:00').hour, 15);
  });

  test('vale con Z', () {
    expect(ShopTime.parse('2026-09-26T08:45:00Z').hour, 8);
  });

  test('vale sin desfase', () {
    expect(ShopTime.parse('2026-09-26T07:15:00').hour, 7);
  });

  test('tryParse devuelve null en lugar de romper', () {
    expect(ShopTime.tryParse(null), isNull);
    expect(ShopTime.tryParse(''), isNull);
    expect(ShopTime.tryParse('no es una fecha'), isNull);
  });
}

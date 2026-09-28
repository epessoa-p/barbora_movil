import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/barbora_theme.dart';

/// El logotipo de la marca.
///
/// Se usa `logo.svg` (el monograma), que es vector puro y se dibuja igual en
/// cualquier pantalla. El `brand.svg` del panel web NO sirve aquí: lleva la
/// palabra «BARBORA» como elemento `<text>` en Montserrat, y ningún móvil trae
/// esa fuente, así que el nombre saldría con otra letra.
///
/// Por eso el nombre se compone aquí, con la Montserrat que va empaquetada en
/// la app: mismo monograma, misma tipografía y mismo espaciado que la web.
class BrandLogo extends StatelessWidget {
  /// Monograma más el nombre. Para la pantalla de acceso.
  const BrandLogo.full({super.key, this.height = 64}) : _withWordmark = true;

  /// Solo el monograma. Para cabeceras y sitios estrechos.
  const BrandLogo.mark({super.key, this.height = 34}) : _withWordmark = false;

  static const String _asset = 'assets/img/logo.svg';

  final bool _withWordmark;
  final double height;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      _asset,
      height: height,
      fit: BoxFit.contain,
      // Se reserva el hueco mientras carga: si no, la pantalla da un salto.
      placeholderBuilder: (_) => SizedBox(height: height, width: height),
    );

    if (!_withWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: height * .32),
        Text(
          'BARBORA',
          style: TextStyle(
            fontFamily: 'Montserrat',
            // El logotipo usa el peso 800; la fuente es variable, así que se
            // pide por eje en vez de confiar en un fichero por peso.
            fontVariations: const [FontVariation('wght', 800)],
            fontSize: height * .42,
            letterSpacing: height * .10,
            color: Colors.white,
            height: 1,
          ),
        ),
        SizedBox(height: height * .13),
        Text(
          'APP DEL PERSONAL',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontVariations: const [FontVariation('wght', 600)],
            fontSize: height * .12,
            letterSpacing: height * .075,
            color: BarboraTheme.titanium.withValues(alpha: .75),
            height: 1,
          ),
        ),
      ],
    );
  }
}

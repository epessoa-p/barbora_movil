// Herramienta, no una prueba. Rasteriza el logo de la marca (SVG) a los PNG
// que piden flutter_launcher_icons y flutter_native_splash, que no leen SVG.
//
// No termina en «_test.dart», así que `flutter test` no lo corre con la suite.
// Se ejecuta a mano cuando cambia el logo:
//
//   flutter test tool/render_app_assets.dart
//
// Deja los PNG en tool/branding/. De ahí los toman las dos herramientas de
// iconos; ver pubspec.yaml.
import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// El icono completo: monograma dentro del squircle oscuro. Para iOS y el
/// icono clásico de Android. Los cortes van en un tono dentro del degradado
/// del squircle.
String get _icon => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#14161D"/>
      <stop offset="100%" stop-color="#07080B"/>
    </linearGradient>
    $_gradients
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#bg)"/>
  <rect x="2" y="2" width="508" height="508" rx="110" fill="none" stroke="#262933" stroke-width="4"/>
  ${_markGroup('#0A0B0E')}
</svg>
''';

/// El monograma recortado al ras, para el primer plano del icono adaptativo.
/// El margen de seguridad NO va aquí: lo añade flutter_launcher_icons con su
/// inset del 16%. Si pusiéramos aire además del suyo, la «B» saldría diminuta.
/// El viewBox ciñe la marca (su caja es ~x[161,382] y[142,350]) con poco borde.
String get _foreground => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="141 116 260 260">
  <defs>$_gradients</defs>
  ${_markGroup('#0B0C10')}
</svg>
''';

/// El monograma con bastante aire, para el splash: ahí la imagen se centra a su
/// tamaño, así que conviene que no ocupe toda la pantalla. Ocupa ~27% del lienzo.
String get _splash => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-157 -157 826 826">
  <defs>$_gradients</defs>
  ${_markGroup('#0B0C10')}
</svg>
''';

const _gradients = '''
    <linearGradient id="iconRed" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ED5442"/>
      <stop offset="100%" stop-color="#B82E1E"/>
    </linearGradient>
    <linearGradient id="iconWhite" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#C5C9D3"/>
    </linearGradient>
''';

/// El monograma. Los cortes (las cavidades que dan forma a la «B») se pintan
/// encima, así que su color tiene que ser el del fondo sobre el que se verá el
/// dibujo: [cut].
String _markGroup(String cut) => '''
  <g transform="translate(142, 126) scale(1.6)">
    <path d="M 20 10 L 48 10 L 48 140 L 20 140 Z" fill="url(#iconWhite)" />
    <path d="M 58 10 L 102 10 C 124 10 138 22 138 42 C 138 60 125 70 105 72 L 58 72 Z" fill="url(#iconRed)" />
    <path d="M 58 82 L 108 82 C 130 82 146 95 146 115 C 146 132 130 140 106 140 L 58 140 Z" fill="url(#iconRed)" />
    <polygon points="48,70 150,70 150,84 48,84" fill="$cut" />
    <polygon points="12,110 55,67 63,75 20,118" fill="$cut" />
    <circle cx="128" cy="22" r="5" fill="$cut" />
    <circle cx="128" cy="22" r="3" fill="#FFFFFF" />
  </g>
''';

// Cada PNG en su propia prueba: así cada render arranca con un binding limpio
// (encadenarlos en una sola prueba colgaba el segundo toImage).
void main() {
  testWidgets('icono con fondo', (t) => _render(t, _icon, 'tool/branding/app_icon.png'));

  testWidgets('primer plano adaptativo',
      (t) => _render(t, _foreground, 'tool/branding/app_icon_foreground.png'));

  testWidgets('logo del splash',
      (t) => _render(t, _splash, 'tool/branding/splash_logo.png'));
}

Future<void> _render(WidgetTester tester, String svg, String path, {double size = 1024}) async {
  final key = GlobalKey();

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: SizedBox(
        width: size,
        height: size,
        child: SvgPicture.string(svg, fit: BoxFit.contain),
      ),
    ),
  );

  // flutter_svg decodifica fuera del frame; un par de frames bastan y no cuelgan.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));

  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;

  late final Uint8List pngBytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ImageByteFormat.png);
    pngBytes = data!.buffer.asUint8List();
  });

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes);

  // ignore: avoid_print
  print('✓ $path (${size.toInt()}px)');
}

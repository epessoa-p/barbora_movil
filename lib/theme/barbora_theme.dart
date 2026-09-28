import 'package:flutter/material.dart';

/// Tema de la app, tomado de los colores del logo (`assets/img/brand.svg`):
/// fondo negro grafito, acento rojo cobre y grises titanio.
class BarboraTheme {
  const BarboraTheme._();

  // ── Marca ───────────────────────────────────────────────────────────────
  /// El negro del logo. Es el color de las cabeceras.
  static const Color ink = Color(0xFF0B0C10);
  static const Color inkSoft = Color(0xFF14161D);
  static const Color inkLine = Color(0xFF262933);

  /// Rojo cobre: el acento de la marca. Se usa con cuentagotas, solo para lo
  /// que de verdad pide atención.
  static const Color copper = Color(0xFFE64A38);
  static const Color copperLight = Color(0xFFED5442);
  static const Color copperDark = Color(0xFFB82E1E);

  static const Color titanium = Color(0xFFA0A5B1);
  static const Color titaniumLight = Color(0xFFC5C9D3);

  // ── Superficies claras ──────────────────────────────────────────────────
  static const Color canvas = Color(0xFFF5F6F8);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE4E6EB);
  static const Color textMuted = Color(0xFF6C757D);

  /// Degradado de la marca, para las cabeceras y la pantalla de acceso.
  static const LinearGradient inkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [inkSoft, Color(0xFF07080B)],
  );

  static const LinearGradient copperGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [copperLight, copperDark],
  );

  /// Colores de estado de una cita. Los mismos que los badges del panel web,
  /// para que quien use ambos no tenga que reaprender nada.
  static const Map<String, Color> statusColors = {
    'reservada': Color(0xFF6C757D),
    'confirmada': Color(0xFF0EA5E9),
    'atendida': Color(0xFF16A34A),
    'no_show': Color(0xFFF59E0B),
    'cancelada': copperDark,
  };

  static Color statusColor(String status) => statusColors[status] ?? titanium;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: copper,
      primary: ink,
      secondary: copper,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.2,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(copper, width: 1.6),
        errorBorder: _inputBorder(copperDark),
        focusedErrorBorder: _inputBorder(copperDark, width: 1.6),
        labelStyle: const TextStyle(color: textMuted),
        prefixIconColor: textMuted,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: copper,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: border),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? ink : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : textMuted,
          ),
          side: WidgetStateProperty.all(const BorderSide(color: border)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: copper.withValues(alpha: .12),
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? copperDark : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 23,
            color: s.contains(WidgetState.selected) ? copperDark : textMuted,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}

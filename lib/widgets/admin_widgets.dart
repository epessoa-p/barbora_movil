import 'package:flutter/material.dart';

import '../theme/barbora_theme.dart';

/// Pantalla propia con la barra oscura de la app. Las secciones que no traen
/// Scaffold (como Reportes) se abren envueltas en esta.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: BarboraTheme.inkSoft,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(title),
        ),
        body: child,
      );
}

/// Etiqueta pequeña: «Inactivo», «Efectivo», el código de una sucursal…
class AdminTag extends StatelessWidget {
  const AdminTag(this.text, {super.key, this.color = BarboraTheme.textMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: BarboraTheme.canvas,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BarboraTheme.border),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );
}

/// Una fila de una lista de administración: icono, título, detalle y etiquetas.
/// Sin [onTap] (sin permiso de edición) no lleva la flecha.
class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.dimmed = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> tags;

  /// Los dados de baja se ven apagados.
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: BarboraTheme.copper.withValues(alpha: dimmed ? .05 : .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: dimmed ? BarboraTheme.titanium : BarboraTheme.copperDark, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: dimmed ? BarboraTheme.textMuted : BarboraTheme.ink,
                      ),
                    ),
                    ...tags,
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// El botón de guardar de los formularios, con su estado de «guardando».
class AdminSaveButton extends StatelessWidget {
  const AdminSaveButton({super.key, required this.saving, required this.label, required this.onPressed});

  final bool saving;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: saving ? null : onPressed,
        icon: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : const Icon(Icons.save),
        label: Text(saving ? 'Guardando…' : label),
      );
}

/// Error general de un formulario (el que no es de un campo concreto).
class AdminFormError extends StatelessWidget {
  const AdminFormError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13)),
        );
}

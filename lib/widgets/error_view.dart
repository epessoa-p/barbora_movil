import 'package:flutter/material.dart';

import '../core/api_exception.dart';

/// Cómo se le enseña un error de la API a una persona.
///
/// Vive en un solo sitio para que cada pantalla no invente su propio mensaje:
/// el icono y el botón salen del tipo de error, no de dónde ocurrió.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final ApiException error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (error.kind) {
      ApiErrorKind.network => (Icons.wifi_off, const Color(0xFF6B7280)),
      ApiErrorKind.planRequired => (Icons.lock_outline, const Color(0xFF7C3AED)),
      ApiErrorKind.forbidden => (Icons.block, const Color(0xFFDC2626)),
      ApiErrorKind.subscriptionBlocked ||
      ApiErrorKind.subscriptionReadonly =>
        (Icons.credit_card_off, const Color(0xFFF59E0B)),
      ApiErrorKind.notFound => (Icons.search_off, const Color(0xFF6B7280)),
      _ => (Icons.error_outline, const Color(0xFFDC2626)),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: color),
            const SizedBox(height: 16),
            Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),

            // Un fallo de plan o de permiso no se arregla reintentando: ahí el
            // botón sobraría y solo haría perder el tiempo.
            if (onRetry != null && _canRetry) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _canRetry => switch (error.kind) {
        ApiErrorKind.planRequired ||
        ApiErrorKind.forbidden ||
        ApiErrorKind.subscriptionBlocked =>
          false,
        _ => true,
      };
}

/// Estado vacío, para cuando no hay error pero tampoco datos.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.black26),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../theme/barbora_theme.dart';

/// Una cita en la lista del día.
///
/// La hora va a la izquierda en una columna propia: bajando por la lista se lee
/// la mañana entera de un vistazo, que es lo que hace un barbero.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.showBarber,
    this.currencySymbol = '',
    this.onTap,
  });

  final Appointment appointment;

  /// En «mi agenda» sobra el nombre del barbero: todas son suyas.
  final bool showBarber;
  final String currencySymbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = BarboraTheme.statusColor(appointment.status);
    final released = appointment.isReleased;

    return Opacity(
      opacity: released ? .62 : 1,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Franja de color del estado, pegada al borde de la tarjeta.
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appointment.timeRange.split(' – ').first,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.6,
                                decoration: released ? TextDecoration.lineThrough : null,
                                color: released ? BarboraTheme.textMuted : BarboraTheme.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${appointment.durationMinutes} min',
                              style: const TextStyle(
                                fontSize: 11,
                                color: BarboraTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.client?.fullName ?? 'Sin cliente',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: -.2,
                                  decoration:
                                      released ? TextDecoration.lineThrough : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                appointment.servicesLabel,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: BarboraTheme.textMuted,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (showBarber && appointment.personal != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.content_cut,
                                      size: 11,
                                      color: BarboraTheme.titanium,
                                    ),
                                    const SizedBox(width: 4),
                                    // Expanded y una sola línea: hay nombres
                                    // largos, y aquí solo cabe uno.
                                    Expanded(
                                      child: Text(
                                        appointment.personal!.fullName,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: BarboraTheme.titanium,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Se acota el ancho de esta columna: sin límite, una
                        // etiqueta de estado larga («No se presentó») se comía
                        // el espacio del cliente y de los servicios. El tope
                        // da justo para esa etiqueta en una línea, que es la
                        // más larga de las cinco.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 114),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusPill(
                                label: appointment.statusLabel,
                                color: color,
                              ),
                              if (appointment.total != null &&
                                  appointment.total! > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '$currencySymbol '
                                  '${appointment.total!.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: BarboraTheme.ink,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La etiqueta redondeada del estado de una cita.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: .1,
        ),
      ),
    );
  }
}

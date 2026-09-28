import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/commission.dart';
import '../state/auth_controller.dart';
import '../state/my_controller.dart';
import '../theme/barbora_theme.dart';

/// Quién soy, mi horario y la salida.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthController>().me?.hasStaffProfile ?? false) {
        context.read<MyController>().loadSchedule();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final my = context.watch<MyController>();
    final me = auth.me;

    if (me == null) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _IdentityCard(
          name: me.personal?.fullName ?? me.user.name,
          subtitle: me.personal?.cargo ?? me.role?.name ?? '',
          email: me.user.email,
          initials: me.personal?.initials ?? _initialsOf(me.user.name),
        ),
        const SizedBox(height: 14),

        _InfoCard(
          title: 'Barbería',
          icon: Icons.store_outlined,
          rows: [
            ('Nombre', auth.company?.name ?? '—'),
            if (me.planName != null) ('Plan', me.planName!),
            if (me.subscription != null)
              ('Suscripción', _subscriptionLabel(me.subscription!.status)),
          ],
          action: auth.companies.length > 1
              ? _CardAction(
                  label: 'Cambiar de barbería',
                  icon: Icons.swap_horiz,
                  onTap: () => context.read<AuthController>().changeCompany(),
                )
              : null,
        ),

        if (me.hasStaffProfile) ...[
          const SizedBox(height: 14),
          _ScheduleCard(
            loading: my.loadingSchedule,
            slots: my.schedule,
            byWeekday: my.scheduleByWeekday,
            weeklyMinutes: my.weeklyMinutes,
            error: my.scheduleError,
            onRetry: () => my.loadSchedule(),
          ),
        ],

        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: auth.busy ? null : () => _confirmLogout(context),
          icon: const Icon(Icons.logout, size: 19),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            foregroundColor: BarboraTheme.copperDark,
            side: BorderSide(color: BarboraTheme.copper.withValues(alpha: .35)),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthController>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Tendrás que volver a escribir tu correo y contraseña la próxima vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: BarboraTheme.copperDark),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed == true) await auth.logout();
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String _subscriptionLabel(String status) => switch (status) {
        'trial' => 'En prueba',
        'active' => 'Al día',
        'past_due' => 'Con pago pendiente',
        'suspended' => 'Suspendida',
        'cancelled' => 'Cancelada',
        _ => status,
      };
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.subtitle,
    required this.email,
    required this.initials,
  });

  final String name;
  final String subtitle;
  final String email;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: BarboraTheme.copperGradient,
              borderRadius: BorderRadius.circular(19),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: BarboraTheme.copperLight,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(
                    color: BarboraTheme.titanium.withValues(alpha: .7),
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction {
  const _CardAction({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.action,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  final _CardAction? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(title: title, icon: icon),
          const Divider(height: 1),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Text(
                    r.$1,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: BarboraTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    r.$2,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (action != null) ...[
            const Divider(height: 1),
            InkWell(
              onTap: action!.onTap,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Icon(action!.icon, size: 17, color: BarboraTheme.copperDark),
                    const SizedBox(width: 9),
                    Text(
                      action!.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: BarboraTheme.copperDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.loading,
    required this.slots,
    required this.byWeekday,
    required this.weeklyMinutes,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final List<WorkSlot> slots;
  final Map<int, List<WorkSlot>> byWeekday;
  final int weeklyMinutes;
  final dynamic error;
  final VoidCallback onRetry;

  static const _weekdays = {
    1: 'Lunes',
    2: 'Martes',
    3: 'Miércoles',
    4: 'Jueves',
    5: 'Viernes',
    6: 'Sábado',
    7: 'Domingo',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Mi horario',
            icon: Icons.schedule,
            trailing: weeklyMinutes > 0 ? '${(weeklyMinutes / 60).round()} h/semana' : null,
          ),
          const Divider(height: 1),

          if (loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: CircularProgressIndicator(color: BarboraTheme.copper),
              ),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error.message as String,
                style: const TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
              ),
            )
          else if (slots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Todavía no tienes turnos asignados. El encargado los define '
                'desde el panel.',
                style: TextStyle(fontSize: 13, color: BarboraTheme.textMuted, height: 1.4),
              ),
            )
          else
            // Los siete días siempre, para que se vea también cuáles libra.
            ..._weekdays.entries.map((day) {
              final daySlots = byWeekday[day.key] ?? const [];

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 82,
                      child: Text(
                        day.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              daySlots.isEmpty ? FontWeight.w400 : FontWeight.w600,
                          color: daySlots.isEmpty
                              ? BarboraTheme.titanium
                              : BarboraTheme.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: daySlots.isEmpty
                          ? const Text(
                              'Libre',
                              style: TextStyle(
                                fontSize: 13,
                                color: BarboraTheme.titanium,
                              ),
                            )
                          : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: daySlots
                                  .map(
                                    (s) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: BarboraTheme.copper
                                            .withValues(alpha: .09),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        s.range,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: BarboraTheme.copperDark,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.icon, this.trailing});

  final String title;
  final IconData icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: BarboraTheme.titanium),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: BarboraTheme.textMuted,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!,
              style: const TextStyle(fontSize: 11.5, color: BarboraTheme.titanium),
            ),
          ],
        ],
      ),
    );
  }
}

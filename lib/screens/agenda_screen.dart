import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/appointment.dart';
import '../state/agenda_controller.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/appointment_tile.dart';
import '../widgets/error_view.dart';
import 'appointment_detail_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  @override
  void initState() {
    super.initState();

    // Quien tiene ficha de barbero entra viendo lo suyo; quien no (recepción,
    // administración) ve la agenda completa, que es lo que necesita.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      context.read<AgendaController>().load(
            onlyMine: auth.me?.hasStaffProfile ?? false,
          );
    });
  }

  Future<void> _pickDay() async {
    final agenda = context.read<AgendaController>();

    final picked = await showDatePicker(
      context: context,
      initialDate: agenda.day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es'),
    );

    if (picked != null) {
      await agenda.goToDay(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agenda = context.watch<AgendaController>();
    final auth = context.watch<AuthController>();
    final hasProfile = auth.me?.hasStaffProfile ?? false;
    final symbol = auth.company?.symbol ?? '';

    return Column(
      children: [
        _DayHeader(
          day: agenda.day,
          isToday: agenda.isToday,
          summary: agenda.summary,
          showSummary: !agenda.loading && agenda.error == null,
          onPrevious: agenda.previousDay,
          onNext: agenda.nextDay,
          onPick: _pickDay,
          onToday: agenda.goToToday,
        ),

        Expanded(
          child: RefreshIndicator(
            color: BarboraTheme.copper,
            onRefresh: () => agenda.load(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (hasProfile)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Mi agenda'),
                            icon: Icon(Icons.person_outline, size: 16),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('La barbería'),
                            icon: Icon(Icons.store_outlined, size: 16),
                          ),
                        ],
                        selected: {agenda.onlyMine},
                        onSelectionChanged: (s) => agenda.toggleScope(s.first),
                      ),
                    ),
                  ),

                if (agenda.blocks.isNotEmpty)
                  SliverToBoxAdapter(child: _BlocksBanner(blocks: agenda.blocks)),

                ..._body(agenda, symbol),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _body(AgendaController agenda, String symbol) {
    if (agenda.loading && agenda.appointments.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: BarboraTheme.copper),
          ),
        ),
      ];
    }

    if (agenda.error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(error: agenda.error!, onRetry: () => agenda.load()),
        ),
      ];
    }

    if (agenda.appointments.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            icon: Icons.event_available_outlined,
            title: agenda.onlyMine ? 'No tienes citas este día' : 'Sin citas este día',
            subtitle: agenda.isToday
                ? 'Cuando recepción agende algo, aparecerá aquí.'
                : 'Desliza hacia abajo para actualizar.',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        sliver: SliverList.separated(
          itemCount: agenda.appointments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 11),
          itemBuilder: (context, i) {
            final appointment = agenda.appointments[i];

            return AppointmentTile(
              appointment: appointment,
              showBarber: !agenda.onlyMine,
              currencySymbol: symbol,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AppointmentDetailScreen(appointmentId: appointment.id),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

/// Cabecera oscura con el día y el resumen. Es la única pieza de marca que se
/// ve siempre, así que lleva el degradado.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.isToday,
    required this.summary,
    required this.showSummary,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  final DateTime day;
  final bool isToday;
  final AgendaSummary summary;
  final bool showSummary;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEEE', 'es').format(day);
    final rest = DateFormat("d 'de' MMMM", 'es').format(day);

    return Container(
      decoration: const BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          children: [
            Row(
              children: [
                _NavButton(icon: Icons.chevron_left, onTap: onPrevious),
                Expanded(
                  child: InkWell(
                    onTap: onPick,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            weekday.isEmpty
                                ? ''
                                : weekday[0].toUpperCase() + weekday.substring(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              letterSpacing: -.3,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            rest,
                            style: TextStyle(
                              color: BarboraTheme.titanium.withValues(alpha: .8),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _NavButton(icon: Icons.chevron_right, onTap: onNext),
              ],
            ),

            if (!isToday)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextButton.icon(
                  onPressed: onToday,
                  icon: const Icon(Icons.today, size: 15),
                  label: const Text('Ir a hoy', style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: BarboraTheme.copperLight,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),

            if (showSummary && summary.total > 0) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _Stat(value: '${summary.total}', label: 'citas'),
                    _StatDivider(),
                    _Stat(value: '${summary.pending}', label: 'pendientes'),
                    _StatDivider(),
                    _Stat(
                      value: '${summary.attended}',
                      label: 'atendidas',
                      // En verde, no en el cobre de la marca: el cobre es el
                      // color de lo que reclama atención, y esto es lo hecho.
                      highlight: summary.attended > 0
                          ? BarboraTheme.statusColor('atendida')
                          : null,
                    ),
                    _StatDivider(),
                    _Stat(value: summary.workloadLabel, label: 'ocupado'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: BarboraTheme.titanium, size: 26),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.highlight});

  final String value;
  final String label;

  /// Color con el que resaltar la cifra. Null la deja en blanco.
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: highlight ?? Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: BarboraTheme.titanium.withValues(alpha: .65),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: Colors.white.withValues(alpha: .1),
      );
}

class _BlocksBanner extends StatelessWidget {
  const _BlocksBanner({required this.blocks});

  final List<AgendaBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.do_not_disturb_on_outlined, size: 16, color: Color(0xFFB45309)),
              SizedBox(width: 7),
              Text(
                'No se atiende',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...blocks.map(
            (b) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${b.scope} · ${b.title}'
                '${b.allDay ? '' : ' (${_hhmm(b.startsAt)}–${_hhmm(b.endsAt)})'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF92400E),
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

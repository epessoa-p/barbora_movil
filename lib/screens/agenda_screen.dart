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
import 'blocks_screen.dart';
import 'home_shell.dart';
import 'reminders_screen.dart';

/// Las pestañas de abajo de la agenda.
enum AgendaTab { agenda, reminders, blocks }

/// La agenda con su barra inferior: Agenda (por defecto), Recordatorios y
/// Bloqueos. Cada pestaña sale solo si el plan y el permiso la dejan; con una
/// sola, no hay barra.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, this.onNewAppointment});

  /// «Nueva cita» (lo decide el shell, que sabe si hay permiso). Null = sin botón.
  final VoidCallback? onNewAppointment;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  AgendaTab _tab = AgendaTab.agenda;

  /// Pestañas ya abiertas: se montan al visitarlas y se conservan.
  final Set<AgendaTab> _visited = {AgendaTab.agenda};

  @override
  Widget build(BuildContext context) {
    final menu = AppMenu(context.watch<AuthController>().me);
    final tabs = [
      AgendaTab.agenda,
      if (menu.reminders) AgendaTab.reminders,
      if (menu.blocks) AgendaTab.blocks,
    ];
    final tab = tabs.contains(_tab) ? _tab : AgendaTab.agenda;
    _visited.add(tab);

    return Scaffold(
      body: IndexedStack(
        index: tabs.indexOf(tab),
        children: [
          for (final t in tabs)
            !_visited.contains(t)
                ? const SizedBox.shrink()
                : switch (t) {
                    AgendaTab.agenda => const _AgendaView(),
                    AgendaTab.reminders => const RemindersScreen(),
                    AgendaTab.blocks => const BlocksScreen(),
                  },
        ],
      ),
      floatingActionButton: tab == AgendaTab.agenda && widget.onNewAppointment != null
          ? FloatingActionButton.extended(
              // Sin hero: la agenda queda montada (IndexedStack) mientras otra
              // sección muestra su propio botón, y dos con el mismo tag chocan.
              heroTag: null,
              onPressed: widget.onNewAppointment,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva cita', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: tabs.indexOf(tab),
              onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
              destinations: [
                for (final t in tabs)
                  switch (t) {
                    AgendaTab.agenda => const NavigationDestination(
                        icon: Icon(Icons.calendar_today_outlined),
                        selectedIcon: Icon(Icons.calendar_today),
                        label: 'Agenda',
                      ),
                    AgendaTab.reminders => const NavigationDestination(
                        icon: Icon(Icons.notifications_none),
                        selectedIcon: Icon(Icons.notifications),
                        label: 'Recordatorios',
                      ),
                    AgendaTab.blocks => const NavigationDestination(
                        icon: Icon(Icons.event_busy_outlined),
                        selectedIcon: Icon(Icons.event_busy),
                        label: 'Bloqueos',
                      ),
                  },
              ],
            ),
    );
  }
}

/// La agenda en sí: cabecera, filtros y citas del día, la semana o el mes.
class _AgendaView extends StatefulWidget {
  const _AgendaView();

  @override
  State<_AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<_AgendaView> {
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
          view: agenda.view,
          rangeEnd: agenda.rangeEnd,
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

                SliverToBoxAdapter(child: _Filters(agenda: agenda)),

                if (agenda.blocks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _BlocksBanner(blocks: agenda.blocks),
                  ),

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

    if (agenda.isWeek) return [_week(agenda, symbol)];

    if (agenda.isMonth) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          sliver: SliverToBoxAdapter(
            child: _MonthGrid(
              month: agenda.day,
              byDay: agenda.byDay,
              onDay: agenda.openDay,
            ),
          ),
        ),
      ];
    }

    if (agenda.appointments.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            icon: Icons.event_available_outlined,
            title: agenda.onlyMine
                ? 'No tienes citas este día'
                : 'Sin citas este día',
            subtitle: agenda.isToday
                ? 'Cuando recepción agende algo, aparecerá aquí.'
                : 'Desliza hacia abajo para actualizar.',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        // Margen inferior amplio: el botón «Nueva cita» flota encima.
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        sliver: SliverList.separated(
          itemCount: agenda.appointments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 11),
          itemBuilder: (context, i) {
            return _tile(agenda, agenda.appointments[i], symbol);
          },
        ),
      ),
    ];
  }

  /// La semana: los 7 días en orden, cada uno con sus citas. Los días vacíos
  /// se dejan a la vista para que se lea dónde hay hueco.
  Widget _week(AgendaController agenda, String symbol) {
    final byDay = agenda.byDay;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      sliver: SliverList.list(
        children: [
          for (final d in agenda.weekDays) ...[
            _WeekDayHeader(
              day: d,
              count: byDay[d]?.length ?? 0,
              isToday: d == today,
            ),
            if (byDay[d] == null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'Sin citas',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                ),
              )
            else
              for (final a in byDay[d]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: _tile(agenda, a, symbol),
                ),
          ],
        ],
      ),
    );
  }

  Widget _tile(
    AgendaController agenda,
    Appointment appointment,
    String symbol,
  ) {
    return AppointmentTile(
      appointment: appointment,
      showBarber: !agenda.onlyMine && agenda.personalId == null,
      currencySymbol: symbol,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              AppointmentDetailScreen(appointmentId: appointment.id),
        ),
      ),
    );
  }
}

/// Día / Semana, y el barbero (solo en la agenda de la barbería).
class _Filters extends StatelessWidget {
  const _Filters({required this.agenda});

  final AgendaController agenda;

  @override
  Widget build(BuildContext context) {
    final showBarber = !agenda.onlyMine && agenda.staff.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AgendaView>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: AgendaView.day, label: Text('Día')),
              ButtonSegment(value: AgendaView.week, label: Text('Semana')),
              ButtonSegment(value: AgendaView.month, label: Text('Mes')),
            ],
            selected: {agenda.view},
            onSelectionChanged: (s) => agenda.setView(s.first),
          ),
          if (showBarber) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              key: const Key('agenda-barber'),
              initialValue: agenda.personalId,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.content_cut, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 34),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                for (final s in agenda.staff)
                  DropdownMenuItem<int?>(
                    value: s.id,
                    child: Text(s.fullName, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: agenda.setPersonal,
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({
    required this.day,
    required this.count,
    required this.isToday,
  });

  final DateTime day;
  final int count;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat("EEEE d", 'es').format(day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            label[0].toUpperCase() + label.substring(1),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isToday ? BarboraTheme.copper : null,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 6),
            const Text(
              '· hoy',
              style: TextStyle(color: BarboraTheme.copper, fontSize: 12.5),
            ),
          ],
          const Spacer(),
          if (count > 0)
            Text(
              count == 1 ? '1 cita' : '$count citas',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

/// Cabecera oscura con el día y el resumen. Es la única pieza de marca que se
/// ve siempre, así que lleva el degradado.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.view,
    required this.rangeEnd,
    required this.isToday,
    required this.summary,
    required this.showSummary,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  final DateTime day;
  final AgendaView view;

  /// Último día del rango (igual a [day] en la vista de un día).
  final DateTime rangeEnd;
  final bool isToday;
  final AgendaSummary summary;
  final bool showSummary;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final end = rangeEnd;
    final weekday = switch (view) {
      AgendaView.day => DateFormat('EEEE', 'es').format(day),
      AgendaView.week => 'Semana',
      AgendaView.month => DateFormat('MMMM', 'es').format(day),
    };
    final rest = switch (view) {
      AgendaView.day => DateFormat("d 'de' MMMM", 'es').format(day),
      AgendaView.month => '${day.year}',
      AgendaView.week => day.month == end.month
          ? '${day.day} – ${DateFormat("d 'de' MMMM", 'es').format(end)}'
          : '${DateFormat("d 'de' MMM", 'es').format(day)} – '
              '${DateFormat("d 'de' MMM", 'es').format(end)}',
    };

    return Container(
      // Degradado vertical que arranca en el color de la barra superior, para
      // que cabecera y barra se lean como una sola pieza.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BarboraTheme.inkSoft, Color(0xFF07080B)],
        ),
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
                                : weekday[0].toUpperCase() +
                                      weekday.substring(1),
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
                              color: BarboraTheme.titanium.withValues(
                                alpha: .8,
                              ),
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
                  label: Text(
                    switch (view) {
                      AgendaView.day => 'Ir a hoy',
                      AgendaView.week => 'Ir a esta semana',
                      AgendaView.month => 'Ir a este mes',
                    },
                    style: const TextStyle(fontSize: 12.5),
                  ),
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

/// El mes como calendario: cada día con cuántas citas tiene. Tocar un día lo
/// abre en la vista de día.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.byDay, required this.onDay});

  /// Día 1 del mes.
  final DateTime month;
  final Map<DateTime, List<Appointment>> byDay;
  final ValueChanged<DateTime> onDay;

  static const _weekdays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Huecos antes del día 1: la semana empieza en lunes.
    final leading = month.weekday - DateTime.monday;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                for (final w in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: BarboraTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(child: _cell(r * 7 + c - leading + 1, daysInMonth, today)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int dayNumber, int daysInMonth, DateTime today) {
    if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox(height: 54);

    final date = DateTime(month.year, month.month, dayNumber);
    final count = byDay[date]?.length ?? 0;
    final isToday = date == today;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isToday ? BarboraTheme.copper.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onDay(date),
          child: SizedBox(
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14,
                    color: isToday ? BarboraTheme.copperDark : BarboraTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: BarboraTheme.copper,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  const SizedBox(height: 15),
              ],
            ),
          ),
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
              Icon(
                Icons.do_not_disturb_on_outlined,
                size: 16,
                color: Color(0xFFB45309),
              ),
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

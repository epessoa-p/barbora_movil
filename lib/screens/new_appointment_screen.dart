import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/client.dart';
import '../state/auth_controller.dart';
import '../state/booking_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/client_picker.dart';
import '../widgets/error_view.dart';

/// Reservar una cita desde el móvil.
///
/// Se rellena de arriba abajo: cliente, barbero, servicios, día y hora. La
/// hora no se escribe: se elige de las que el servidor dice que están libres,
/// con las mismas reglas que la agenda web (turno, bloqueos, otras citas).
///
/// Devuelve la [Appointment] creada o reprogramada al cerrar, o null si se
/// canceló. Si se pasa [editing], el formulario arranca con sus datos y guarda
/// con PUT en vez de crear una cita nueva.
class NewAppointmentScreen extends StatelessWidget {
  const NewAppointmentScreen({super.key, this.day, this.editing});

  /// Día con el que arranca el formulario: el que se miraba en la agenda.
  final DateTime? day;

  /// Cita que se reprograma. Null para una cita nueva.
  final Appointment? editing;

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthController>().me;

    // Un barbero que atiende reserva casi siempre para sí mismo.
    final ownId = (me?.personal?.bookable ?? false) ? me!.personal!.id : null;

    return ChangeNotifierProvider(
      create: (_) => BookingController(
        api: context.read<ApiClient>(),
        day: day,
        personalId: ownId,
        editing: editing,
      )..loadCatalog(),
      child: const _NewAppointmentView(),
    );
  }
}

class _NewAppointmentView extends StatefulWidget {
  const _NewAppointmentView();

  @override
  State<_NewAppointmentView> createState() => _NewAppointmentViewState();
}

class _NewAppointmentViewState extends State<_NewAppointmentView> {
  String? _error;

  Future<void> _submit() async {
    final booking = context.read<BookingController>();
    setState(() => _error = null);

    try {
      final appointment = await booking.submit();
      if (!mounted) return;
      Navigator.of(context).pop(appointment);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.firstErrorFor('time') ??
            e.firstErrorFor('personal_id') ??
            e.firstErrorFor('client_id') ??
            e.firstErrorFor('services') ??
            e.message;
      });
    }
  }

  Future<void> _pickDay() async {
    final booking = context.read<BookingController>();
    final today = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: booking.day.isBefore(DateTime(today.year, today.month, today.day))
          ? today
          : booking.day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      locale: const Locale('es'),
    );

    if (picked != null) booking.setDay(picked);
  }

  Future<void> _pickClient() async {
    final booking = context.read<BookingController>();
    final me = context.read<AuthController>().me;

    final client = await ClientPickerSheet.show(
      context,
      api: context.read<ApiClient>(),
      canCreate: me?.can('clients.create') ?? false,
    );

    if (client != null) booking.setClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingController>();
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(booking.isEditing ? 'Reprogramar cita' : 'Nueva cita'),
      ),
      body: _body(booking, symbol),
      bottomNavigationBar: booking.loadingCatalog || booking.catalogError != null
          ? null
          : _SubmitBar(
              booking: booking,
              symbol: symbol,
              error: _error,
              onSubmit: _submit,
            ),
    );
  }

  Widget _body(BookingController booking, String symbol) {
    if (booking.loadingCatalog) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (booking.catalogError != null) {
      return ErrorView(error: booking.catalogError!, onRetry: booking.loadCatalog);
    }

    if (booking.staff.isEmpty) {
      return const EmptyView(
        icon: Icons.person_off_outlined,
        title: 'Nadie atiende citas',
        subtitle: 'Marca en la web qué personal atiende citas y define su horario.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Cliente ─────────────────────────────────────────────────────
        const _StepTitle(number: 1, title: 'Cliente'),
        _ClientCard(client: booking.client, onTap: _pickClient),

        // ── Barbero ─────────────────────────────────────────────────────
        const _StepTitle(number: 2, title: 'Barbero'),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: booking.staff.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final member = booking.staff[i];
              return _BarberChip(
                member: member,
                selected: member.id == booking.personalId,
                onTap: () => booking.setPersonal(member.id),
              );
            },
          ),
        ),

        // ── Servicios ───────────────────────────────────────────────────
        const _StepTitle(number: 3, title: 'Servicios'),
        if (booking.services.isEmpty)
          const _Hint('No hay servicios activos. Créalos en la web.')
        else
          Card(
            child: Column(
              children: [
                for (final (i, s) in booking.services.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  CheckboxListTile(
                    value: booking.serviceIds.contains(s.id),
                    onChanged: (_) => booking.toggleService(s.id),
                    activeColor: BarboraTheme.copper,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    subtitle: Text(
                      '${s.durationMinutes} min',
                      style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5),
                    ),
                    secondary: Text(
                      '$symbol ${s.price.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),

        // ── Día y hora ──────────────────────────────────────────────────
        const _StepTitle(number: 4, title: 'Día y hora'),
        _DayCard(day: booking.day, onTap: _pickDay),
        const SizedBox(height: 12),
        _SlotsGrid(booking: booking),

        // ── Notas ───────────────────────────────────────────────────────
        const _StepTitle(number: 5, title: 'Notas', optional: true),
        TextField(
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => booking.notes = v,
          decoration: const InputDecoration(
            hintText: 'Ej.: prefiere máquina 2, trae referencia…',
          ),
        ),
      ],
    );
  }
}

// ── Piezas ──────────────────────────────────────────────────────────────────

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title, this.optional = false});

  final int number;
  final String title;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: number == 1 ? 0 : 22, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: BarboraTheme.ink, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -.2),
          ),
          if (optional)
            const Text(
              '  · opcional',
              style: TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13, height: 1.4),
        ),
      );
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap});

  final Client? client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = client;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor:
                    c == null ? BarboraTheme.canvas : BarboraTheme.copper.withValues(alpha: .12),
                child: Icon(
                  c == null ? Icons.person_search_outlined : Icons.person,
                  color: c == null ? BarboraTheme.textMuted : BarboraTheme.copperDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c?.fullName ?? 'Elegir cliente',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: c == null ? BarboraTheme.textMuted : BarboraTheme.ink,
                      ),
                    ),
                    if (c?.phone != null || c?.preferences != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [c!.phone, c.preferences].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5),
                      ),
                    ],
                    if (c?.allergies != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠ ${c!.allergies}',
                        style: const TextStyle(
                          color: BarboraTheme.copperDark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                c == null ? Icons.chevron_right : Icons.swap_horiz,
                color: BarboraTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarberChip extends StatelessWidget {
  const _BarberChip({required this.member, required this.selected, required this.onTap});

  final StaffMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(member.agendaColor) ?? BarboraTheme.titanium;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? BarboraTheme.ink : BarboraTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? BarboraTheme.ink : BarboraTheme.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: color.withValues(alpha: selected ? .9 : .18),
              foregroundImage:
                  member.photoUrl == null ? null : NetworkImage(member.photoUrl!),
              child: Text(
                member.initials,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? Colors.white : BarboraTheme.ink,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              member.fullName.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : BarboraTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onTap});

  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat("EEEE d 'de' MMMM", 'es').format(day);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.event_outlined, color: BarboraTheme.copperDark),
        title: Text(
          label[0].toUpperCase() + label.substring(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: const Text(
          'Cambiar',
          style: TextStyle(color: BarboraTheme.copperDark, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SlotsGrid extends StatelessWidget {
  const _SlotsGrid({required this.booking});

  final BookingController booking;

  @override
  Widget build(BuildContext context) {
    if (!booking.canLookForSlots) {
      return const _Hint('Elige barbero y al menos un servicio para ver las horas libres.');
    }

    if (booking.loadingSlots) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: BarboraTheme.copper),
          ),
        ),
      );
    }

    if (booking.slotsError != null) {
      return Row(
        children: [
          Expanded(child: _Hint(booking.slotsError!.message)),
          TextButton(onPressed: booking.loadSlots, child: const Text('Reintentar')),
        ],
      );
    }

    if (booking.slots.isEmpty) {
      return _Hint(
        '${booking.barber?.fullName ?? 'El barbero'} no tiene huecos libres de '
        '${booking.durationMinutes} min este día. Prueba con otro día.',
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slot in booking.slots)
          ChoiceChip(
            label: Text(slot),
            selected: slot == booking.time,
            onSelected: (_) => booking.setTime(slot),
            showCheckmark: false,
            selectedColor: BarboraTheme.copper,
            backgroundColor: BarboraTheme.surface,
            side: BorderSide(
              color: slot == booking.time ? BarboraTheme.copper : BarboraTheme.border,
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              color: slot == booking.time ? Colors.white : BarboraTheme.ink,
            ),
          ),
      ],
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.booking,
    required this.symbol,
    required this.error,
    required this.onSubmit,
  });

  final BookingController booking;
  final String symbol;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final hasServices = booking.serviceIds.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: BarboraTheme.surface,
        border: Border(top: BorderSide(color: BarboraTheme.border)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13, height: 1.35),
              ),
            ),
          if (hasServices)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(
                    '${booking.durationMinutes} min'
                    '${booking.time == null ? '' : ' · ${booking.time}'}',
                    style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '$symbol ${booking.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          FilledButton.icon(
            onPressed: booking.canSubmit ? onSubmit : null,
            icon: booking.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.event_available),
            label: Text(_label()),
          ),
        ],
      ),
    );
  }

  /// El botón dice qué falta, en vez de quedarse gris sin explicación.
  String _label() {
    if (booking.saving) return booking.isEditing ? 'Guardando…' : 'Reservando…';
    if (booking.client == null) return 'Falta el cliente';
    if (booking.personalId == null) return 'Falta el barbero';
    if (booking.serviceIds.isEmpty) return 'Falta el servicio';
    if (booking.time == null) return 'Falta la hora';
    return booking.isEditing ? 'Guardar cambios' : 'Reservar cita';
  }
}

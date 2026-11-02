import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

/// Una cita por avisar: la cita y el enlace de WhatsApp con el mensaje escrito.
class _Reminder {
  const _Reminder(this.appointment, this.whatsappUrl);

  final Appointment appointment;
  final String? whatsappUrl;

  factory _Reminder.fromJson(Map<String, dynamic> json) =>
      _Reminder(Appointment.fromJson(json), json['whatsapp_url'] as String?);
}

/// Recordatorios: las citas próximas sin avisar. No envía nada solo (igual que
/// la web): abre WhatsApp con el mensaje escrito y apunta quién avisó, para que
/// nadie llame dos veces.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  /// Hasta cuántos días por delante: hoy, mañana o la semana.
  int _days = 1;
  List<_Reminder> _items = const [];
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canMark => context.read<AuthController>().me?.can('appointments.edit') ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/reminders', query: {'days': _days});
      if (!mounted) return;
      setState(() => _items = (body['data'] as List? ?? [])
          .map((e) => _Reminder.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Abre WhatsApp y, si se puede, deja la cita marcada como avisada.
  Future<void> _whatsapp(_Reminder r) async {
    final opened = await launchUrl(Uri.parse(r.whatsappUrl!), mode: LaunchMode.externalApplication);

    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
      return;
    }

    if (_canMark && r.appointment.remindedAt == null) await _mark(r, true);
  }

  Future<void> _mark(_Reminder r, bool reminded) async {
    final api = context.read<ApiClient>();

    try {
      final res = reminded
          ? await api.post('/reminders/${r.appointment.id}')
          : await api.delete('/reminders/${r.appointment.id}');
      if (!mounted) return;

      final updated = _Reminder.fromJson(res['data'] as Map<String, dynamic>);
      setState(() => _items = [for (final i in _items) i.appointment.id == updated.appointment.id ? updated : i]);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 0, label: Text('Hoy')),
              ButtonSegment(value: 1, label: Text('Hasta mañana')),
              ButtonSegment(value: 7, label: Text('7 días')),
            ],
            selected: {_days},
            onSelectionChanged: (s) {
              setState(() => _days = s.first);
              _load();
            },
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final pending = _items.where((r) => r.appointment.remindedAt == null).toList();
    final done = _items.where((r) => r.appointment.remindedAt != null).toList();

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: EmptyView(
                icon: Icons.notifications_none,
                title: 'Nada que avisar',
                subtitle: 'No hay citas próximas reservadas o confirmadas.',
              ),
            ),
          if (pending.isNotEmpty) _label('Por avisar (${pending.length})'),
          for (final r in pending) _tile(r),
          if (done.isNotEmpty) _label('Avisadas (${done.length})'),
          for (final r in done) _tile(r),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: BarboraTheme.textMuted,
          ),
        ),
      );

  Widget _tile(_Reminder r) {
    final a = r.appointment;
    final done = a.remindedAt != null;
    final when = DateFormat("EEE d · HH:mm", 'es').format(a.startsAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.client?.fullName ?? 'Cliente',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: done ? BarboraTheme.textMuted : BarboraTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      when[0].toUpperCase() + when.substring(1),
                      if (a.personal != null) a.personal!.fullName,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                  if (a.client?.phone == null || a.client!.phone!.isEmpty)
                    const Text('Sin teléfono', style: TextStyle(fontSize: 12, color: BarboraTheme.copperDark)),
                ],
              ),
            ),
            if (r.whatsappUrl != null)
              IconButton(
                tooltip: 'Avisar por WhatsApp',
                onPressed: () => _whatsapp(r),
                icon: const Icon(Icons.chat_outlined, color: Color(0xFF16A34A)),
              ),
            if (_canMark)
              IconButton(
                tooltip: done ? 'Desmarcar' : 'Marcar como avisada',
                onPressed: () => _mark(r, !done),
                icon: Icon(
                  done ? Icons.check_circle : Icons.check_circle_outline,
                  color: done ? const Color(0xFF16A34A) : BarboraTheme.titanium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

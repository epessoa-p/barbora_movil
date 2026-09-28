import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/sale.dart';
import '../state/agenda_controller.dart';
import '../state/auth_controller.dart';
import '../state/checkout_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/appointment_tile.dart';
import '../widgets/error_view.dart';
import 'checkout_screen.dart';

/// Detalle de una cita y los botones para cerrarla.
///
/// Es la pantalla donde el barbero de verdad hace algo: marcar que atendió, o
/// que el cliente no vino. Por eso las acciones van abajo, al alcance del pulgar.
class AppointmentDetailScreen extends StatefulWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final int appointmentId;

  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  Appointment? _appointment;
  ApiException? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context
          .read<ApiClient>()
          .get('/appointments/${widget.appointmentId}');

      setState(() => _appointment =
          Appointment.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final appointment = _appointment;
    if (appointment == null) return;

    // Se toma el controlador ANTES del diálogo: después de un await el
    // BuildContext puede haber dejado de ser válido.
    final agenda = context.read<AgendaController>();

    String? reason;

    if (status == 'cancelada') {
      reason = await _askCancelReason();
      if (reason == null) return; // se arrepintió
    }

    setState(() => _saving = true);

    // Se pasa por el controlador de la agenda para que la lista de atrás quede
    // al día sin tener que recargarla al volver.
    final error = await agenda.updateStatus(appointment, status, cancelReason: reason);

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: BarboraTheme.copperDark,
        ),
      );
      return;
    }

    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cita marcada como ${_labelFor(status)}.')),
    );
  }

  Future<String?> _askCancelReason() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar la cita'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            hintText: 'Ej: el cliente reprogramó',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: BarboraTheme.copperDark),
            child: const Text('Cancelar cita'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  /// ¿Se puede cobrar esta cita desde aquí?
  ///
  /// Hacen falta las tres cosas: el módulo de ventas en el plan, el permiso, y
  /// que la cita tenga servicios (sin ellos no habría nada que cobrar).
  bool get _canCharge {
    final me = context.read<AuthController>().me;

    return (me?.hasModule('pos') ?? false)
        && (me?.can('sales.create') ?? false)
        && (_appointment?.services.isNotEmpty ?? false);
  }

  /// Arranca el cobro con la cita ya cargada: cliente, barbero y servicios con
  /// el precio que se pactó al reservar. Al confirmar, el servidor marca la
  /// cita como atendida; no hay que hacerlo a mano.
  void _charge() {
    final a = _appointment!;

    context.read<CheckoutController>().startFromAppointment(
          appointmentId: a.id,
          clientId: a.client?.id,
          clientName: a.client?.fullName,
          personalId: a.personal?.id,
          lines: a.services
              .map((s) => CartLine(
                    type: 'servicio',
                    id: s.id,
                    name: s.name,
                    unitPrice: s.price,
                    personalId: a.personal?.id,
                  ))
              .toList(),
        );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
    );
  }

  static String _labelFor(String status) => switch (status) {
        'atendida' => 'atendida',
        'no_show' => 'no se presentó',
        'cancelada' => 'cancelada',
        'confirmada' => 'confirmada',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: BarboraTheme.inkGradient),
        ),
        title: const Text('Detalle de la cita'),
      ),
      body: _buildBody(symbol),
      bottomNavigationBar: _appointment == null || !_appointment!.isEditable
          ? null
          : _Actions(
              saving: _saving,
              status: _appointment!.status,
              onChange: _changeStatus,
              // Cobrar solo tiene sentido con el módulo de ventas y el permiso.
              onCharge: _canCharge ? _charge : null,
            ),
    );
  }

  Widget _buildBody(String symbol) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    final a = _appointment!;
    final color = BarboraTheme.statusColor(a.status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // Bloque de cabecera: la hora grande, que es el dato que se busca.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BarboraTheme.border),
          ),
          child: Column(
            children: [
              StatusPill(label: a.statusLabel, color: color),
              const SizedBox(height: 14),
              Text(
                a.timeRange,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _fullDate(a.startsAt),
                style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13.5),
              ),
              const SizedBox(height: 3),
              Text(
                '${a.durationMinutes} minutos',
                style: const TextStyle(color: BarboraTheme.titanium, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _Section(
          title: 'Cliente',
          icon: Icons.person_outline,
          children: [
            _Row(label: 'Nombre', value: a.client?.fullName ?? '—'),
            if (a.client?.phone != null)
              _Row(label: 'Teléfono', value: a.client!.phone!),
          ],
        ),

        if (a.personal != null) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Atiende',
            icon: Icons.content_cut,
            children: [
              _Row(label: 'Barbero', value: a.personal!.fullName),
              if (a.branch != null) _Row(label: 'Sucursal', value: a.branch!),
            ],
          ),
        ],

        const SizedBox(height: 12),
        _Section(
          title: 'Servicios',
          icon: Icons.design_services_outlined,
          children: [
            if (a.services.isEmpty)
              const _Row(label: '—', value: 'Sin servicios')
            else
              ...a.services.map(
                (s) => _Row(
                  label: s.name,
                  sublabel: '${s.durationMinutes} min',
                  value: '$symbol ${s.price.toStringAsFixed(2)}',
                ),
              ),
            if (a.total != null && a.services.isNotEmpty)
              _Row(
                label: 'Total',
                value: '$symbol ${a.total!.toStringAsFixed(2)}',
                strong: true,
              ),
          ],
        ),

        if (a.notes != null && a.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Notas',
            icon: Icons.sticky_note_2_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(a.notes!, style: const TextStyle(height: 1.4, fontSize: 13.5)),
              ),
            ],
          ),
        ],

        if (!a.isEditable) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BarboraTheme.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BarboraTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 18, color: BarboraTheme.titanium),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Esta cita ya está ${a.statusLabel.toLowerCase()} y no se puede cambiar.',
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _fullDate(DateTime d) {
    final text = DateFormat("EEEE d 'de' MMMM 'de' y", 'es').format(d);
    return text.isEmpty ? '' : text[0].toUpperCase() + text.substring(1);
  }
}

/// Botonera inferior. Solo aparece si la cita todavía se puede cerrar.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.saving,
    required this.status,
    required this.onChange,
    this.onCharge,
  });

  final bool saving;
  final String status;
  final void Function(String) onChange;
  final VoidCallback? onCharge;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 24),
          if (saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: CircularProgressIndicator(color: BarboraTheme.copper),
            )
          else ...[
            // Cobrar es la acción de verdad: al cobrar, el servidor marca la
            // cita como atendida. Por eso va primero y en el color de marca.
            if (onCharge != null) ...[
              FilledButton.icon(
                onPressed: onCharge,
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Cobrar esta cita'),
              ),
              const SizedBox(height: 9),
            ],

            FilledButton.icon(
              onPressed: () => onChange('atendida'),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                onCharge != null ? 'Atendida sin cobrar' : 'Marcar como atendida',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onChange('no_show'),
                    icon: const Icon(Icons.person_off_outlined, size: 18),
                    label: const Text('No vino', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: const BorderSide(color: Color(0xFFFDE68A)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onChange('cancelada'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BarboraTheme.copperDark,
                      side: BorderSide(
                        color: BarboraTheme.copper.withValues(alpha: .35),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (status == 'reservada') ...[
              const SizedBox(height: 9),
              TextButton.icon(
                onPressed: () => onChange('confirmada'),
                icon: const Icon(Icons.task_alt, size: 18),
                label: const Text('Confirmar con el cliente'),
                style: TextButton.styleFrom(foregroundColor: BarboraTheme.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
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
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.sublabel,
    this.strong = false,
  });

  final String label;
  final String value;
  final String? sublabel;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                    color: strong ? BarboraTheme.ink : BarboraTheme.textMuted,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: const TextStyle(fontSize: 11, color: BarboraTheme.titanium),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

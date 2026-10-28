import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/block_options.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// Lo que devuelve el formulario al guardar o eliminar: el mensaje del
/// servidor y si avisa de citas que caen dentro del bloqueo.
typedef BlockResult = ({String message, bool warn});

/// Alta o edición de un bloqueo. Mismas reglas que la web: no cancela las
/// citas que caen dentro, solo avisa de ellas.
class BlockEditScreen extends StatefulWidget {
  const BlockEditScreen({super.key, this.block, required this.options});

  /// Null = alta; con valor = edición.
  final AgendaBlock? block;
  final BlockOptions options;

  bool get isEditing => block != null;

  @override
  State<BlockEditScreen> createState() => _BlockEditScreenState();
}

class _BlockEditScreenState extends State<BlockEditScreen> {
  late final _title = TextEditingController(text: widget.block?.title ?? '');
  late final _notes = TextEditingController(text: widget.block?.notes ?? '');

  late String _reason;
  int? _personalId;
  int? _branchId;
  late bool _allDay;
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  bool _saving = false;
  final _errors = <String, String>{};
  String? _error;

  @override
  void initState() {
    super.initState();

    final b = widget.block;
    final reasons = widget.options.reasons;

    _reason = b?.reason ?? (reasons.isEmpty ? 'otro' : reasons.first.value as String);
    _branchId = b?.branchId;
    _allDay = b?.allDay ?? true;

    if (b != null) {
      _personalId = b.personalId;
    } else {
      // Un barbero que entra aquí suele bloquear lo suyo; si no tiene ficha
      // (recepción, administración) se parte de toda la barbería.
      final own = context.read<AuthController>().me?.personal?.id;
      final staffIds = widget.options.staff.map((s) => s.value);
      _personalId = own != null && staffIds.contains(own) ? own : null;
    }

    final now = DateTime.now();
    final start = b?.startsAt ?? DateTime(now.year, now.month, now.day, 13);
    final end = b?.endsAt ?? DateTime(now.year, now.month, now.day, 14);

    _startDate = DateTime(start.year, start.month, start.day);
    _endDate = DateTime(end.year, end.month, end.day);
    _startTime = TimeOfDay.fromDateTime(start);
    _endTime = TimeOfDay.fromDateTime(end);

    // Uno de todo el día se guarda hasta las 23:59: al pasarlo a horas se
    // ofrece un tramo razonable en vez de ese 23:59.
    if (_allDay) {
      _startTime = const TimeOfDay(hour: 13, minute: 0);
      _endTime = const TimeOfDay(hour: 14, minute: 0);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String _time(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'title': _title.text.trim(),
      'reason': _reason,
      'personal_id': _personalId,
      'branch_id': _branchId,
      'start_date': _date(_startDate),
      'end_date': _date(_endDate),
      'all_day': _allDay,
      if (!_allDay) 'start_time': _time(_startTime),
      if (!_allDay) 'end_time': _time(_endTime),
      'notes': _notes.text.trim(),
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.isEditing
          ? await api.put('/agenda-blocks/${widget.block!.id}', body: body)
          : await api.post('/agenda-blocks', body: body);

      if (!mounted) return;
      Navigator.of(context).pop<BlockResult>((
        message: res['message'] as String? ?? 'Bloqueo guardado.',
        warn: (res['clashes'] as int? ?? 0) > 0,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final field in ['title', 'start_time', 'end_time', 'end_date', 'personal_id']) {
          final msg = e.firstErrorFor(field);
          if (msg != null) _errors[field] = msg;
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar el bloqueo?'),
        content: const Text('Ese periodo vuelve a quedar disponible para reservar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _saving = true);

    try {
      final res = await context.read<ApiClient>().delete('/agenda-blocks/${widget.block!.id}');
      if (!mounted) return;
      Navigator.of(context).pop<BlockResult>((
        message: res['message'] as String? ?? 'Bloqueo eliminado.',
        warn: false,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('es'),
    );

    if (picked == null) return;

    setState(() {
      if (start) {
        _startDate = picked;
        // Que el fin nunca quede antes del inicio.
        if (_endDate.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );

    if (picked == null) return;
    setState(() => start ? _startTime = picked : _endTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = widget.isEditing &&
        (context.read<AuthController>().me?.can('agenda_blocks.delete') ?? false);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.isEditing ? 'Editar bloqueo' : 'Nuevo bloqueo'),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej.: Vacaciones de Tania, Año nuevo, Almuerzo',
              errorText: _errors['title'],
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            key: const Key('block-reason'),
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motivo'),
            items: [
              for (final r in widget.options.reasons)
                DropdownMenuItem(value: r.value as String, child: Text(r.label)),
            ],
            onChanged: (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<int?>(
            key: const Key('block-scope'),
            initialValue: _personalId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'A quién afecta',
              errorText: _errors['personal_id'],
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Toda la barbería')),
              for (final s in widget.options.staff)
                DropdownMenuItem<int?>(value: s.value as int, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => _personalId = v),
          ),

          // Con una sola sucursal no hay nada que elegir.
          if (widget.options.branches.length > 1) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sucursal'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Todas')),
                for (final b in widget.options.branches)
                  DropdownMenuItem<int?>(value: b.value as int, child: Text(b.label)),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ],
          const SizedBox(height: 6),

          SwitchListTile(
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Todo el día'),
            subtitle: Text(_allDay
                ? 'Bloquea los días completos.'
                : 'Bloquea solo el tramo de horas indicado.'),
          ),
          const SizedBox(height: 4),

          _DateTimeRow(
            label: 'Desde',
            date: _startDate,
            time: _allDay ? null : _startTime,
            onDate: () => _pickDate(start: true),
            onTime: () => _pickTime(start: true),
          ),
          const SizedBox(height: 10),
          _DateTimeRow(
            label: 'Hasta',
            date: _endDate,
            time: _allDay ? null : _endTime,
            onDate: () => _pickDate(start: false),
            onTime: () => _pickTime(start: false),
          ),
          for (final field in ['end_date', 'start_time', 'end_time'])
            if (_errors[field] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _errors[field]!,
                  style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12.5),
                ),
              ),
          const SizedBox(height: 14),

          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13)),
          ],

          const SizedBox(height: 10),
          const Text(
            'Las citas que ya estén dentro de este periodo no se cancelan: '
            'se avisa para que puedas reprogramarlas.',
            style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
          ),
          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: Text(_saving
                ? 'Guardando…'
                : (widget.isEditing ? 'Guardar cambios' : 'Crear bloqueo')),
          ),
        ],
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onDate,
    required this.onTime,
  });

  final String label;
  final DateTime date;

  /// Null en los de todo el día: solo se elige la fecha.
  final TimeOfDay? time;
  final VoidCallback onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDate,
            icon: const Icon(Icons.event, size: 18),
            // El año solo si no es el actual, para que quepa en una línea.
            label: Text(DateFormat(
              date.year == DateTime.now().year ? 'EEE d MMM' : 'd MMM yyyy',
              'es',
            ).format(date)),
          ),
        ),
        if (time != null) ...[
          const SizedBox(width: 8),
          // Ancho fijo: el tema da a los botones ancho completo, y dentro de
          // una fila eso es infinito.
          SizedBox(
            width: 108,
            child: OutlinedButton.icon(
              onPressed: onTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(
                '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

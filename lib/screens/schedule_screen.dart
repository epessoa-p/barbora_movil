import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

/// Una franja del horario: un día, de tal hora a tal hora, en una sucursal.
class ScheduleSlot {
  const ScheduleSlot({
    required this.id,
    required this.weekday,
    required this.weekdayLabel,
    required this.start,
    required this.end,
    this.branch,
  });

  final int id;

  /// 1 = lunes … 7 = domingo.
  final int weekday;
  final String weekdayLabel;
  final String start;
  final String end;
  final String? branch;

  factory ScheduleSlot.fromJson(Map<String, dynamic> j) => ScheduleSlot(
        id: j['id'] as int,
        weekday: (j['weekday'] as num).toInt(),
        weekdayLabel: j['weekday_label'] as String? ?? '',
        start: j['start_time'] as String? ?? '',
        end: j['end_time'] as String? ?? '',
        branch: j['branch'] as String?,
      );
}

/// El horario de una persona del personal: la semana con sus franjas, para
/// agregar (varios días de una vez) o quitar. Vale para cualquiera, atienda
/// citas o no (la recepcionista también tiene horario). Datos de
/// `/personal/{id}/schedules`.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.personalId, required this.name});

  final int personalId;
  final String name;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _days = {1: 'Lunes', 2: 'Martes', 3: 'Miércoles', 4: 'Jueves', 5: 'Viernes', 6: 'Sábado', 7: 'Domingo'};

  List<ScheduleSlot> _slots = const [];
  List<({int id, String name})> _branches = const [];
  bool _bookable = true;
  bool _loading = true;
  ApiException? _error;

  String get _base => '/personal/${widget.personalId}/schedules';

  bool get _canEdit => context.read<AuthController>().me?.can('schedules.edit') ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> body) {
    _slots = (body['data'] as List? ?? []).map((e) => ScheduleSlot.fromJson(e as Map<String, dynamic>)).toList();
    _branches = [
      for (final b in (body['branches'] as List? ?? []).cast<Map<String, dynamic>>())
        (id: b['id'] as int, name: b['name'] as String? ?? ''),
    ];
    _bookable = (body['personal'] as Map?)?['bookable'] as bool? ?? true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get(_base);
      if (!mounted) return;
      setState(() => _apply(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SlotSheet(base: _base, branches: _branches),
    );
    if (body == null || !mounted) return;
    setState(() => _apply(body));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body['message'] as String? ?? 'Franja agregada.')));
  }

  Future<void> _remove(ScheduleSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar franja'),
        content: Text('¿Quitar ${s.weekdayLabel} de ${s.start} a ${s.end}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final body = await context.read<ApiClient>().delete('$_base/${s.id}');
      if (!mounted) return;
      setState(() => _apply(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Horario · ${widget.name}',
      floatingActionButton: _canEdit && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _add,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Agregar franja', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: BarboraTheme.copper,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                    children: [
                      if (!_bookable)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'No atiende citas: el horario es solo de su jornada, no abre turnos en la agenda.',
                            style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                          ),
                        ),
                      for (final day in _days.entries) _day(day.key, day.value),
                    ],
                  ),
                ),
    );
  }

  Widget _day(int weekday, String label) {
    final slots = _slots.where((s) => s.weekday == weekday).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: slots.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Libre', style: TextStyle(color: BarboraTheme.textMuted)),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in slots)
                          InputChip(
                            label: Text(
                              _branches.length > 1 && s.branch != null ? '${s.start}–${s.end} · ${s.branch}' : '${s.start}–${s.end}',
                            ),
                            onDeleted: _canEdit ? () => _remove(s) : null,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Agregar una franja: varios días a la vez, entrada y salida, y la sucursal
/// si hay más de una. Devuelve la respuesta de la API (el horario nuevo).
class _SlotSheet extends StatefulWidget {
  const _SlotSheet({required this.base, required this.branches});

  final String base;
  final List<({int id, String name})> branches;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  static const _short = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom'};

  final Set<int> _weekdays = {1, 2, 3, 4, 5};
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  int? _branchId;
  bool _saving = false;
  String? _error;

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);

    try {
      final body = await context.read<ApiClient>().post(widget.base, body: {
        'weekdays': _weekdays.toList()..sort(),
        'start_time': _fmt(_start),
        'end_time': _fmt(_end),
        'branch_id': ?_branchId,
      });
      navigator.pop(body);
    } on ApiException catch (e) {
      setState(() => _error = e.firstErrorFor('start_time') ??
          e.firstErrorFor('end_time') ??
          e.firstErrorFor('weekdays') ??
          e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget time(String label, TimeOfDay t, bool start) => Expanded(
          child: InkWell(
            onTap: () => _pick(start),
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.schedule, size: 18)),
              child: Text(_fmt(t), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Agregar franja', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Elige los días: la misma franja se agrega a todos.',
              style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in _short.entries)
                FilterChip(
                  label: Text(d.value),
                  selected: _weekdays.contains(d.key),
                  onSelected: (v) => setState(() => v ? _weekdays.add(d.key) : _weekdays.remove(d.key)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              time('Entrada', _start, true),
              const SizedBox(width: 12),
              time('Salida', _end, false),
            ],
          ),
          if (widget.branches.length > 1) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sucursal'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Cualquiera')),
                for (final b in widget.branches) DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ],
          AdminFormError(_error),
          const SizedBox(height: 18),
          AdminSaveButton(
            saving: _saving,
            label: 'Agregar',
            onPressed: () {
              if (_weekdays.isEmpty) {
                setState(() => _error = 'Elige al menos un día.');
                return;
              }
              _save();
            },
          ),
        ],
      ),
    );
  }
}

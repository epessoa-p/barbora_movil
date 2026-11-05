import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/upper_case.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/admin.dart';
import '../models/barber.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'schedule_screen.dart';

/// Alta o edición de un barbero. Devuelve el [Barber] guardado, o null si se
/// canceló. La cuenta de acceso (usuario) NO se toca aquí: eso va por la web.
class BarberEditScreen extends StatefulWidget {
  const BarberEditScreen({super.key, this.barber});

  /// Null = alta; con valor = edición.
  final Barber? barber;

  bool get isEditing => barber != null;

  @override
  State<BarberEditScreen> createState() => _BarberEditScreenState();
}

class _BarberEditScreenState extends State<BarberEditScreen> {
  late final _name = TextEditingController(text: widget.barber?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.barber?.phone ?? '');
  late final _specialty = TextEditingController(
    text: widget.barber?.specialty ?? '',
  );

  int? _cargoId;
  late int? _branchId = widget.barber?.branchId;

  /// Sucursales adicionales (además de la base).
  late final Set<int> _extraBranches = {...?widget.barber?.extraBranchIds};
  late bool _bookable = widget.barber?.bookable ?? true;
  late bool _active = widget.barber?.active ?? true;

  List<CargoOption> _cargos = const [];
  List<PickOption> _branches = const [];
  bool _loadingCargos = true;
  ApiException? _loadError;

  bool _saving = false;
  final _errors = <String, String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargoId = widget.barber?.cargoId;
    _loadCargos();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _specialty.dispose();
    super.dispose();
  }

  Future<void> _loadCargos() async {
    setState(() {
      _loadingCargos = true;
      _loadError = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/personal/options');
      if (!mounted) return;
      setState(() {
        _cargos = (body['cargos'] as List? ?? [])
            .map((e) => CargoOption.fromJson(e as Map<String, dynamic>))
            .toList();
        _branches = PickOption.listOf(body['branches']);
        // Con una sola sucursal no hay nada que elegir.
        // La del usuario con sesión; con una sola sucursal, esa.
        _branchId ??= _branches.length == 1
            ? _branches.first.id
            : _branches.map((b) => b.id).where((id) => id == context.read<AuthController>().me?.personal?.branchId).firstOrNull;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loadingCargos = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'full_name': upperName(_name.text),
      'cargo_id': _cargoId,
      'branch_id': _branchId,
      // Solo si hay varias sucursales: con una, no hay adicionales que elegir.
      if (_branches.length > 1) 'extra_branch_ids': _extraBranches.where((id) => id != _branchId).toList(),
      'phone': _phone.text.trim(),
      'specialty': _specialty.text.trim(),
      'bookable': _bookable ? 1 : 0,
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.isEditing
          ? await api.put('/personal/${widget.barber!.id}', body: body)
          : await api.post('/personal', body: body);

      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(Barber.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors
          ..['full_name'] = e.firstErrorFor('full_name') ?? ''
          ..['cargo_id'] = e.firstErrorFor('cargo_id') ?? ''
          ..['branch_id'] = e.firstErrorFor('branch_id') ?? '';
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.isEditing ? 'Editar personal' : 'Nuevo personal'),
        // Su horario (atienda citas o no): una pantalla aparte.
        actions: [
          if (widget.isEditing && (context.read<AuthController>().me?.can('schedules.view') ?? false))
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ScheduleScreen(personalId: widget.barber!.id, name: widget.barber!.fullName)),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.schedule, size: 20),
              label: const Text('Horario'),
            ),
        ],
      ),
      body: _loadingCargos
          ? const Center(
              child: CircularProgressIndicator(color: BarboraTheme.copper),
            )
          : _loadError != null
          ? ErrorView(error: _loadError!, onRetry: _loadCargos)
          : _form(),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseFormatter()],
          decoration: InputDecoration(
            labelText: 'Nombre completo',
            errorText: _errors['full_name']?.isNotEmpty == true
                ? _errors['full_name']
                : null,
          ),
        ),
        const SizedBox(height: 14),

        DropdownButtonFormField<int>(
          initialValue: _cargoId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Cargo',
            errorText: _errors['cargo_id']?.isNotEmpty == true
                ? _errors['cargo_id']
                : null,
          ),
          items: [
            for (final c in _cargos)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _cargoId = v),
        ),
        if (_cargos.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No hay cargos. Créalos primero (en «Cargos», desde la web).',
              style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
            ),
          ),
        const SizedBox(height: 14),

        // Con una sola sucursal no hay nada que elegir: va sola.
        if (_branches.length > 1) ...[
          DropdownButtonFormField<int>(
            initialValue: _branches.any((b) => b.id == _branchId) ? _branchId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Sucursal',
              helperText: 'Donde trabaja: ahí se numeran sus citas y ventas.',
              errorText: _errors['branch_id']?.isNotEmpty == true ? _errors['branch_id'] : null,
            ),
            items: [
              for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
            ],
            onChanged: (v) => setState(() => _branchId = v),
          ),
          const SizedBox(height: 12),
          // Un gerente o administrador de varios locales: en qué otras
          // sucursales trabaja (lo que verá al vender, agendar, abrir caja).
          const Text('Otras sucursales donde trabaja (opcional)',
              style: TextStyle(fontSize: 13, color: BarboraTheme.textMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final b in _branches.where((b) => b.id != _branchId))
                FilterChip(
                  label: Text(b.name),
                  selected: _extraBranches.contains(b.id),
                  selectedColor: BarboraTheme.copper.withValues(alpha: .15),
                  onSelected: (on) => setState(() => on ? _extraBranches.add(b.id) : _extraBranches.remove(b.id)),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _specialty,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Especialidad (opcional)',
            hintText: 'Ej.: degradados, barba, color…',
          ),
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          value: _bookable,
          onChanged: (v) => setState(() => _bookable = v),
          activeThumbColor: BarboraTheme.copper,
          contentPadding: EdgeInsets.zero,
          title: const Text('Atiende citas'),
          subtitle: const Text(
            'Si está activo, aparece al reservar y al asignar servicios.',
          ),
        ),
        SwitchListTile(
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          activeThumbColor: BarboraTheme.copper,
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          subtitle: const Text(
            'Un barbero inactivo deja de aparecer en la barbería.',
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(
              color: BarboraTheme.copperDark,
              fontSize: 13,
            ),
          ),
        ],

        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            _saving
                ? 'Guardando…'
                : (widget.isEditing ? 'Guardar cambios' : 'Crear personal'),
          ),
        ),
      ],
    );
  }
}

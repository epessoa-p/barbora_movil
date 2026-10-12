import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/upper_case.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/barber.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

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
  late bool _bookable = widget.barber?.bookable ?? true;
  late bool _active = widget.barber?.active ?? true;

  List<CargoOption> _cargos = const [];
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
      final body = await context.read<ApiClient>().get('/cargos');
      if (!mounted) return;
      setState(
        () => _cargos = (body['data'] as List? ?? [])
            .map((e) => CargoOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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
          ..['cargo_id'] = e.firstErrorFor('cargo_id') ?? '';
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
        title: Text(widget.isEditing ? 'Editar barbero' : 'Nuevo barbero'),
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
                : (widget.isEditing ? 'Guardar cambios' : 'Crear barbero'),
          ),
        ),
      ],
    );
  }
}

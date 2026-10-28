import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/block_options.dart';
import '../models/service.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// Alta o edición de un servicio: nombre, categoría, precio, duración,
/// descripción y estado.
///
/// Devuelve el [Service] guardado, o null si se canceló. Las reglas son las de
/// la web (nombre único, duración entre 5 min y 10 h); el servidor valida igual.
class ServiceEditScreen extends StatefulWidget {
  const ServiceEditScreen({super.key, this.service});

  /// Null = alta; con valor = edición.
  final Service? service;

  bool get isEditing => service != null;

  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _price = TextEditingController(
    text: widget.service?.price.toStringAsFixed(2) ?? '',
  );
  late final _duration = TextEditingController(
    text: widget.service == null ? '30' : '${widget.service!.durationMinutes}',
  );
  late final _description = TextEditingController(
    text: widget.service?.description ?? '',
  );
  late bool _active = widget.service?.active ?? true;
  late int? _categoryId = widget.service?.categoryId;

  List<Option> _categories = const [];

  bool _saving = false;
  String? _error;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Si no cargan, se puede guardar igual: la categoría es opcional.
  Future<void> _loadCategories() async {
    try {
      final body = await context.read<ApiClient>().get('/service-categories');
      if (!mounted) return;
      setState(() => _categories = (body['data'] as List? ?? [])
          .map((e) => Option((e as Map<String, dynamic>)['id'] as int, e['name'] as String))
          .toList());
    } on ApiException {
      // Sin categorías no se rompe nada: el desplegable queda en «Sin categoría».
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _errors.clear();
    });

    final payload = {
      'name': upperName(_name.text),
      'service_category_id': _categoryId,
      'price': double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0,
      'duration_minutes': int.tryParse(_duration.text.trim()) ?? 0,
      'description': _description.text.trim(),
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final body = widget.isEditing
          ? await api.put('/services/${widget.service!.id}', body: payload)
          : await api.post('/services', body: payload);

      if (!mounted) return;
      Navigator.of(context).pop(Service.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['name', 'price', 'duration_minutes', 'service_category_id']) {
          final msg = e.firstErrorFor(f);
          if (msg != null) _errors[f] = msg;
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    // Si la categoría del servicio ya no está activa, no se puede preseleccionar.
    final categoryValue = _categories.any((c) => c.value == _categoryId) ? _categoryId : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.isEditing ? 'Editar servicio' : 'Nuevo servicio'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre', errorText: _errors['name']),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<int?>(
            key: ValueKey('cat-${_categories.length}'),
            initialValue: categoryValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Categoría',
              errorText: _errors['service_category_id'],
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Sin categoría')),
              for (final c in _categories)
                DropdownMenuItem<int?>(value: c.value as int, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: 'Precio',
                    prefixText: '$symbol ',
                    errorText: _errors['price'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Duración (min)',
                    errorText: _errors['duration_minutes'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            subtitle: const Text('Un servicio inactivo no aparece al reservar ni al cobrar.'),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13)),
          ],

          const SizedBox(height: 20),
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
                : (widget.isEditing ? 'Guardar cambios' : 'Crear servicio')),
          ),
        ],
      ),
    );
  }
}

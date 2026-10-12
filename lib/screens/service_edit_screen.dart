import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/upper_case.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/service.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// Editar un servicio desde el móvil: precio, duración, nombre, estado.
///
/// Devuelve el [Service] actualizado al guardar, o null si se canceló. Las
/// reglas son las de la web; el servidor valida igual.
class ServiceEditScreen extends StatefulWidget {
  const ServiceEditScreen({super.key, required this.service});

  final Service service;

  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  late final _name = TextEditingController(text: widget.service.name);
  late final _price = TextEditingController(
    text: widget.service.price.toStringAsFixed(2),
  );
  late final _duration = TextEditingController(
    text: '${widget.service.durationMinutes}',
  );
  late final _description = TextEditingController(
    text: widget.service.description ?? '',
  );
  late bool _active = widget.service.active;

  bool _saving = false;
  String? _error;
  final _errors = <String, String>{};

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _errors.clear();
    });

    try {
      final body = await context.read<ApiClient>().put(
        '/services/${widget.service.id}',
        body: {
          'name': upperName(_name.text),
          'price': double.tryParse(_price.text.replaceAll(',', '.')) ?? 0,
          'duration_minutes': int.tryParse(_duration.text.trim()) ?? 0,
          'description': _description.text.trim(),
          'active': _active ? 1 : 0,
        },
      );

      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(Service.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors
          ..['name'] = e.firstErrorFor('name') ?? ''
          ..['price'] = e.firstErrorFor('price') ?? ''
          ..['duration_minutes'] = e.firstErrorFor('duration_minutes') ?? '';
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Editar servicio'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(
              labelText: 'Nombre',
              errorText: _errors['name']?.isNotEmpty == true
                  ? _errors['name']
                  : null,
            ),
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Precio',
                    prefixText: '$symbol ',
                    errorText: _errors['price']?.isNotEmpty == true
                        ? _errors['price']
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Duración (min)',
                    errorText: _errors['duration_minutes']?.isNotEmpty == true
                        ? _errors['duration_minutes']
                        : null,
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
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
            ),
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            subtitle: const Text(
              'Un servicio inactivo no aparece al reservar ni al cobrar.',
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
            label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

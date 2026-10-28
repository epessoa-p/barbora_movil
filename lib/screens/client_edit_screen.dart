import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/client.dart';
import '../theme/barbora_theme.dart';

/// Alta o edición de la ficha de un cliente. Devuelve el [Client] guardado, o
/// null si se canceló. Mismas reglas que la web (documento único por barbería,
/// cumpleaños en el pasado…), que valida el servidor.
class ClientEditScreen extends StatefulWidget {
  const ClientEditScreen({super.key, this.client});

  /// Null = alta; con valor = edición.
  final Client? client;

  bool get isEditing => client != null;

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  late final _name = TextEditingController(text: widget.client?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.client?.phone ?? '');
  late final _email = TextEditingController(text: widget.client?.email ?? '');
  late final _document = TextEditingController(text: widget.client?.documentNumber ?? '');
  late final _preferences = TextEditingController(text: widget.client?.preferences ?? '');
  late final _allergies = TextEditingController(text: widget.client?.allergies ?? '');
  late final _notes = TextEditingController(text: widget.client?.notes ?? '');

  late DateTime? _birthDate = widget.client?.birthDate;
  late bool _active = widget.client?.active ?? true;

  bool _saving = false;
  final _errors = <String, String>{};
  String? _error;

  static const _fields = [
    'full_name', 'phone', 'email', 'document_number', 'birth_date',
    'preferences', 'allergies', 'notes',
  ];

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _document, _preferences, _allergies, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now.subtract(const Duration(days: 1)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      locale: const Locale('es'),
    );

    if (picked != null) setState(() => _birthDate = picked);
  }

  /// Vacío se manda como null: así se borra un dato que ya no vale.
  static String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'full_name': upperName(_name.text),
      'phone': _text(_phone),
      'email': _text(_email),
      'document_number': _text(_document),
      'birth_date': _birthDate == null ? null : DateFormat('yyyy-MM-dd').format(_birthDate!),
      'preferences': _text(_preferences),
      'allergies': _text(_allergies),
      'notes': _text(_notes),
      'active': _active,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.isEditing
          ? await api.put('/clients/${widget.client!.id}', body: body)
          : await api.post('/clients', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(Client.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final field in _fields) {
          final msg = e.firstErrorFor(field);
          if (msg != null) _errors[field] = msg;
        }
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
        title: Text(widget.isEditing ? 'Editar cliente' : 'Nuevo cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre completo', errorText: _errors['full_name']),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Teléfono', errorText: _errors['phone']),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Correo', errorText: _errors['email']),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _document,
            decoration: InputDecoration(
              labelText: 'Documento (CI / NIT)',
              errorText: _errors['document_number'],
            ),
          ),
          const SizedBox(height: 14),

          // Cumpleaños: se elige en el calendario y se puede quitar.
          InkWell(
            onTap: _pickBirthDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Cumpleaños',
                errorText: _errors['birth_date'],
                prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                suffixIcon: _birthDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _birthDate = null),
                      ),
              ),
              child: Text(
                _birthDate == null
                    ? 'Sin registrar'
                    : DateFormat("d 'de' MMMM 'de' y", 'es').format(_birthDate!),
                style: TextStyle(color: _birthDate == null ? BarboraTheme.textMuted : null),
              ),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _preferences,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Preferencias',
              hintText: 'Ej.: degradado bajo, máquina 2 a los lados',
              errorText: _errors['preferences'],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _allergies,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Alergias',
              hintText: 'Se muestra destacado en la ficha',
              errorText: _errors['allergies'],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Notas', errorText: _errors['notes']),
          ),

          if (widget.isEditing)
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeThumbColor: BarboraTheme.copper,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              subtitle: const Text('Un cliente inactivo no aparece al reservar ni al cobrar.'),
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
                : (widget.isEditing ? 'Guardar cambios' : 'Crear cliente')),
          ),
        ],
      ),
    );
  }
}

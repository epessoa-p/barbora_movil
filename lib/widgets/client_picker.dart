import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/client.dart';
import '../theme/barbora_theme.dart';
import 'error_view.dart';

/// Hoja para buscar y elegir un cliente, con alta rápida opcional.
///
/// Se comparte entre reservar una cita y cobrar una venta suelta: en los dos
/// sitios se hace lo mismo —buscar por nombre o teléfono, o dar de alta al que
/// llega por primera vez— así que la lógica vive en un solo lugar.
///
/// Devuelve el [Client] elegido, o null si se cerró sin elegir.
class ClientPickerSheet extends StatefulWidget {
  const ClientPickerSheet({super.key, required this.api, this.canCreate = false});

  final ApiClient api;

  /// Si el usuario puede dar de alta clientes (permiso `clients.create`).
  final bool canCreate;

  /// Abre la hoja y espera al cliente elegido.
  static Future<Client?> show(
    BuildContext context, {
    required ApiClient api,
    bool canCreate = false,
  }) {
    return showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: BarboraTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ClientPickerSheet(api: api, canCreate: canCreate),
    );
  }

  @override
  State<ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<ClientPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<Client> _results = const [];
  bool _loading = true;
  ApiException? _error;

  /// Para descartar respuestas de búsquedas que ya no son la última.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(term));
  }

  Future<void> _load(String term) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await widget.api.get('/clients', query: {
        if (term.trim().isNotEmpty) 'q': term.trim(),
        'per_page': 20,
      });

      if (!mounted || request != _request) return;

      setState(() => _results = (body['data'] as List? ?? [])
          .map((e) => Client.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = e);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final client = await showDialog<Client>(
      context: context,
      builder: (_) => _QuickClientDialog(api: widget.api, initialName: _search.text.trim()),
    );

    if (client != null && mounted) Navigator.of(context).pop(client);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BarboraTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nombre, teléfono o documento',
                ),
              ),
            ),
            if (widget.canCreate)
              ListTile(
                onTap: _create,
                leading: const CircleAvatar(
                  backgroundColor: BarboraTheme.copper,
                  child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                ),
                title: Text(
                  _search.text.trim().isEmpty
                      ? 'Cliente nuevo'
                      : 'Crear «${_search.text.trim()}»',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            const Divider(),
            Expanded(child: _list()),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: () => _load(_search.text));
    }

    if (_results.isEmpty) {
      return const EmptyView(
        icon: Icons.person_search_outlined,
        title: 'Sin resultados',
        subtitle: 'Prueba con otro nombre o con el teléfono.',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(indent: 72),
      itemBuilder: (_, i) {
        final c = _results[i];
        return ListTile(
          onTap: () => Navigator.of(context).pop(c),
          leading: CircleAvatar(
            backgroundColor: BarboraTheme.canvas,
            child: Text(
              c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, color: BarboraTheme.ink),
            ),
          ),
          title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: c.phone == null ? null : Text(c.phone!),
        );
      },
    );
  }
}

/// Alta rápida: nombre y teléfono, lo justo para no frenar la atención.
class _QuickClientDialog extends StatefulWidget {
  const _QuickClientDialog({required this.api, required this.initialName});

  final ApiClient api;
  final String initialName;

  @override
  State<_QuickClientDialog> createState() => _QuickClientDialogState();
}

class _QuickClientDialogState extends State<_QuickClientDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  final _phone = TextEditingController();

  bool _saving = false;
  String? _nameError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Escribe el nombre');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
      _error = null;
    });

    try {
      final body = await widget.api.post('/clients', body: {
        'full_name': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      });

      final client = Client.fromJson(body['data'] as Map<String, dynamic>);
      if (mounted) Navigator.of(context).pop(client);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _nameError = e.firstErrorFor('full_name');
        _error = _nameError == null ? (e.firstErrorFor('phone') ?? e.message) : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cliente nuevo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.initialName.isEmpty,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Nombre completo', errorText: _nameError),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Crear'),
        ),
      ],
    );
  }
}

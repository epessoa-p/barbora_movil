import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

/// Proveedores: a quién se le compra o se le paga un gasto, y cuánto se le debe.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<SupplierItem> _suppliers = const [];
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _can(String p) => context.read<AuthController>().me?.can(p) ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/suppliers');
      if (!mounted) return;
      setState(() => _suppliers = (body['data'] as List? ?? []).map((e) => SupplierItem.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([SupplierItem? supplier]) async {
    final saved = await Navigator.of(context).push<SupplierItem>(
      MaterialPageRoute(builder: (_) => SupplierEditScreen(supplier: supplier)),
    );
    if (saved != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    final canEdit = _can('suppliers.edit');

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: BarboraTheme.copper,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                    children: [
                      if (_suppliers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: EmptyView(icon: Icons.local_shipping_outlined, title: 'Sin proveedores'),
                        ),
                      for (final s in _suppliers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminTile(
                            icon: Icons.local_shipping_outlined,
                            title: s.name,
                            dimmed: !s.active,
                            tags: [
                              if (s.debt > 0.004) AdminTag('Debe $symbol ${s.debt.toStringAsFixed(2)}', color: BarboraTheme.copperDark),
                              if (!s.active) const AdminTag('Inactivo'),
                            ],
                            subtitle: [
                              if (s.contactName != null) s.contactName!,
                              if (s.phone != null) s.phone!,
                              '${s.purchasesCount} compras',
                            ].join(' · '),
                            onTap: canEdit ? () => _edit(s) : null,
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: _can('suppliers.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _edit(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo proveedor', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

/// Alta o edición de un proveedor.
class SupplierEditScreen extends StatefulWidget {
  const SupplierEditScreen({super.key, this.supplier});

  final SupplierItem? supplier;

  @override
  State<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends State<SupplierEditScreen> {
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _taxId = TextEditingController(text: widget.supplier?.taxId ?? '');
  late final _contact = TextEditingController(text: widget.supplier?.contactName ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(text: widget.supplier?.address ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  late bool _active = widget.supplier?.active ?? true;
  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _taxId, _contact, _phone, _email, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'name': upperName(_name.text),
      'tax_id': _taxId.text.trim(),
      'contact_name': upperName(_contact.text),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
      if (widget.supplier != null) 'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.supplier == null
          ? await api.post('/suppliers', body: body)
          : await api.put('/suppliers/${widget.supplier!.id}', body: body);
      if (!mounted) return;
      Navigator.of(context).pop(SupplierItem.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in body.keys) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre o razón social', errorText: _errors['name']),
          ),
          const SizedBox(height: 14),
          TextField(controller: _taxId, decoration: const InputDecoration(labelText: 'NIT (opcional)')),
          const SizedBox(height: 14),
          TextField(
            controller: _contact,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: const InputDecoration(labelText: 'Persona de contacto (opcional)'),
          ),
          const SizedBox(height: 14),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Correo (opcional)', errorText: _errors['email']),
          ),
          const SizedBox(height: 14),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección (opcional)')),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas', hintText: 'Qué vende, días de entrega…'),
          ),
          if (widget.supplier != null)
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeThumbColor: BarboraTheme.copper,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
            ),
          AdminFormError(_error),
          const SizedBox(height: 20),
          AdminSaveButton(saving: _saving, label: widget.supplier == null ? 'Registrar proveedor' : 'Guardar cambios', onPressed: _save),
        ],
      ),
    );
  }
}

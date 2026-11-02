import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/admin.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

/// Sucursales: lista (activas e inactivas), alta y edición. El alta respeta
/// el límite del plan; no se borra desde aquí, se da de baja.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  List<BranchItem> _branches = const [];
  bool _canAdd = false;
  ApiException? _error;
  bool _loading = true;

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
      final body = await context.read<ApiClient>().get('/admin/branches');
      if (!mounted) return;
      setState(() {
        _branches = (body['data'] as List? ?? [])
            .map((e) => BranchItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _canAdd = body['can_add'] as bool? ?? false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _can(String permission) => context.read<AuthController>().me?.can(permission) ?? false;

  Future<void> _open({BranchItem? branch}) async {
    final saved = await Navigator.of(context).push<BranchItem>(
      MaterialPageRoute(builder: (_) => BranchEditScreen(branch: branch)),
    );

    if (saved == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${saved.name} guardada.')));
    _load(); // el cupo del plan puede haber cambiado
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _can('branches.create');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Sucursales'),
      ),
      body: _body(),
      floatingActionButton: canCreate && _canAdd && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva sucursal', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final canEdit = _can('branches.edit');

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (_branches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: EmptyView(icon: Icons.store_mall_directory_outlined, title: 'Sin sucursales'),
            ),
          for (final b in _branches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminTile(
                icon: Icons.store_mall_directory_outlined,
                title: b.name,
                dimmed: !b.active,
                tags: [
                  if (b.code != null && b.code!.isNotEmpty) AdminTag(b.code!),
                  if (!b.active) const AdminTag('Inactiva'),
                ],
                subtitle: [
                  if (b.address != null && b.address!.isNotEmpty) b.address!,
                  '${b.personalCount} personal · ${b.cajasCount} ${b.cajasCount == 1 ? 'caja' : 'cajas'}',
                ].join('\n'),
                onTap: canEdit ? () => _open(branch: b) : null,
              ),
            ),
          if (!_canAdd && _can('branches.create'))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Alcanzaste el límite de sucursales de tu plan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o edición de una sucursal. Devuelve la guardada, o null si se canceló.
class BranchEditScreen extends StatefulWidget {
  const BranchEditScreen({super.key, this.branch});

  final BranchItem? branch;

  @override
  State<BranchEditScreen> createState() => _BranchEditScreenState();
}

class _BranchEditScreenState extends State<BranchEditScreen> {
  late final _name = TextEditingController(text: widget.branch?.name ?? '');
  late final _code = TextEditingController(text: widget.branch?.code ?? '');
  late final _address = TextEditingController(text: widget.branch?.address ?? '');
  late final _phone = TextEditingController(text: widget.branch?.phone ?? '');
  late final _email = TextEditingController(text: widget.branch?.email ?? '');
  late final _manager = TextEditingController(text: widget.branch?.managerName ?? '');
  late bool _active = widget.branch?.active ?? true;

  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _code, _address, _phone, _email, _manager]) {
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
      'code': _code.text.trim(),
      'address': _address.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'manager_name': upperName(_manager.text),
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.branch == null
          ? await api.post('/admin/branches', body: body)
          : await api.put('/admin/branches/${widget.branch!.id}', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(BranchItem.fromJson(res['data'] as Map<String, dynamic>));
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
    final editing = widget.branch != null;

    return AdminPage(
      title: editing ? 'Editar sucursal' : 'Nueva sucursal',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre', errorText: _errors['name']),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            decoration: InputDecoration(
              labelText: 'Código (opcional)',
              hintText: 'Vacío: se genera solo (S01, S02…)',
              errorText: _errors['code'],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Dirección', errorText: _errors['address']),
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
            decoration: InputDecoration(labelText: 'Correo', errorText: _errors['email']),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _manager,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Encargado (opcional)', errorText: _errors['manager_name']),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activa'),
            subtitle: const Text('Una sucursal inactiva deja de ofrecerse al asignar personal y cajas.'),
          ),
          AdminFormError(_error),
          const SizedBox(height: 20),
          AdminSaveButton(
            saving: _saving,
            label: editing ? 'Guardar cambios' : 'Crear sucursal',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

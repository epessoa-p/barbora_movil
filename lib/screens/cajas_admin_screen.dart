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

/// Las cajas registradoras (los datos maestros; el turno se opera en «Caja»).
/// Cada caja es de una sucursal, y su responsable trabaja en esa misma.
class CajasAdminScreen extends StatefulWidget {
  const CajasAdminScreen({super.key});

  @override
  State<CajasAdminScreen> createState() => _CajasAdminScreenState();
}

class _CajasAdminScreenState extends State<CajasAdminScreen> {
  List<CajaItem> _cajas = const [];
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
      final body = await context.read<ApiClient>().get('/admin/cajas');
      if (!mounted) return;
      setState(() => _cajas = (body['data'] as List? ?? [])
          .map((e) => CajaItem.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _can(String permission) => context.read<AuthController>().me?.can(permission) ?? false;

  Future<void> _open({CajaItem? caja}) async {
    final saved = await Navigator.of(context).push<CajaItem>(
      MaterialPageRoute(builder: (_) => CajaEditScreen(caja: caja)),
    );

    if (saved == null || !mounted) return;

    setState(() {
      final i = _cajas.indexWhere((c) => c.id == saved.id);
      if (i >= 0) {
        _cajas = [..._cajas]..[i] = saved;
      } else {
        _cajas = [..._cajas, saved]..sort((a, b) => a.name.compareTo(b.name));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${saved.name} guardada.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Cajas'),
      ),
      body: _body(),
      floatingActionButton: _can('cajas.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva caja', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final canEdit = _can('cajas.edit');

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (_cajas.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: EmptyView(icon: Icons.point_of_sale_outlined, title: 'Sin cajas'),
            ),
          for (final c in _cajas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminTile(
                icon: Icons.point_of_sale_outlined,
                title: c.name,
                dimmed: !c.active,
                tags: [
                  if (c.code != null && c.code!.isNotEmpty) AdminTag(c.code!),
                  if (!c.active) const AdminTag('Inactiva'),
                ],
                subtitle: [
                  c.branch ?? 'Sin sucursal',
                  c.personal ?? 'Caja general',
                ].join(' · '),
                onTap: canEdit ? () => _open(caja: c) : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o edición de una caja. Devuelve la guardada, o null si se canceló.
class CajaEditScreen extends StatefulWidget {
  const CajaEditScreen({super.key, this.caja});

  final CajaItem? caja;

  @override
  State<CajaEditScreen> createState() => _CajaEditScreenState();
}

class _CajaEditScreenState extends State<CajaEditScreen> {
  late final _name = TextEditingController(text: widget.caja?.name ?? '');
  late final _code = TextEditingController(text: widget.caja?.code ?? '');
  late final _description = TextEditingController(text: widget.caja?.description ?? '');
  late int? _branchId = widget.caja?.branchId;
  late int? _personalId = widget.caja?.personalId;
  late bool _active = widget.caja?.active ?? true;

  List<PickOption> _branches = const [];
  List<PickOption> _personal = const [];
  bool _loadingOptions = true;
  ApiException? _loadError;

  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/admin/cajas/options');
      if (!mounted) return;
      setState(() {
        _branches = PickOption.listOf(body['branches']);
        _personal = PickOption.listOf(body['personal']);
        // Con una sola sucursal no hay nada que elegir.
        if (_branchId == null && _branches.length == 1) _branchId = _branches.first.id;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  /// El responsable tiene que trabajar en la sucursal de la caja.
  List<PickOption> get _personalOfBranch =>
      _personal.where((p) => p.branchId == null || p.branchId == _branchId).toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'name': upperName(_name.text),
      'code': _code.text.trim(),
      'description': _description.text.trim(),
      'branch_id': _branchId,
      'personal_id': _personalId,
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.caja == null
          ? await api.post('/admin/cajas', body: body)
          : await api.put('/admin/cajas/${widget.caja!.id}', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(CajaItem.fromJson(res['data'] as Map<String, dynamic>));
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
    final editing = widget.caja != null;

    return AdminPage(
      title: editing ? 'Editar caja' : 'Nueva caja',
      child: _loadingOptions
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _loadOptions)
              : _form(editing),
    );
  }

  Widget _form(bool editing) {
    final staff = _personalOfBranch;
    // Si el responsable elegido ya no está entre los de la sucursal, se suelta.
    final personalId = staff.any((p) => p.id == _personalId) ? _personalId : null;

    return ListView(
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
          decoration: InputDecoration(labelText: 'Código (opcional)', errorText: _errors['code']),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _branchId,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Sucursal', errorText: _errors['branch_id']),
          items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
          onChanged: (v) => setState(() => _branchId = v),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int?>(
          key: ValueKey('personal-$_branchId'),
          initialValue: personalId,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Responsable', errorText: _errors['personal_id']),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Ninguno (caja general)')),
            for (final p in staff) DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _personalId = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _description,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Descripción (opcional)', errorText: _errors['description']),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          activeThumbColor: BarboraTheme.copper,
          contentPadding: EdgeInsets.zero,
          title: const Text('Activa'),
          subtitle: const Text('Una caja inactiva no se ofrece al abrir turno.'),
        ),
        AdminFormError(_error),
        const SizedBox(height: 20),
        AdminSaveButton(
          saving: _saving,
          label: editing ? 'Guardar cambios' : 'Crear caja',
          onPressed: () {
            _personalId = personalId;
            _save();
          },
        ),
      ],
    );
  }
}

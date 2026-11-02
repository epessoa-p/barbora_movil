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

Color _hex(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null ? BarboraTheme.titanium : Color(0xFF000000 | value);
}

/// Categorías de servicios: lista (activas e inactivas), alta y edición. Agrupan
/// los servicios en la app, en la web y en el catálogo público.
class ServiceCategoriesScreen extends StatefulWidget {
  const ServiceCategoriesScreen({super.key});

  @override
  State<ServiceCategoriesScreen> createState() => _ServiceCategoriesScreenState();
}

class _ServiceCategoriesScreenState extends State<ServiceCategoriesScreen> {
  List<ServiceCategoryItem> _categories = const [];
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
      final body = await context.read<ApiClient>().get('/service-categories/manage');
      if (!mounted) return;
      setState(() => _categories = (body['data'] as List? ?? [])
          .map((e) => ServiceCategoryItem.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _can(String permission) => context.read<AuthController>().me?.can(permission) ?? false;

  Future<void> _open({ServiceCategoryItem? category}) async {
    final saved = await Navigator.of(context).push<ServiceCategoryItem>(
      MaterialPageRoute(builder: (_) => ServiceCategoryEditScreen(category: category)),
    );

    if (saved == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${saved.name} guardada.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body(),
      floatingActionButton: _can('service_categories.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final canEdit = _can('service_categories.edit');

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (_categories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: EmptyView(
                icon: Icons.category_outlined,
                title: 'Sin categorías',
                subtitle: 'Agrupan tus servicios: cortes, barba, color…',
              ),
            ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: canEdit ? () => _open(category: c) : null,
                  leading: CircleAvatar(radius: 9, backgroundColor: _hex(c.color)),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.active ? BarboraTheme.ink : BarboraTheme.textMuted,
                    ),
                  ),
                  subtitle: Text(
                    [
                      c.servicesCount == 1 ? '1 servicio' : '${c.servicesCount} servicios',
                      if (c.description != null && c.description!.isNotEmpty) c.description!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!c.active) const AdminTag('Inactiva'),
                      if (canEdit) const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o edición de una categoría. Devuelve la guardada, o null.
class ServiceCategoryEditScreen extends StatefulWidget {
  const ServiceCategoryEditScreen({super.key, this.category});

  final ServiceCategoryItem? category;

  @override
  State<ServiceCategoryEditScreen> createState() => _ServiceCategoryEditScreenState();
}

class _ServiceCategoryEditScreenState extends State<ServiceCategoryEditScreen> {
  /// Colores de muestra: los mismos tonos que usa la web para las categorías.
  static const _palette = [
    '#E64A38', '#F59E0B', '#16A34A', '#0D9488', '#0EA5E9',
    '#2563EB', '#7C3AED', '#DB2777', '#6B7280', '#111827',
  ];

  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late final _description = TextEditingController(text: widget.category?.description ?? '');
  late String _color = widget.category?.color.toUpperCase() ?? _palette.first;
  late bool _active = widget.category?.active ?? true;

  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
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
      'description': _description.text.trim(),
      'color': _color,
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.category == null
          ? await api.post('/service-categories', body: body)
          : await api.put('/service-categories/${widget.category!.id}', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(ServiceCategoryItem.fromJson(res['data'] as Map<String, dynamic>));
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
    final editing = widget.category != null;

    return AdminPage(
      title: editing ? 'Editar categoría' : 'Nueva categoría',
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
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Descripción (opcional)', errorText: _errors['description']),
          ),
          const SizedBox(height: 18),
          const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final hex in {..._palette, _color})
                GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: _hex(hex),
                    child: hex == _color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ],
          ),
          if (_errors['color'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_errors['color']!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12.5)),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activa'),
            subtitle: const Text('Una categoría inactiva deja de ofrecerse al crear servicios.'),
          ),
          AdminFormError(_error),
          const SizedBox(height: 20),
          AdminSaveButton(
            saving: _saving,
            label: editing ? 'Guardar cambios' : 'Crear categoría',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

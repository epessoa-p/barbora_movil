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

/// Los tipos de categoría: deciden en qué pestaña de Gastos sale y qué pide.
const _types = <String, String>{
  'general': 'Gasto general',
  'basicos': 'Servicio básico',
  'proveedor': 'Pago a proveedor',
  'personal': 'Pago a personal',
};

const _groupTitles = <String, String>{
  'general': 'Gastos generales',
  'basicos': 'Servicios básicos',
  'proveedor': 'Pagos a proveedores',
  'personal': 'Pagos a personal',
};

/// En qué se gasta, agrupado por tipo: generales (comida, pasajes…),
/// servicios básicos (luz, agua, hosting… mensual o anual), pagos a
/// proveedores y a personal.
class ExpenseCategoriesScreen extends StatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  State<ExpenseCategoriesScreen> createState() => _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState extends State<ExpenseCategoriesScreen> {
  List<ExpenseCategoryItem> _categories = const [];
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
      final body = await context.read<ApiClient>().get('/finance/expense-categories');
      if (!mounted) return;
      setState(() {
        _categories = (body['data'] as List? ?? []).map((e) => ExpenseCategoryItem.fromJson(e as Map<String, dynamic>)).toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([ExpenseCategoryItem? category]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(category: category),
    );
    if (saved == true) _load();
  }

  List<Widget> _section(String group, String title, bool canEdit) {
    final rows = _categories.where((c) => c.type == group).toList();
    if (rows.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: BarboraTheme.textMuted),
        ),
      ),
      for (final c in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminTile(
            icon: switch (c.type) {
              'proveedor' => Icons.local_shipping_outlined,
              'personal' => Icons.badge_outlined,
              'basicos' => Icons.home_work_outlined,
              _ => Icons.label_outline,
            },
            title: c.name,
            dimmed: !c.active,
            tags: [
              if (c.type == 'basicos') AdminTag(c.isAnnual ? 'Anual' : 'Mensual'),
              if (!c.active) const AdminTag('Inactiva'),
            ],
            subtitle: '${c.expensesCount} gastos',
            onTap: canEdit ? () => _edit(c) : null,
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _can('expense_categories.edit');

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
                      for (final g in _groupTitles.entries) ..._section(g.key, g.value, canEdit),
                    ],
                  ),
                ),
      floatingActionButton: _can('expense_categories.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _edit(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({this.category});

  final ExpenseCategoryItem? category;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _type = widget.category?.type ?? 'general';
  late String _frequency = widget.category?.frequency ?? 'mensual';
  late bool _active = widget.category?.active ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);

    try {
      final api = context.read<ApiClient>();
      final body = {
        'name': upperName(_name.text),
        'type': _type,
        if (_type == 'basicos') 'frequency': _frequency,
        'active': _active ? 1 : 0,
      };
      widget.category == null
          ? await api.post('/finance/expense-categories', body: body)
          : await api.put('/finance/expense-categories/${widget.category!.id}', body: body);
      navigator.pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.firstErrorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.category == null ? 'Nueva categoría' : 'Editar categoría',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [for (final t in _types.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          // Un servicio básico se paga cada mes (luz, agua…) o cada año (hosting…).
          if (_type == 'basicos') ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mensual', label: Text('Mensual'), icon: Icon(Icons.calendar_month, size: 18)),
                ButtonSegment(value: 'anual', label: Text('Anual'), icon: Icon(Icons.event_repeat, size: 18)),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _frequency == 'anual'
                  ? 'Queda pagado por un año desde el último pago (ej.: el hosting).'
                  : 'Queda pagado si hubo un pago en el mes (luz, agua, internet…).',
              style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
            ),
          ],
          if (widget.category != null)
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeThumbColor: BarboraTheme.copper,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
            ),
          const SizedBox(height: 16),
          AdminSaveButton(saving: _busy, label: 'Guardar', onPressed: _save),
        ],
      ),
    );
  }
}

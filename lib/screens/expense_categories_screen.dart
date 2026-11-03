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

/// En qué se gasta. «A quién se paga» decide si el gasto pide un proveedor o
/// alguien del personal.
class ExpenseCategoriesScreen extends StatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  State<ExpenseCategoriesScreen> createState() => _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState extends State<ExpenseCategoriesScreen> {
  List<ExpenseCategoryItem> _categories = const [];
  Map<String, String> _payees = const {};
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
        _payees = (body['payees'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v'));
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
      builder: (_) => _CategorySheet(category: category, payees: _payees),
    );
    if (saved == true) _load();
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
                      for (final c in _categories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminTile(
                            icon: switch (c.payee) {
                              'proveedor' => Icons.local_shipping_outlined,
                              'personal' => Icons.badge_outlined,
                              _ => Icons.label_outline,
                            },
                            title: c.name,
                            dimmed: !c.active,
                            tags: [if (!c.active) const AdminTag('Inactiva')],
                            subtitle: [
                              _payees[c.payee] ?? c.payee,
                              if (c.recurring) 'Servicio básico',
                              '${c.expensesCount} gastos',
                            ].join(' · '),
                            onTap: canEdit ? () => _edit(c) : null,
                          ),
                        ),
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
  const _CategorySheet({this.category, required this.payees});

  final ExpenseCategoryItem? category;
  final Map<String, String> payees;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _payee = widget.category?.payee ?? 'ninguno';
  late bool _recurring = widget.category?.recurring ?? false;
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
        'payee': _payee,
        'recurring': _recurring ? 1 : 0,
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
            initialValue: _payee,
            decoration: const InputDecoration(labelText: 'A quién se paga'),
            items: [
              for (final p in (widget.payees.isEmpty ? const {'ninguno': 'Nadie en concreto'} : widget.payees).entries)
                DropdownMenuItem(value: p.key, child: Text(p.value)),
            ],
            onChanged: (v) => setState(() => _payee = v ?? _payee),
          ),
          SwitchListTile(
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Servicio básico'),
            subtitle: const Text('Alquiler, luz, agua… lo que se paga cada mes o cada año.'),
          ),
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

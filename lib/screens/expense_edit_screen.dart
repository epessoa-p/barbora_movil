import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/admin.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';
import '../widgets/payment_source_picker.dart';

/// Registrar un gasto: en qué, a quién (si la categoría lo pide), cuánto y de
/// dónde sale el dinero. Devuelve el [ExpenseItem] guardado.
class ExpenseEditScreen extends StatefulWidget {
  const ExpenseEditScreen({super.key, this.group, this.initialCategoryId, this.initialAmount});

  /// Desde una pestaña (general, proveedor, personal, basicos): solo sus
  /// categorías. A proveedor o personal no se elige categoría: va la habitual.
  final String? group;

  /// Desde el control del mes: el servicio ya elegido y el último importe.
  final int? initialCategoryId;
  final double? initialAmount;

  bool get payeeGroup => group == 'proveedor' || group == 'personal';

  String get title => switch (group) {
        'proveedor' => 'Pago a proveedor',
        'personal' => 'Pago a personal',
        'basicos' => 'Pago de servicio',
        _ => 'Nuevo gasto',
      };

  @override
  State<ExpenseEditScreen> createState() => _ExpenseEditScreenState();
}

class _ExpenseEditScreenState extends State<ExpenseEditScreen> {
  final _description = TextEditingController();
  late final _amount = TextEditingController(text: widget.initialAmount?.toStringAsFixed(2) ?? '');
  final _reference = TextEditingController();
  DateTime _date = DateTime.now();

  List<ExpenseCategoryItem> _categories = const [];
  List<PickOption> _suppliers = const [];
  List<PickOption> _staff = const [];
  PaymentSourceOptions _sources = const PaymentSourceOptions();
  late PaymentSourceSelection _selection;

  late int? _categoryId = widget.initialCategoryId;
  int? _supplierId;
  int? _personalId;

  bool _loading = true;
  ApiException? _loadError;
  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _selection = PaymentSourceSelection(_sources);
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/finance/options', query: {'group': ?widget.group});
      if (!mounted) return;
      setState(() {
        _categories = (body['categories'] as List? ?? [])
            .map((e) => ExpenseCategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        // A proveedor o personal va la habitual; con una sola, ya va elegida.
        final fallback = (body['default_category_id'] as num?)?.toInt();
        if (_categoryId == null || !_categories.any((c) => c.id == _categoryId)) {
          _categoryId = widget.payeeGroup ? (fallback ?? _categories.firstOrNull?.id) : (_categories.length == 1 ? _categories.first.id : null);
        }
        _suppliers = PickOption.listOf(body['suppliers']);
        _staff = PickOption.listOf(body['staff']);
        _sources = PaymentSourceOptions.fromJson(body);
        _selection = PaymentSourceSelection(_sources);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _payee => widget.payeeGroup
      ? widget.group!
      : (_categories.where((c) => c.id == _categoryId).firstOrNull?.payee ?? 'ninguno');

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'group': ?widget.group,
      'expense_category_id': _categoryId,
      if (_payee == 'proveedor') 'supplier_id': _supplierId,
      if (_payee == 'personal') 'personal_id': _personalId,
      'description': _description.text.trim(),
      'amount': double.tryParse(_amount.text.replaceAll(',', '.')),
      'spent_on': apiDate(_date),
      'reference': _reference.text.trim(),
      ..._selection.toJson(),
    };

    try {
      final res = await context.read<ApiClient>().post('/finance/expenses', body: body);
      if (!mounted) return;
      Navigator.of(context).pop(ExpenseItem.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['expense_category_id', 'supplier_id', 'personal_id', 'description', 'amount', 'spent_on', 'source', 'finance_account_id', 'cash_session_id']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : (e.firstErrorFor('error'));
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return AdminPage(
      title: widget.title,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    // A proveedor o personal: primero a quién se le paga.
                    if (_payee == 'proveedor')
                      DropdownButtonFormField<int?>(
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Proveedor', errorText: _errors['supplier_id']),
                        items: [
                          if (!widget.payeeGroup) const DropdownMenuItem<int?>(value: null, child: Text('Sin especificar')),
                          for (final s in _suppliers) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    if (_payee == 'personal')
                      DropdownButtonFormField<int?>(
                        initialValue: _personalId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Personal', errorText: _errors['personal_id']),
                        items: [
                          if (!widget.payeeGroup) const DropdownMenuItem<int?>(value: null, child: Text('Sin especificar')),
                          for (final p in _staff) DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => setState(() => _personalId = v),
                      ),
                    // La categoría: a proveedor o personal solo si hay más de una.
                    if (!widget.payeeGroup || _categories.length > 1) ...[
                      if (_payee != 'ninguno') const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: switch (widget.group) {
                            'basicos' => 'Servicio',
                            'proveedor' || 'personal' => 'Concepto',
                            _ => 'Categoría',
                          },
                          errorText: _errors['expense_category_id'],
                        ),
                        items: [
                          for (final c in _categories)
                            DropdownMenuItem(value: c.id, child: Text(c.isAnnual ? '${c.name} (anual)' : c.name)),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: _description,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: widget.group == 'general' || widget.group == null ? 'Descripción' : 'Descripción (opcional)',
                        hintText: switch (widget.group) {
                          'basicos' => 'Si la dejas vacía: «LUZ · noviembre 2026»',
                          'proveedor' || 'personal' => 'Si la dejas vacía: «Pago a …»',
                          _ => 'Almuerzo del equipo, pasaje a la central…',
                        },
                        errorText: _errors['description'],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: 'Importe', prefixText: '$symbol ', errorText: _errors['amount']),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: InputDecoration(labelText: 'Fecha', errorText: _errors['spent_on']),
                              child: Text(shortDate(_date)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _reference,
                      decoration: const InputDecoration(labelText: 'Referencia (opcional)', hintText: 'Nº de factura o recibo'),
                    ),
                    const SizedBox(height: 22),
                    PaymentSourcePicker(options: _sources, selection: _selection, symbol: symbol, errors: _errors),
                    AdminFormError(_error),
                    const SizedBox(height: 22),
                    AdminSaveButton(saving: _saving, label: 'Registrar gasto', onPressed: _save),
                  ],
                ),
    );
  }
}

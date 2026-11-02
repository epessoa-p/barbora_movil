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
  const ExpenseEditScreen({super.key});

  @override
  State<ExpenseEditScreen> createState() => _ExpenseEditScreenState();
}

class _ExpenseEditScreenState extends State<ExpenseEditScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  DateTime _date = DateTime.now();

  List<ExpenseCategoryItem> _categories = const [];
  List<PickOption> _suppliers = const [];
  List<PickOption> _staff = const [];
  PaymentSourceOptions _sources = const PaymentSourceOptions();
  late PaymentSourceSelection _selection;

  int? _categoryId;
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
      final body = await context.read<ApiClient>().get('/finance/options');
      if (!mounted) return;
      setState(() {
        _categories = (body['categories'] as List? ?? [])
            .map((e) => ExpenseCategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
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

  String get _payee => _categories.where((c) => c.id == _categoryId).firstOrNull?.payee ?? 'ninguno';

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
        for (final f in ['expense_category_id', 'description', 'amount', 'spent_on', 'source', 'finance_account_id', 'cash_session_id']) {
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
      title: 'Nuevo gasto',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Categoría', errorText: _errors['expense_category_id']),
                      items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                    if (_payee == 'proveedor') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int?>(
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Proveedor'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Sin especificar')),
                          for (final s in _suppliers) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    ],
                    if (_payee == 'personal') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int?>(
                        initialValue: _personalId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Personal'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Sin especificar')),
                          for (final p in _staff) DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => setState(() => _personalId = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: _description,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Alquiler de noviembre, almuerzo del equipo…',
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

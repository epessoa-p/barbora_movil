import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';
import 'expense_edit_screen.dart';

/// Gastos: pagos a proveedores y personal, servicios, comida, pasajes… Salen
/// de una cuenta o de la caja abierta. Se anulan, no se borran.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseItem> _expenses = const [];
  double _total = 0;
  ApiException? _error;
  bool _loading = true;

  /// Periodo: este mes por defecto.
  late DateTimeRange _range = _thisMonth();

  static DateTimeRange _thisMonth() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day));
  }

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
      final body = await context.read<ApiClient>().get('/finance/expenses', query: {
        'from': apiDate(_range.start),
        'to': apiDate(_range.end),
      });
      if (!mounted) return;
      setState(() {
        _expenses = (body['data'] as List? ?? []).map((e) => ExpenseItem.fromJson(e as Map<String, dynamic>)).toList();
        _total = (body['total'] as num?)?.toDouble() ?? 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      locale: const Locale('es'),
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<ExpenseItem>(
      MaterialPageRoute(builder: (_) => const ExpenseEditScreen()),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gasto ${saved.number} registrado.')));
    _load();
  }

  Future<void> _open(ExpenseItem e) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseSheet(expense: e, canCancel: e.canCancel && _can('expenses.delete')),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

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
                      Card(
                        child: ListTile(
                          onTap: _pickRange,
                          leading: const Icon(Icons.date_range, color: BarboraTheme.copperDark),
                          title: Text('${shortDate(_range.start)} – ${shortDate(_range.end)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Toca para cambiar el periodo'),
                          trailing: Text('$symbol ${_total.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_expenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: EmptyView(icon: Icons.receipt_long_outlined, title: 'Sin gastos en el periodo'),
                        ),
                      for (final e in _expenses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminTile(
                            icon: e.source == 'cash' ? Icons.point_of_sale_outlined : Icons.account_balance_outlined,
                            title: '$symbol ${e.amount.toStringAsFixed(2)} · ${e.description}',
                            dimmed: e.cancelled,
                            tags: [AdminTag(e.number), if (e.cancelled) const AdminTag('Anulado')],
                            subtitle: [
                              shortDate(e.spentOn),
                              e.category ?? '',
                              if (e.payee != null) e.payee!,
                              e.sourceLabel,
                            ].where((x) => x.isNotEmpty).join(' · '),
                            onTap: () => _open(e),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: _can('expenses.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _new,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo gasto', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

/// El detalle de un gasto, con la opción de anularlo.
class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.expense, required this.canCancel});

  final ExpenseItem expense;
  final bool canCancel;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final res = await context.read<ApiClient>().patch('/finance/expenses/${widget.expense.id}/cancel', body: {
        if (_reason.text.trim().isNotEmpty) 'cancel_reason': _reason.text.trim(),
      });
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Gasto anulado.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final symbol = context.read<AuthController>().company?.symbol ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Gasto ${e.number}', style: const TextStyle(fontSize: 13, color: BarboraTheme.textMuted)),
          const SizedBox(height: 4),
          Text('$symbol ${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text(e.description, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _row('Fecha', shortDate(e.spentOn)),
          _row('Categoría', e.category ?? '—'),
          if (e.payee != null) _row('Pagado a', e.payee!),
          _row('Salió de', e.sourceLabel),
          if (e.reference != null) _row('Referencia', e.reference!),
          if (e.cancelled) _row('Anulado', e.cancelReason ?? 'Sí'),
          if (widget.canCancel) ...[
            const SizedBox(height: 14),
            TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motivo de la anulación (opcional)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              style: OutlinedButton.styleFrom(foregroundColor: BarboraTheme.copperDark),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(e.source == 'cash' ? 'Anular (vuelve a la caja)' : 'Anular (vuelve a la cuenta)'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 96, child: Text(label, style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 13))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );
}

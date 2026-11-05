import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';
import 'expense_categories_screen.dart';
import 'expense_edit_screen.dart';
import 'settle_commission_sheet.dart';

/// Gastos: pagos a proveedores y personal, servicios, comida, pasajes… Salen
/// de una cuenta o de la caja abierta. Se anulan, no se borran.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.group});

  /// La pestaña: «general», «proveedor», «personal» o «basicos» (null: todos).
  final String? group;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseItem> _expenses = const [];

  /// Servicios básicos: el control del mes (pagados y pendientes) y qué mes.
  BasicServicesMonth? _basics;
  String? _month;

  /// Personal: lo que se debe en comisiones (de cualquier fecha), para pagarlo.
  List<PendingCommission>? _owed;
  double _owedTotal = 0;
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

  /// En Personal, si el plan tiene comisiones y el usuario puede verlas.
  bool get _showsCommissions =>
      widget.group == 'personal' &&
      (context.read<AuthController>().me?.hasModule('comisiones') ?? false) &&
      _can('commissions.view');

  /// Crear un servicio básico (mensual o anual) y que aparezca en el control del mes.
  Future<void> _newService() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ExpenseCategorySheet(initialType: 'basicos'),
    );
    if (saved == true) _load();
  }

  Future<void> _settle(PendingCommission p) async {
    final symbol = context.read<AuthController>().company?.symbol ?? '';
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettleCommissionSheet(pending: p, symbol: symbol),
    );
    if (paid == true) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = context.read<ApiClient>();

    try {
      final body = await api.get('/finance/expenses', query: {
        'from': apiDate(_range.start),
        'to': apiDate(_range.end),
        'group': ?widget.group,
      });
      // En Servicios básicos, además, cuáles se pagaron este mes y cuáles faltan.
      final basics = widget.group == 'basicos'
          ? await api.get('/finance/basics', query: {'month': ?_month})
          : null;
      final owed = _showsCommissions ? await api.get('/commissions/pending') : null;
      if (!mounted) return;
      setState(() {
        if (basics != null) _basics = BasicServicesMonth.fromJson(basics);
        if (owed != null) {
          _owed = (owed['data'] as List? ?? []).map((e) => PendingCommission.fromJson(e as Map<String, dynamic>)).toList();
          _owedTotal = ((owed['summary'] as Map?)?['total'] as num?)?.toDouble() ?? 0;
        }
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

  Future<void> _new({int? categoryId, double? amount}) async {
    final saved = await Navigator.of(context).push<ExpenseItem>(
      MaterialPageRoute(
        builder: (_) => ExpenseEditScreen(group: widget.group, initialCategoryId: categoryId, initialAmount: amount),
      ),
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
                      if (_owed case final owed?) ...[
                        _OwedCard(
                          owed: owed,
                          total: _owedTotal,
                          symbol: symbol,
                          canPay: _can('commissions.create'),
                          onPay: _settle,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_basics case final basics?) ...[
                        _BasicsCard(
                          month: basics,
                          symbol: symbol,
                          canCreate: _can('expenses.create'),
                          onMonth: (m) {
                            setState(() => _month = m);
                            _load();
                          },
                          onPay: (s) => _new(categoryId: s.id, amount: s.lastAmount),
                          onAddService: _can('expense_categories.create') ? _newService : null,
                        ),
                        const SizedBox(height: 10),
                      ],
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
              label: Text(
                switch (widget.group) {
                  'proveedor' => 'Pago a proveedor',
                  'personal' => 'Pago a personal',
                  'basicos' => 'Pago de servicio',
                  _ => 'Nuevo gasto',
                },
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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

/// Servicios básicos del mes: cuáles se pagaron y cuáles faltan. Tocar uno
/// pendiente abre el alta con el servicio y el último importe ya puestos.
class _BasicsCard extends StatelessWidget {
  const _BasicsCard({
    required this.month,
    required this.symbol,
    required this.canCreate,
    required this.onMonth,
    required this.onPay,
    this.onAddService,
  });

  final BasicServicesMonth month;
  final String symbol;
  final bool canCreate;
  final ValueChanged<String> onMonth;
  final ValueChanged<BasicServiceStatus> onPay;

  /// Crear un servicio básico (luz, hosting…); null sin permiso.
  final VoidCallback? onAddService;

  static const _green = Color(0xFF16A34A);
  static const _orange = Color(0xFFEA580C);

  @override
  Widget build(BuildContext context) {
    String money(double v) => '$symbol ${v.toStringAsFixed(2)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: month.previous == null ? null : () => onMonth(month.previous!),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(month.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        '${month.paidCount} pagados · ${month.pendingCount} pendientes · ${money(month.totalPaid)}',
                        style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: month.next == null ? null : () => onMonth(month.next!),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (month.services.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Todavía no hay servicios básicos: agrega la luz, el agua, el hosting… con «Nuevo servicio».',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                ),
              ),
            for (final s in month.services)
              ListTile(
                dense: true,
                onTap: !s.paid && canCreate ? () => onPay(s) : null,
                leading: Icon(
                  s.paid ? Icons.check_circle : Icons.schedule,
                  color: s.paid ? _green : _orange,
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (s.annual) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: BarboraTheme.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Anual', style: TextStyle(fontSize: 10.5, color: BarboraTheme.textMuted)),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  s.paid
                      ? [
                          'Pagado ${money(s.amount)}',
                          if (s.nextDueOn != null) 'vuelve el ${shortDate(s.nextDueOn!)}',
                        ].join(' · ')
                      : ['Pendiente', if (s.lastAmount != null) 'último ${money(s.lastAmount!)}'].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: !s.paid && canCreate
                    ? const Text('Registrar', style: TextStyle(color: BarboraTheme.copper, fontWeight: FontWeight.w700))
                    : null,
              ),
            // Un servicio nuevo (el hosting, el gas…), sin ir a Finanzas › Categorías.
            if (onAddService != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAddService,
                  style: TextButton.styleFrom(foregroundColor: BarboraTheme.copper),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo servicio'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Comisiones por pagar»: lo que se le debe a cada persona, de cualquier
/// fecha. «Pagar» abre la liquidación.
class _OwedCard extends StatelessWidget {
  const _OwedCard({
    required this.owed,
    required this.total,
    required this.symbol,
    required this.canPay,
    required this.onPay,
  });

  final List<PendingCommission> owed;
  final double total;
  final String symbol;
  final bool canPay;
  final ValueChanged<PendingCommission> onPay;

  static const _amber = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    String money(double v) => '$symbol ${v.toStringAsFixed(2)}';
    final count = owed.fold<int>(0, (n, p) => n + p.count);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: owed.isEmpty ? BarboraTheme.border : _amber.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top, color: _amber, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Comisiones por pagar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                Text(money(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2, bottom: 6),
              child: Text(
                owed.isEmpty
                    ? 'Nada pendiente: todas las comisiones están pagadas.'
                    : '$count ${count == 1 ? 'comisión' : 'comisiones'} sin pagar, de cualquier fecha.',
                style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
              ),
            ),
            for (final p in owed)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 6, 0, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${p.count} ${p.count == 1 ? 'comisión' : 'comisiones'} · desde el ${shortDate(p.since)}',
                            style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(money(p.total), style: const TextStyle(fontWeight: FontWeight.w700, color: _amber)),
                    if (canPay) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => onPay(p),
                        style: FilledButton.styleFrom(
                          backgroundColor: _amber,
                          // El tema estira los botones a todo el ancho: aquí va compacto.
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Pagar'),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

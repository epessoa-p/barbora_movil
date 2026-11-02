import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';
import '../widgets/payment_source_picker.dart';
import 'purchases_screen.dart';

/// Una compra: lo comprado, sus pagos, pagar la deuda y anular.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseItem? _purchase;
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
      final body = await context.read<ApiClient>().get('/purchases/${widget.purchaseId}');
      if (!mounted) return;
      setState(() => _purchase = PurchaseItem.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaySheet(purchase: _purchase!),
    );
    if (done == true) _load();
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Anular la compra?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('La mercadería sale del almacén y cada pago vuelve a su cuenta o a la caja.'),
            const SizedBox(height: 10),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final res = await context.read<ApiClient>().patch('/purchases/${widget.purchaseId}/cancel', body: {
        if (reason.text.trim().isNotEmpty) 'cancel_reason': reason.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Compra anulada.')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.firstErrorFor('error') ?? e.firstErrorFor('quantity') ?? e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    String money(double v) => '$symbol ${v.toStringAsFixed(2)}';
    final p = _purchase;

    return AdminPage(
      title: p == null ? 'Compra' : 'Compra ${p.number}',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(p!.supplier ?? 'Sin proveedor', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                AdminTag(p.statusLabel, color: purchaseStatusColor(p.status)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text([
                              shortDate(p.purchasedOn),
                              if (p.warehouse != null) p.warehouse!,
                              if (p.invoiceNumber != null) 'Factura ${p.invoiceNumber}',
                            ].join(' · '), style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5)),
                            if (p.isCancelled && p.cancelReason != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Anulada: ${p.cancelReason}', style: const TextStyle(color: BarboraTheme.copperDark)),
                              ),
                            const Divider(height: 24),
                            for (final l in p.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(child: Text('${l.product}\n${_qty(l.quantity)} × ${money(l.unitCost)}', style: const TextStyle(fontSize: 13))),
                                    Text(money(l.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            const Divider(height: 20),
                            if (p.discount > 0) _row('Descuento', '−${money(p.discount)}'),
                            _row('Total', money(p.total), strong: true),
                            _row('Pagado', money(p.paid)),
                            _row('Se debe', money(p.balance), strong: true, color: p.balance > 0 ? BarboraTheme.copperDark : null),
                            if (p.dueOn != null && p.balance > 0) _row('Vence', shortDate(p.dueOn!)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('PAGOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: BarboraTheme.textMuted)),
                    const SizedBox(height: 6),
                    if (p.payments.isEmpty)
                      const Text('Sin pagos: la compra está a crédito.', style: TextStyle(color: BarboraTheme.textMuted)),
                    for (final pay in p.payments)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          title: Text(money(pay.amount), style: TextStyle(fontWeight: FontWeight.w700, decoration: pay.cancelled ? TextDecoration.lineThrough : null)),
                          subtitle: Text([shortDate(pay.paidOn), pay.sourceLabel, if (pay.cancelled) 'Devuelto'].join(' · ')),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (!p.isCancelled && p.balance > 0 && _can('purchases.edit'))
                      FilledButton.icon(onPressed: _pay, icon: const Icon(Icons.payments_outlined), label: const Text('Registrar un pago')),
                    if (!p.isCancelled && _can('purchases.delete')) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _cancel,
                        style: OutlinedButton.styleFrom(foregroundColor: BarboraTheme.copperDark),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Anular compra'),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _row(String label, String value, {bool strong = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: strong ? BarboraTheme.ink : BarboraTheme.textMuted, fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
            const Spacer(),
            Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, color: color)),
          ],
        ),
      );

  static String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

/// Pagar (parte de) la deuda: cuánto y de dónde sale.
class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.purchase});

  final PurchaseItem purchase;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final _amount = TextEditingController(text: widget.purchase.balance.toStringAsFixed(2));
  PaymentSourceOptions _sources = const PaymentSourceOptions();
  late PaymentSourceSelection _selection = PaymentSourceSelection(_sources);
  bool _loading = true;
  bool _busy = false;
  final _errors = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final body = await context.read<ApiClient>().get('/purchases/options');
      if (!mounted) return;
      setState(() {
        _sources = PaymentSourceOptions.fromJson(body);
        _selection = PaymentSourceSelection(_sources);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors['error'] = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _errors.clear();
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final res = await context.read<ApiClient>().post('/purchases/${widget.purchase.id}/payments', body: {
        'amount': double.tryParse(_amount.text.replaceAll(',', '.')),
        'paid_on': apiDate(DateTime.now()),
        ..._selection.toJson(),
      });
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Pago registrado.')));
    } on ApiException catch (e) {
      setState(() {
        for (final f in ['amount', 'source', 'finance_account_id', 'cash_session_id']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _errors['error'] = e.errors.isEmpty ? e.message : e.firstErrorFor('error');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<AuthController>().company?.symbol ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: BarboraTheme.copper)))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pagar ${widget.purchase.number}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Importe',
                    prefixText: '$symbol ',
                    helperText: 'Se deben $symbol ${widget.purchase.balance.toStringAsFixed(2)}',
                    errorText: _errors['amount'],
                  ),
                ),
                const SizedBox(height: 16),
                PaymentSourcePicker(options: _sources, selection: _selection, symbol: symbol, errors: _errors),
                AdminFormError(_errors['error']),
                const SizedBox(height: 16),
                AdminSaveButton(saving: _busy, label: 'Registrar pago', onPressed: _pay),
              ],
            ),
    );
  }
}

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

class _Line {
  _Line(this.product, {this.quantity = 1}) : cost = product.cost;

  final PurchasableProduct product;
  double quantity;
  double cost;

  double get total => quantity * cost;
}

/// Registrar una compra: proveedor, almacén, productos y cuánto se paga ahora
/// (todo, una parte o nada: a crédito). Devuelve la [PurchaseItem] guardada.
class PurchaseNewScreen extends StatefulWidget {
  const PurchaseNewScreen({super.key});

  @override
  State<PurchaseNewScreen> createState() => _PurchaseNewScreenState();
}

class _PurchaseNewScreenState extends State<PurchaseNewScreen> {
  List<PickOption> _suppliers = const [];
  List<PickOption> _warehouses = const [];
  List<PurchasableProduct> _products = const [];
  PaymentSourceOptions _sources = const PaymentSourceOptions();
  late PaymentSourceSelection _selection = PaymentSourceSelection(_sources);

  int? _supplierId;
  int? _warehouseId;
  final _lines = <_Line>[];
  final _invoice = TextEditingController();
  final _discount = TextEditingController();
  final _partial = TextEditingController();

  /// «all», «part» o «none» (a crédito).
  String _payMode = 'all';

  bool _loading = true;
  ApiException? _loadError;
  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invoice.dispose();
    _discount.dispose();
    _partial.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/purchases/options');
      if (!mounted) return;
      setState(() {
        _suppliers = PickOption.listOf(body['suppliers']);
        _warehouses = PickOption.listOf(body['warehouses']);
        _warehouseId = body['default_warehouse_id'] as int?;
        _products = (body['products'] as List? ?? []).map((e) => PurchasableProduct.fromJson(e as Map<String, dynamic>)).toList();
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

  double get _subtotal => _lines.fold(0, (s, l) => s + l.total);
  double get _total => (_subtotal - (double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0)).clamp(0, double.infinity);

  double get _payNow => switch (_payMode) {
        'all' => _total,
        'part' => (double.tryParse(_partial.text.replaceAll(',', '.')) ?? 0).clamp(0, _total),
        _ => 0,
      };

  Future<void> _addLine() async {
    final line = await showModalBottomSheet<_Line>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineSheet(products: _products),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final now = DateTime.now();
    final body = {
      'supplier_id': _supplierId,
      'warehouse_id': _warehouseId,
      'invoice_number': _invoice.text.trim(),
      'purchased_on': apiDate(now),
      'discount': double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0,
      'items': [
        for (final l in _lines) {'product_id': l.product.id, 'quantity': l.quantity, 'unit_cost': l.cost},
      ],
      'pay_amount': double.parse(_payNow.toStringAsFixed(2)),
      if (_payNow > 0) ..._selection.toJson(),
    };

    try {
      final res = await context.read<ApiClient>().post('/purchases', body: body);
      if (!mounted) return;
      Navigator.of(context).pop(PurchaseItem.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['warehouse_id', 'items', 'discount', 'pay_amount', 'source', 'finance_account_id', 'cash_session_id']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : (_errors['items'] ?? e.firstErrorFor('error'));
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    String money(double v) => '$symbol ${v.toStringAsFixed(2)}';

    return AdminPage(
      title: 'Nueva compra',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    DropdownButtonFormField<int?>(
                      initialValue: _supplierId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Proveedor'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Sin proveedor')),
                        for (final s in _suppliers) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _warehouseId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Entra al almacén', errorText: _errors['warehouse_id']),
                      items: [for (final w in _warehouses) DropdownMenuItem(value: w.id, child: Text(w.name))],
                      onChanged: (v) => setState(() => _warehouseId = v),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: _invoice, decoration: const InputDecoration(labelText: 'Nº de factura (opcional)')),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text('PRODUCTOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: BarboraTheme.textMuted)),
                        const Spacer(),
                        TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 18), label: const Text('Añadir')),
                      ],
                    ),
                    if (_lines.isEmpty)
                      const Text('Añade los productos que entran al almacén.', style: TextStyle(color: BarboraTheme.textMuted, fontSize: 13)),
                    for (final l in _lines)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${_qty(l.quantity)} × ${money(l.cost)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(money(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _lines.remove(l)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _discount,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Descuento (opcional)', prefixText: '$symbol ', errorText: _errors['discount']),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const Spacer(),
                        Text(money(_total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('¿Cuánto pagas ahora?', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Todo')),
                        ButtonSegment(value: 'part', label: Text('Una parte')),
                        ButtonSegment(value: 'none', label: Text('A crédito')),
                      ],
                      selected: {_payMode},
                      onSelectionChanged: (v) => setState(() => _payMode = v.first),
                    ),
                    if (_payMode == 'part') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _partial,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Pagas ahora', prefixText: '$symbol ', errorText: _errors['pay_amount']),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _total - _payNow > 0.004 ? 'Queda como deuda con el proveedor: ${money(_total - _payNow)}.' : 'Se paga completa.',
                      style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                    ),
                    if (_payNow > 0) ...[
                      const SizedBox(height: 18),
                      PaymentSourcePicker(options: _sources, selection: _selection, symbol: symbol, errors: _errors),
                    ],
                    AdminFormError(_error),
                    const SizedBox(height: 22),
                    AdminSaveButton(saving: _saving, label: 'Registrar compra', onPressed: _save),
                  ],
                ),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

/// Elegir un producto, cuántos y a qué costo.
class _LineSheet extends StatefulWidget {
  const _LineSheet({required this.products});

  final List<PurchasableProduct> products;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  PurchasableProduct? _product;
  final _qty = TextEditingController(text: '1');
  final _cost = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<AuthController>().company?.symbol ?? '';
    final qty = double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0;
    final cost = double.tryParse(_cost.text.replaceAll(',', '.')) ?? -1;
    final valid = _product != null && qty > 0 && cost >= 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Añadir producto', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          DropdownButtonFormField<PurchasableProduct>(
            initialValue: _product,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Producto'),
            items: [
              for (final p in widget.products)
                DropdownMenuItem(value: p, child: Text(p.trackStock ? p.name : '${p.name} (sin control de stock)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (p) => setState(() {
              _product = p;
              // Se propone su último costo.
              if (p != null) _cost.text = p.cost.toStringAsFixed(2);
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cost,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Costo unitario', prefixText: '$symbol '),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid ? () => Navigator.of(context).pop(_Line(_product!, quantity: qty)..cost = cost) : null,
            child: const Text('Añadir a la compra'),
          ),
        ],
      ),
    );
  }
}

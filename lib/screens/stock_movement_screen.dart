import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/block_options.dart';
import '../models/inventory.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// Registrar una entrada, salida o ajuste (recuento). Devuelve el mensaje del
/// servidor («Entrada registrada: … queda en 15 unidades…»), o null si se
/// canceló. Las reglas (no sacar más de lo que hay, etc.) las pone el servidor.
class StockMovementScreen extends StatefulWidget {
  const StockMovementScreen({
    super.key,
    required this.product,
    required this.type,
    required this.options,
  });

  final InventoryProduct product;

  /// `entrada`, `salida` o `ajuste`.
  final String type;
  final InventoryOptions options;

  @override
  State<StockMovementScreen> createState() => _StockMovementScreenState();
}

class _StockMovementScreenState extends State<StockMovementScreen> {
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  int? _warehouseId;
  String? _reason;

  bool _saving = false;
  final _errors = <String, String>{};
  String? _error;

  /// Motivos que tienen sentido para cada tipo. El ajuste no lleva: es siempre
  /// un recuento físico.
  static const _reasonsByType = {
    'entrada': ['compra', 'devolucion', 'traslado', 'otro'],
    'salida': ['consumo', 'venta', 'merma', 'traslado', 'otro'],
  };

  bool get _isAdjust => widget.type == 'ajuste';
  bool get _isEntry => widget.type == 'entrada';

  List<Option> get _reasons {
    final allowed = _reasonsByType[widget.type] ?? const [];
    return widget.options.reasons.where((r) => allowed.contains(r.value)).toList();
  }

  @override
  void initState() {
    super.initState();
    final warehouses = widget.options.warehouses;
    _warehouseId = warehouses.isEmpty ? null : warehouses.first.value as int;
    final reasons = _reasons;
    _reason = reasons.isEmpty ? null : reasons.first.value as String;
  }

  @override
  void dispose() {
    for (final c in [_quantity, _cost, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Lo que hay ahora en el almacén elegido, para orientar la cantidad.
  String get _currentLabel {
    final line = widget.product.stocks.where((s) => s.warehouseId == _warehouseId);
    final qty = line.isEmpty ? 0.0 : line.first.quantity;
    return '${trimNumber(qty)} ${widget.product.unitLabel.toLowerCase()}';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    double? number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

    final body = {
      'type': widget.type,
      'product_id': widget.product.id,
      'warehouse_id': _warehouseId,
      'quantity': number(_quantity),
      if (!_isAdjust) 'reason': _reason,
      if (_isEntry && number(_cost) != null) 'unit_cost': number(_cost),
      if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    };

    try {
      final res = await context.read<ApiClient>().post('/inventory/movements', body: body);
      if (!mounted) return;
      Navigator.of(context).pop(res['message'] as String? ?? 'Movimiento registrado.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['quantity', 'warehouse_id', 'unit_cost', 'product_id']) {
          final msg = e.firstErrorFor(f);
          if (msg != null) _errors[f] = msg;
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    final title = switch (widget.type) {
      'entrada' => 'Registrar entrada',
      'salida' => 'Registrar salida',
      _ => 'Ajuste por recuento',
    };
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Text(widget.product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),

          // Con un solo almacén no hay nada que elegir.
          if (widget.options.warehouses.length > 1) ...[
            DropdownButtonFormField<int>(
              initialValue: _warehouseId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Almacén', errorText: _errors['warehouse_id']),
              items: [
                for (final w in widget.options.warehouses)
                  DropdownMenuItem(value: w.value as int, child: Text(w.label)),
              ],
              onChanged: (v) => setState(() => _warehouseId = v),
            ),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _quantity,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimals,
            decoration: InputDecoration(
              labelText: _isAdjust ? 'Cantidad contada' : 'Cantidad',
              suffixText: widget.product.unitLabel.toLowerCase(),
              helperText: _isAdjust
                  ? 'Lo que hay físicamente ahora (hoy figura $_currentLabel).'
                  : 'Hay $_currentLabel en este almacén.',
              errorText: _errors['quantity'],
            ),
          ),
          const SizedBox(height: 14),

          if (!_isAdjust && _reasons.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                for (final r in _reasons)
                  DropdownMenuItem(value: r.value as String, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 14),
          ],

          if (_isEntry) ...[
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimals,
              decoration: InputDecoration(
                labelText: 'Costo unitario (opcional)',
                prefixText: '$symbol ',
                errorText: _errors['unit_cost'],
              ),
            ),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _reference,
            decoration: InputDecoration(
              labelText: 'Referencia (opcional)',
              hintText: _isEntry ? 'Ej.: factura del proveedor' : null,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Guardando…' : 'Registrar'),
          ),
        ],
      ),
    );
  }
}

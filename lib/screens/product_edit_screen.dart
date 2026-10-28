import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/inventory.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';

/// Alta o edición de un producto. Devuelve el [InventoryProduct] guardado, o
/// null si se canceló. Las existencias NO se tocan aquí: van por movimientos
/// (entrada, salida, ajuste) desde la ficha, para que quede su historial.
class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({super.key, this.product, required this.options});

  /// Null = alta; con valor = edición.
  final InventoryProduct? product;
  final InventoryOptions options;

  bool get isEditing => product != null;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _cost = TextEditingController(text: _money(widget.product?.costPrice));
  late final _price = TextEditingController(text: _money(widget.product?.salePrice));
  late final _min = TextEditingController(
    text: widget.product == null ? '' : trimNumber(widget.product!.minStock),
  );

  late int? _categoryId = widget.product?.categoryId;
  late String _unit = widget.product?.unit ??
      (widget.options.units.isEmpty ? 'unidad' : widget.options.units.first.value as String);
  late bool _sellable = widget.product?.isSellable ?? true;
  late bool _track = widget.product?.trackStock ?? true;
  late bool _active = widget.product?.active ?? true;

  bool _saving = false;
  final _errors = <String, String>{};
  String? _error;

  static String _money(double? v) => v == null ? '' : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_name, _sku, _cost, _price, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'name': upperName(_name.text),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'product_category_id': _categoryId,
      'unit': _unit,
      'cost_price': _number(_cost),
      'sale_price': _number(_price),
      'min_stock': _number(_min) ?? 0,
      'is_sellable': _sellable,
      'track_stock': _track,
      'active': _active,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.isEditing
          ? await api.put('/inventory/products/${widget.product!.id}', body: body)
          : await api.post('/inventory/products', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(InventoryProduct.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['name', 'sku', 'cost_price', 'sale_price', 'min_stock', 'unit']) {
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
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.isEditing ? 'Editar producto' : 'Nuevo producto'),
      ),
      body: ListView(
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
            controller: _sku,
            decoration: InputDecoration(
              labelText: 'Código / SKU (opcional)',
              errorText: _errors['sku'],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Sin categoría')),
              for (final c in widget.options.categories)
                DropdownMenuItem<int?>(value: c.value as int, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Unidad', errorText: _errors['unit']),
            items: [
              for (final u in widget.options.units)
                DropdownMenuItem(value: u.value as String, child: Text(u.label)),
            ],
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimals,
                  decoration: InputDecoration(
                    labelText: 'Costo',
                    prefixText: '$symbol ',
                    errorText: _errors['cost_price'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimals,
                  decoration: InputDecoration(
                    labelText: 'Precio de venta',
                    prefixText: '$symbol ',
                    errorText: _errors['sale_price'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimals,
            decoration: InputDecoration(
              labelText: 'Stock mínimo',
              helperText: 'Al llegar a esta cantidad se avisa para reponer.',
              errorText: _errors['min_stock'],
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            value: _sellable,
            onChanged: (v) => setState(() => _sellable = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Se vende'),
            subtitle: const Text('Si no, es un insumo: no aparece al cobrar.'),
          ),
          SwitchListTile(
            value: _track,
            onChanged: (v) => setState(() => _track = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Controlar existencias'),
            subtitle: const Text('Lleva la cuenta de entradas y salidas.'),
          ),
          if (widget.isEditing)
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeThumbColor: BarboraTheme.copper,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
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
                : const Icon(Icons.save),
            label: Text(_saving
                ? 'Guardando…'
                : (widget.isEditing ? 'Guardar cambios' : 'Crear producto')),
          ),
        ],
      ),
    );
  }
}

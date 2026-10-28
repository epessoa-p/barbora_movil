import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/inventory.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'product_edit_screen.dart';
import 'stock_movement_screen.dart';

/// La ficha de un producto: precio, margen, existencias por almacén, los
/// botones de entrada / salida / ajuste y el historial de movimientos.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.options,
  });

  final int productId;
  final InventoryOptions options;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  InventoryProduct? _product;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get(
        '/inventory/products/${widget.productId}',
      );
      if (!mounted) return;
      setState(
        () => _product = InventoryProduct.fromJson(
          body['data'] as Map<String, dynamic>,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move(String type) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => StockMovementScreen(
          product: _product!,
          type: type,
          options: widget.options,
        ),
      ),
    );

    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<InventoryProduct>(
      MaterialPageRoute(
        builder: (_) =>
            ProductEditScreen(product: _product, options: widget.options),
      ),
    );

    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${saved.name} guardado.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canEdit = auth.me?.can('products.edit') ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Producto'),
        actions: [
          if (canEdit && _product != null)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              onPressed: _edit,
            ),
        ],
      ),
      body: _body(auth),
    );
  }

  Widget _body(AuthController auth) {
    if (_loading && _product == null) {
      return const Center(
        child: CircularProgressIndicator(color: BarboraTheme.copper),
      );
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    final p = _product!;
    final symbol = auth.company?.symbol ?? '';
    final canMove = (auth.me?.can('stock.create') ?? false) && p.trackStock;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // Cabecera: nombre, categoría y la existencia total en grande.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: BarboraTheme.inkGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    p.category ?? 'Sin categoría',
                    if (p.sku != null && p.sku!.isNotEmpty) p.sku!,
                    if (!p.isSellable) 'Insumo',
                    if (!p.active) 'Inactivo',
                  ].join(' · '),
                  style: TextStyle(
                    color: BarboraTheme.titanium.withValues(alpha: .8),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 14),
                if (p.trackStock)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        p.stockLabel ?? '—',
                        style: TextStyle(
                          color: p.lowStock
                              ? const Color(0xFFFBBF24)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            p.lowStock
                                ? 'reponer · mín. ${trimNumber(p.minStock)}'
                                : 'mín. ${trimNumber(p.minStock)}',
                            style: TextStyle(
                              color: p.lowStock
                                  ? const Color(0xFFFBBF24)
                                  : BarboraTheme.titanium.withValues(alpha: .7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Sin control de existencias',
                    style: TextStyle(
                      color: BarboraTheme.titanium.withValues(alpha: .8),
                    ),
                  ),
              ],
            ),
          ),

          if (canMove) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _MoveButton(
                  icon: Icons.add_box_outlined,
                  label: 'Entrada',
                  color: const Color(0xFF16A34A),
                  onTap: () => _move('entrada'),
                ),
                const SizedBox(width: 8),
                _MoveButton(
                  icon: Icons.indeterminate_check_box_outlined,
                  label: 'Salida',
                  color: const Color(0xFFDC2626),
                  onTap: () => _move('salida'),
                ),
                const SizedBox(width: 8),
                _MoveButton(
                  icon: Icons.fact_check_outlined,
                  label: 'Ajuste',
                  color: const Color(0xFF2563EB),
                  onTap: () => _move('ajuste'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          _Section(
            title: 'Precio',
            children: [
              _Line(
                label: 'Venta',
                value: '$symbol ${p.salePrice.toStringAsFixed(2)}',
                strong: true,
              ),
              _Line(
                label: 'Costo',
                value: '$symbol ${p.costPrice.toStringAsFixed(2)}',
              ),
              if (p.marginPercent != null)
                _Line(
                  label: 'Margen',
                  value: '${trimNumber(p.marginPercent!)} %',
                ),
            ],
          ),

          // Por almacén solo tiene sentido si hay más de uno con existencias.
          if (p.trackStock && p.stocks.length > 1) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Por almacén',
              children: [
                for (final s in p.stocks)
                  _Line(label: s.warehouse, value: s.label),
              ],
            ),
          ],

          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Descripción',
              children: [_Line(label: p.description!, value: '')],
            ),
          ],

          if (p.trackStock) ...[
            const SizedBox(height: 18),
            const Text(
              'ÚLTIMOS MOVIMIENTOS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: BarboraTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            if (p.movements.isEmpty)
              const Text(
                'Todavía no hay movimientos. Registra una entrada para empezar.',
                style: TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < p.movements.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _MovementRow(move: p.movements[i]),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: BarboraTheme.textMuted,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: BarboraTheme.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 15.5 : 13.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.move});

  final StockMove move;

  @override
  Widget build(BuildContext context) {
    final up = move.quantity >= 0;
    final color = switch (move.type) {
      'entrada' => const Color(0xFF16A34A),
      'salida' => const Color(0xFFDC2626),
      _ => const Color(0xFF2563EB),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              up ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    move.typeLabel,
                    if (move.reasonLabel != null) move.reasonLabel!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  [
                    if (move.createdAt != null)
                      DateFormat('d MMM, HH:mm', 'es').format(move.createdAt!),
                    if (move.createdBy != null) move.createdBy!,
                    if (move.reference != null && move.reference!.isNotEmpty)
                      move.reference!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: BarboraTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${up ? '+' : '−'}${trimNumber(move.quantity.abs())}',
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
              Text(
                'queda ${trimNumber(move.quantityAfter)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: BarboraTheme.titanium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

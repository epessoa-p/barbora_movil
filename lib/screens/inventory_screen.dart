import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/inventory.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'product_detail_screen.dart';
import 'product_edit_screen.dart';

/// Inventario: todos los productos con su existencia, el aviso de stock bajo,
/// y el alta de productos. Cada producto abre su ficha, desde donde se
/// registran entradas, salidas y ajustes.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<InventoryProduct> _products = const [];
  InventoryOptions _options = const InventoryOptions();
  int _lowCount = 0;
  bool _onlyLow = false;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.get('/inventory/products', query: {
          if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
          if (_onlyLow) 'low': 1,
        }),
        api.get('/inventory/options'),
      ]);
      if (!mounted) return;

      setState(() {
        _products = (results[0]['data'] as List? ?? [])
            .map((e) => InventoryProduct.fromJson(e as Map<String, dynamic>))
            .toList();
        _lowCount = results[0]['low_count'] as int? ?? 0;
        _options = InventoryOptions.fromJson(results[1]);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  Future<void> _open(InventoryProduct product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: product.id, options: _options),
      ),
    );

    // Pudo cambiar su existencia o sus datos.
    if (mounted) _load();
  }

  Future<void> _create() async {
    if (_options.limitReached) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Alcanzaste el límite de productos de tu plan.'),
      ));
      return;
    }

    final saved = await Navigator.of(context).push<InventoryProduct>(
      MaterialPageRoute(builder: (_) => ProductEditScreen(options: _options)),
    );

    if (saved == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${saved.name} creado. Registra su primera entrada desde la ficha.')),
    );
    _open(saved);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final symbol = auth.company?.symbol ?? '';
    final canCreate = auth.me?.can('products.create') ?? false;

    return Scaffold(
      floatingActionButton: canCreate && _error == null
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo producto', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar por nombre o código',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  selected: _onlyLow,
                  onSelected: (v) {
                    setState(() => _onlyLow = v);
                    _load();
                  },
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: _lowCount > 0 ? const Color(0xFFD97706) : BarboraTheme.titanium,
                  ),
                  label: Text('Stock bajo ($_lowCount)'),
                ),
              ],
            ),
          ),
          Expanded(child: _body(symbol)),
        ],
      ),
    );
  }

  Widget _body(String symbol) {
    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    if (_products.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 60),
            EmptyView(
              icon: Icons.inventory_2_outlined,
              title: _onlyLow ? 'Nada por reponer' : 'Sin productos',
              subtitle: _onlyLow
                  ? 'Todos los productos están por encima de su mínimo.'
                  : 'Agrega productos con el botón de abajo.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        itemCount: _products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, i) => _ProductTile(
          product: _products[i],
          symbol: symbol,
          onTap: () => _open(_products[i]),
        ),
      ),
    );
  }
}

/// La unidad en plural o singular según la cantidad: sale del «13 unidades»
/// que ya formateó el servidor.
String _unitOf(InventoryProduct p) {
  final label = p.stockLabel;
  if (label == null || !label.contains(' ')) return p.unitLabel.toLowerCase();
  return label.substring(label.indexOf(' ') + 1);
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.symbol, required this.onTap});

  final InventoryProduct product;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final low = product.lowStock;
    final stockColor = low ? const Color(0xFFD97706) : const Color(0xFF16A34A);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: product.active ? null : BarboraTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        product.category ?? 'Sin categoría',
                        if (product.sku != null && product.sku!.isNotEmpty) product.sku!,
                        if (!product.isSellable) 'Insumo',
                        if (!product.active) 'Inactivo',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$symbol ${product.salePrice.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (product.stock != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trimNumber(product.stock!),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: stockColor),
                    ),
                    Text(
                      low ? 'reponer' : _unitOf(product),
                      style: TextStyle(fontSize: 11, color: low ? stockColor : BarboraTheme.textMuted),
                    ),
                  ],
                )
              else
                const Text('sin control', style: TextStyle(fontSize: 11.5, color: BarboraTheme.titanium)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
            ],
          ),
        ),
      ),
    );
  }
}

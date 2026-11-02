import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';
import 'purchase_detail_screen.dart';
import 'purchase_new_screen.dart';

Color purchaseStatusColor(String status) => switch (status) {
      'pagada' => const Color(0xFF16A34A),
      'parcial' => const Color(0xFFCA8A04),
      'anulada' => BarboraTheme.textMuted,
      _ => BarboraTheme.copperDark,
    };

/// Las compras a proveedores, con lo que se les debe.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<PurchaseItem> _purchases = const [];
  double _debt = 0;
  bool _onlyDebt = false;
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
      final body = await context.read<ApiClient>().get('/purchases', query: {if (_onlyDebt) 'status': 'deuda'});
      if (!mounted) return;
      setState(() {
        _purchases = (body['data'] as List? ?? []).map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>)).toList();
        _debt = ((body['summary'] as Map?)?['debt'] as num?)?.toDouble() ?? 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<PurchaseItem>(MaterialPageRoute(builder: (_) => const PurchaseNewScreen()));
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compra ${saved.number} registrada.')));
    _load();
  }

  Future<void> _open(PurchaseItem p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: p.id)));
    if (mounted) _load();
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
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: !_onlyDebt,
                            onSelected: (_) {
                              setState(() => _onlyDebt = false);
                              _load();
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Con deuda'),
                            selected: _onlyDebt,
                            onSelected: (_) {
                              setState(() => _onlyDebt = true);
                              _load();
                            },
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Por pagar', style: TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted)),
                              Text('$symbol ${_debt.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _debt > 0 ? BarboraTheme.copperDark : BarboraTheme.ink,
                                  )),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_purchases.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: EmptyView(icon: Icons.shopping_bag_outlined, title: 'Sin compras'),
                        ),
                      for (final p in _purchases)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminTile(
                            icon: Icons.shopping_bag_outlined,
                            title: '${p.number} · $symbol ${p.total.toStringAsFixed(2)}',
                            dimmed: p.isCancelled,
                            tags: [AdminTag(p.statusLabel, color: purchaseStatusColor(p.status))],
                            subtitle: [
                              shortDate(p.purchasedOn),
                              p.supplier ?? 'Sin proveedor',
                              if (p.balance > 0) 'debe $symbol ${p.balance.toStringAsFixed(2)}',
                            ].join(' · '),
                            onTap: () => _open(p),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: _can('purchases.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _new,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva compra', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

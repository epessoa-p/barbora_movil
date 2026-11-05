import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/finance.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/payment_source_picker.dart';

/// Pagar la liquidación de una persona: todas sus comisiones pendientes
/// (desde la más antigua hasta hoy), con o sin propinas, y de dónde sale el
/// dinero. Queda como gasto «COMISIONES» en Gastos › Personal.
///
///   comisión     lo que gana por cada servicio o venta (se suma sola al cobrar)
///   liquidación  el pago de lo acumulado: un comprobante (L-000x)
///
/// Devuelve true si se pagó.
class SettleCommissionSheet extends StatefulWidget {
  const SettleCommissionSheet({super.key, required this.pending, required this.symbol});

  final PendingCommission pending;
  final String symbol;

  @override
  State<SettleCommissionSheet> createState() => _SettleCommissionSheetState();
}

class _SettleCommissionSheetState extends State<SettleCommissionSheet> {
  PaymentSourceOptions _sources = const PaymentSourceOptions();
  late PaymentSourceSelection _selection = PaymentSourceSelection(_sources);
  bool _includeTips = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _errors = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  /// De dónde puede salir el dinero: las mismas cuentas y turnos que un gasto.
  Future<void> _loadSources() async {
    try {
      final body = await context.read<ApiClient>().get('/finance/options', query: {'group': 'personal'});
      if (!mounted) return;
      setState(() {
        _sources = PaymentSourceOptions.fromJson(body);
        _selection = PaymentSourceSelection(_sources);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    setState(() {
      _saving = true;
      _error = null;
      _errors.clear();
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final p = widget.pending;
      final res = await context.read<ApiClient>().post('/commissions/${p.personalId}/settle', body: {
        'period_start': apiDate(p.since),
        'period_end': apiDate(DateTime.now()),
        'include_tips': _includeTips ? 1 : 0,
        if (_sources.sources.isNotEmpty) ..._selection.toJson(),
      });
      messenger.showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Liquidación pagada.')));
      navigator.pop(true);
    } on ApiException catch (e) {
      setState(() {
        for (final f in ['source', 'finance_account_id', 'cash_session_id']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.firstErrorFor('error') ?? (e.errors.isEmpty ? e.message : null);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    String money(double v) => '${widget.symbol} ${v.toStringAsFixed(2)}';
    final total = p.total + (_includeTips ? p.tips : 0);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagar a ${p.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Liquida ${p.count} ${p.count == 1 ? 'comisión' : 'comisiones'} del ${shortDate(p.since)} a hoy.',
              style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
            ),
            const SizedBox(height: 14),
            _Line('Comisiones', money(p.total)),
            if (p.tips > 0)
              SwitchListTile(
                value: _includeTips,
                onChanged: (v) => setState(() => _includeTips = v),
                activeThumbColor: BarboraTheme.copper,
                contentPadding: EdgeInsets.zero,
                title: Text('Incluir propinas (${money(p.tips)})'),
                subtitle: const Text('Las que le dejaron los clientes en ese tramo.'),
              ),
            const Divider(height: 20),
            _Line('Total a pagar', money(total), bold: true),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
            else if (_sources.sources.isNotEmpty)
              PaymentSourcePicker(options: _sources, selection: _selection, symbol: widget.symbol, errors: _errors),
            AdminFormError(_error),
            const SizedBox(height: 18),
            AdminSaveButton(saving: _saving || _loading, label: 'Pagar liquidación', onPressed: _pay),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

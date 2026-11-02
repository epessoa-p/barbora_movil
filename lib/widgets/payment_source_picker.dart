import 'package:flutter/material.dart';

import '../models/finance.dart';
import '../theme/barbora_theme.dart';

/// Lo elegido en el selector: de dónde sale el dinero.
class PaymentSourceSelection {
  PaymentSourceSelection(PaymentSourceOptions options)
      : source = options.sources.contains('account') ? 'account' : (options.sources.firstOrNull ?? 'account'),
        accountId = options.accounts.firstOrNull?.id,
        sessionId = options.preferredSessionId ?? options.sessions.firstOrNull?.id;

  /// «account» o «cash».
  String source;
  int? accountId;
  int? sessionId;

  /// Lo que se manda a la API junto al gasto o el pago.
  Map<String, dynamic> toJson() => {
        'source': source,
        if (source == 'account') 'finance_account_id': accountId,
        if (source == 'cash') 'cash_session_id': sessionId,
      };
}

/// ¿De dónde sale el dinero? Dos pestañas, como en la web: una cuenta
/// (capital, caja chica, banco…) o un turno de caja abierto. Lo comparten
/// gastos y compras.
class PaymentSourcePicker extends StatefulWidget {
  const PaymentSourcePicker({
    super.key,
    required this.options,
    required this.selection,
    required this.symbol,
    this.title = '¿De dónde sale el dinero?',
    this.errors = const {},
  });

  final PaymentSourceOptions options;
  final PaymentSourceSelection selection;
  final String symbol;
  final String title;

  /// Errores del servidor: source, finance_account_id, cash_session_id.
  final Map<String, String?> errors;

  @override
  State<PaymentSourcePicker> createState() => _PaymentSourcePickerState();
}

class _PaymentSourcePickerState extends State<PaymentSourcePicker> {
  @override
  Widget build(BuildContext context) {
    final o = widget.options;
    final s = widget.selection;

    if (o.sources.isEmpty) {
      return const Text(
        'Tu plan no incluye cuentas ni caja: no se puede pagar desde aquí.',
        style: TextStyle(color: BarboraTheme.copperDark, fontSize: 13),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (o.sources.length > 1)
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'account', label: Text('Cuenta'), icon: Icon(Icons.account_balance, size: 16)),
              ButtonSegment(value: 'cash', label: Text('Caja abierta'), icon: Icon(Icons.point_of_sale, size: 16)),
            ],
            selected: {s.source},
            onSelectionChanged: (v) => setState(() => s.source = v.first),
          ),
        const SizedBox(height: 10),
        if (s.source == 'account')
          o.accounts.isEmpty
              ? const _Hint('No hay cuentas activas. Créalas en Finanzas › Cuentas.')
              : DropdownButtonFormField<int>(
                  initialValue: s.accountId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Cuenta', errorText: widget.errors['finance_account_id']),
                  items: [
                    for (final a in o.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} · ${widget.symbol} ${a.balance.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => s.accountId = v),
                )
        else
          o.sessions.isEmpty
              ? const _Hint('No hay ningún turno de caja abierto. Abre la caja para pagar desde ella.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: s.sessionId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Turno de caja', errorText: widget.errors['cash_session_id']),
                      items: [
                        for (final t in o.sessions)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text('${t.label} · ${widget.symbol} ${t.expectedCash.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => s.sessionId = v),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sale en efectivo del cajón: se descuenta en el arqueo del turno.',
                      style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                  ],
                ),
        if (widget.errors['source'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.errors['source']!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12.5)),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
      );
}

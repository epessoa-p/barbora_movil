import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cash.dart';
import '../state/auth_controller.dart';
import '../state/cash_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'checkout_screen.dart';

/// El turno de caja. Tres estados bien distintos:
///   · sin turno → invita a abrirlo
///   · abierto   → el esperado en el cajón, los movimientos y el botón de cobrar
///   · recién cerrado → el arqueo, para verlo antes de seguir
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CashController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashController>();
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    if (cash.loading && cash.session == null && cash.cajas.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (cash.error != null) {
      return ErrorView(error: cash.error!, onRetry: () => cash.load());
    }

    final session = cash.session;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: () => cash.load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (session == null)
            _OpenShiftCard(cajas: cash.availableCajas, symbol: symbol)
          else if (session.isOpen)
            ..._openShift(session, symbol)
          else
            _ClosedShiftCard(session: session, symbol: symbol),
        ],
      ),
    );
  }

  List<Widget> _openShift(CashSession session, String symbol) => [
        _ExpectedCard(session: session, symbol: symbol),
        const SizedBox(height: 14),
        _Actions(session: session),
        const SizedBox(height: 18),
        _MovementsList(session: session, symbol: symbol),
      ];
}

/// Sin turno abierto: no se puede cobrar, y hay que decirlo sin rodeos.
class _OpenShiftCard extends StatefulWidget {
  const _OpenShiftCard({required this.cajas, required this.symbol});

  final List<Caja> cajas;
  final String symbol;

  @override
  State<_OpenShiftCard> createState() => _OpenShiftCardState();
}

class _OpenShiftCardState extends State<_OpenShiftCard> {
  final _amount = TextEditingController(text: '0');
  int? _cajaId;

  @override
  void initState() {
    super.initState();
    _cajaId = widget.cajas.isNotEmpty ? widget.cajas.first.id : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final cash = context.read<CashController>();
    final messenger = ScaffoldMessenger.of(context);

    final error = await cash.open(
      cajaId: _cajaId!,
      openingAmount: double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
    );

    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: BarboraTheme.copperDark,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashController>();

    if (widget.cajas.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.point_of_sale_outlined, size: 46, color: Colors.black26),
              SizedBox(height: 14),
              Text(
                'No hay ninguna caja libre',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 6),
              Text(
                'Todas las cajas tienen un turno abierto, o todavía no se ha '
                'creado ninguna desde el panel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: BarboraTheme.textMuted, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: BarboraTheme.copper.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.lock_open, color: BarboraTheme.copperDark, size: 21),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Abrir turno de caja',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sin turno abierto no se puede cobrar.',
                        style: TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (widget.cajas.length > 1) ...[
              DropdownButtonFormField<int>(
                initialValue: _cajaId,
                decoration: const InputDecoration(labelText: 'Caja'),
                items: widget.cajas
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.branch == null ? c.name : '${c.name} · ${c.branch}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _cajaId = v),
              ),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Fondo inicial',
                prefixText: '${widget.symbol} ',
                helperText: 'El efectivo con el que empieza el cajón.',
              ),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: cash.busy || _cajaId == null ? null : _open,
              icon: cash.busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Abrir turno'),
            ),
          ],
        ),
      ),
    );
  }
}

/// La cifra que importa mientras el turno está abierto: lo que debería haber
/// en el cajón.
class _ExpectedCard extends StatelessWidget {
  const _ExpectedCard({required this.session, required this.symbol});

  final CashSession session;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EFECTIVO ESPERADO',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: BarboraTheme.titanium.withValues(alpha: .8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Abierto',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                symbol,
                style: const TextStyle(
                  color: BarboraTheme.copperLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                session.totals.expectedCash.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${session.cajaName} · abierta hace ${session.duration}',
            style: TextStyle(
              fontSize: 11.5,
              color: BarboraTheme.titanium.withValues(alpha: .7),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white.withValues(alpha: .1), height: 1),
          ),

          Row(
            children: [
              _Figure(label: 'Fondo', value: session.openingAmount, symbol: symbol),
              _Figure(label: 'Entró', value: session.totals.cashIncome, symbol: symbol),
              _Figure(
                label: 'Salió',
                value: session.totals.cashExpense,
                symbol: symbol,
                negative: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.symbol,
    this.negative = false,
  });

  final String label;
  final double value;
  final String symbol;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: BarboraTheme.titanium.withValues(alpha: .65),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${negative && value > 0 ? '−' : ''}$symbol ${value.toStringAsFixed(2)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final can = context.watch<AuthController>().me;

    return Column(
      children: [
        if (can?.can('sales.create') ?? false)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CheckoutScreen()),
            ),
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Cobrar'),
          ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _movementSheet(context),
                icon: const Icon(Icons.swap_vert, size: 18),
                label: const Text('Movimiento', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _closeSheet(context, session),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Cerrar turno', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BarboraTheme.copperDark,
                  side: BorderSide(color: BarboraTheme.copper.withValues(alpha: .35)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _movementSheet(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _MovementSheet(),
      );

  void _closeSheet(BuildContext context, CashSession session) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CloseSheet(session: session),
      );
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.session, required this.symbol});

  final CashSession session;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    if (session.movements.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Todavía no hay movimientos en este turno.',
              style: TextStyle(color: BarboraTheme.textMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              const Text(
                'MOVIMIENTOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: BarboraTheme.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${session.movements.length}',
                style: const TextStyle(fontSize: 11.5, color: BarboraTheme.titanium),
              ),
            ],
          ),
        ),
        ...session.movements.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _MovementTile(movement: m, symbol: symbol),
          ),
        ),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.symbol});

  final CashMovement movement;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final color = movement.isIncome ? const Color(0xFF16A34A) : BarboraTheme.copperDark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                movement.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                size: 17,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movement.concept,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  // Qué incluyó la venta (servicios/productos).
                  if (movement.detail != null && movement.detail!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      movement.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.ink, height: 1.25),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('HH:mm').format(movement.createdAt)}'
                    '  ·  ${movement.paymentMethodLabel}'
                    '${movement.createdBy != null ? '  ·  ${movement.createdBy}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${movement.isIncome ? '+' : '−'}$symbol ${movement.amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// El arqueo, recién hecho.
class _ClosedShiftCard extends StatelessWidget {
  const _ClosedShiftCard({required this.session, required this.symbol});

  final CashSession session;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final difference = session.difference ?? 0;
    final squared = difference.abs() < 0.005;

    final color = squared
        ? const Color(0xFF16A34A)
        : (difference > 0 ? const Color(0xFF0EA5E9) : BarboraTheme.copperDark);

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  squared ? Icons.check_circle_outline : Icons.report_problem_outlined,
                  size: 44,
                  color: color,
                ),
                const SizedBox(height: 12),
                Text(
                  session.differenceLabel ?? 'Turno cerrado',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.cajaName} · ${session.duration}',
                  style: const TextStyle(color: BarboraTheme.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 20),

                _Line(label: 'Esperado', value: session.expectedAmount ?? 0, symbol: symbol),
                _Line(label: 'Contado', value: session.closingAmount ?? 0, symbol: symbol),
                const Divider(height: 22),
                _Line(
                  label: 'Diferencia',
                  value: difference,
                  symbol: symbol,
                  strong: true,
                  color: color,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.read<CashController>().dismissClosed(),
          child: const Text('Abrir un turno nuevo'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    required this.symbol,
    this.strong = false,
    this.color,
  });

  final String label;
  final double value;
  final String symbol;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: strong ? 15 : 13.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: strong ? BarboraTheme.ink : BarboraTheme.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            '$symbol ${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: strong ? 17 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: color ?? BarboraTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Registrar un ingreso o un egreso a mano.
class _MovementSheet extends StatefulWidget {
  const _MovementSheet();

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _concept = TextEditingController();
  final _amount = TextEditingController();
  String _type = 'egreso';
  String? _method;

  /// Los métodos de esta barbería, que vienen de `/me`. El fallback solo actúa
  /// si la sesión todavía no cargó.
  List<PaymentMethod> _methods(BuildContext context) {
    final methods = context.read<AuthController>().me?.paymentMethods ?? const [];

    return methods.isEmpty ? PaymentMethod.fallback : methods;
  }

  @override
  void dispose() {
    _concept.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cash = context.read<CashController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final error = await cash.addMovement(
      type: _type,
      paymentMethod: _method ?? _methods(context).first.slug,
      concept: _concept.text.trim(),
      amount: double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
    );

    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: BarboraTheme.copperDark,
      ));
      return;
    }

    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Movimiento registrado.')));
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashController>();

    return _Sheet(
      title: 'Movimiento de caja',
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ingreso', label: Text('Entra')),
            ButtonSegment(value: 'egreso', label: Text('Sale')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _concept,
          decoration: const InputDecoration(
            labelText: 'Concepto',
            hintText: 'Ej: compra de toallas',
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Importe'),
        ),
        const SizedBox(height: 14),

        DropdownButtonFormField<String>(
          initialValue: _method ?? _methods(context).first.slug,
          decoration: const InputDecoration(labelText: 'Método'),
          items: _methods(context)
              .map((m) => DropdownMenuItem(value: m.slug, child: Text(m.name)))
              .toList(),
          onChanged: (v) => setState(() => _method = v ?? _methods(context).first.slug),
        ),
        const SizedBox(height: 22),

        FilledButton(
          onPressed: cash.busy ? null : _save,
          child: cash.busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Registrar'),
        ),
      ],
    );
  }
}

/// Cerrar el turno: se cuenta el efectivo y se compara con el esperado.
class _CloseSheet extends StatefulWidget {
  const _CloseSheet({required this.session});

  final CashSession session;

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final cash = context.read<CashController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final error = await cash.close(
      countedAmount: double.tryParse(_counted.text.replaceAll(',', '.')) ?? 0,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: BarboraTheme.copperDark,
      ));
      return;
    }

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashController>();
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return _Sheet(
      title: 'Cerrar turno',
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BarboraTheme.canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Text(
                'Debería haber',
                style: TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
              ),
              const Spacer(),
              Text(
                '$symbol ${widget.session.totals.expectedCash.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _counted,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Efectivo contado',
            prefixText: '$symbol ',
            helperText: 'Cuenta el cajón y escribe lo que hay de verdad.',
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notas (opcional)'),
        ),
        const SizedBox(height: 22),

        FilledButton(
          onPressed: cash.busy ? null : _close,
          style: FilledButton.styleFrom(backgroundColor: BarboraTheme.ink),
          child: cash.busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Cerrar y arquear'),
        ),
      ],
    );
  }
}

/// Envoltorio común de las hojas inferiores.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BarboraTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

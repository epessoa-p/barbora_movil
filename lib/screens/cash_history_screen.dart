import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/cash.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'cash_screen.dart';

/// Color del resultado del arqueo: verde si cuadró, azul si sobró, cobre si
/// faltó. Gris mientras el turno sigue abierto.
Color _resultColor(CashSession s) {
  if (s.isOpen) return BarboraTheme.titanium;
  final d = s.difference ?? 0;
  if (d.abs() < 0.005) return const Color(0xFF16A34A);
  return d > 0 ? const Color(0xFF0EA5E9) : BarboraTheme.copperDark;
}

String _when(DateTime d) => DateFormat("EEE d MMM, HH:mm", 'es').format(d);

/// Historial de turnos de caja: cada cierre con lo esperado, lo contado y la
/// diferencia. Tocar uno abre su detalle con todos los movimientos.
class CashHistoryScreen extends StatefulWidget {
  const CashHistoryScreen({super.key});

  @override
  State<CashHistoryScreen> createState() => _CashHistoryScreenState();
}

class _CashHistoryScreenState extends State<CashHistoryScreen> {
  List<CashSession> _sessions = const [];
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
      final body = await context.read<ApiClient>().get('/cash/sessions');
      if (!mounted) return;
      setState(() => _sessions = (body['data'] as List? ?? [])
          .map((e) => CashSession.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Turnos de caja'),
      ),
      body: _body(symbol),
    );
  }

  Widget _body(String symbol) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    if (_sessions.isEmpty) {
      return const EmptyView(
        icon: Icons.history,
        title: 'Sin turnos todavía',
        subtitle: 'Aquí quedan los cierres de caja con su arqueo.',
      );
    }

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: _sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _SessionTile(
          session: _sessions[i],
          symbol: symbol,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CashSessionDetailScreen(sessionId: _sessions[i].id)),
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.symbol, required this.onTap});

  final CashSession session;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final color = _resultColor(s);
    final difference = s.difference ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _when(s.openedAt),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [s.cajaName, s.duration, if (s.closedBy != null) s.closedBy!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ingresos $symbol ${s.totals.income.toStringAsFixed(2)} · ${s.movementsCount} mov.',
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.isOpen ? 'Abierto' : (s.differenceLabel ?? ''),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  if (!s.isOpen && difference.abs() >= 0.005)
                    Text(
                      '${difference > 0 ? '+' : '−'}$symbol ${difference.abs().toStringAsFixed(2)}',
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un turno pasado (o el abierto) en detalle: arqueo, desglose por forma de
/// pago, notas y todos los movimientos.
class CashSessionDetailScreen extends StatefulWidget {
  const CashSessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<CashSessionDetailScreen> createState() => _CashSessionDetailScreenState();
}

class _CashSessionDetailScreenState extends State<CashSessionDetailScreen> {
  CashSession? _session;
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
      final body = await context.read<ApiClient>().get('/cash/sessions/${widget.sessionId}');
      if (!mounted) return;
      setState(() => _session = CashSession.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final symbol = auth.company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Turno de caja'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : _content(_session!, symbol, auth),
    );
  }

  Widget _content(CashSession s, String symbol, AuthController auth) {
    final color = _resultColor(s);
    final difference = s.difference ?? 0;

    // Nombre legible de cada forma de pago; si se dio de baja, el slug.
    final methodNames = {
      for (final m in auth.me?.paymentMethods ?? const <PaymentMethod>[]) m.slug: m.name,
    };
    final usedMethods = s.byMethod.entries.where((e) => e.value.count > 0).toList();

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.cajaName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                        ),
                      ),
                      Text(
                        s.isOpen ? 'Abierto' : (s.differenceLabel ?? ''),
                        style: TextStyle(color: color, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Abrió ${s.openedBy ?? '—'} · ${_when(s.openedAt)}',
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                  if (s.closedAt != null)
                    Text(
                      'Cerró ${s.closedBy ?? '—'} · ${_when(s.closedAt!)} (${s.duration})',
                      style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                    ),
                  const Divider(height: 24),
                  _Row(label: 'Fondo inicial', value: s.openingAmount, symbol: symbol),
                  _Row(label: 'Ingresos', value: s.totals.income, symbol: symbol),
                  _Row(label: 'Egresos', value: -s.totals.expense, symbol: symbol),
                  if (!s.isOpen) ...[
                    const Divider(height: 20),
                    _Row(label: 'Efectivo esperado', value: s.expectedAmount ?? 0, symbol: symbol),
                    _Row(label: 'Efectivo contado', value: s.closingAmount ?? 0, symbol: symbol),
                    _Row(label: 'Diferencia', value: difference, symbol: symbol, strong: true, color: color),
                  ] else
                    _Row(
                      label: 'Efectivo esperado ahora',
                      value: s.totals.expectedCash,
                      symbol: symbol,
                      strong: true,
                    ),
                ],
              ),
            ),
          ),

          if (usedMethods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'POR FORMA DE PAGO',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: BarboraTheme.textMuted),
                    ),
                    const SizedBox(height: 8),
                    for (final e in usedMethods)
                      _Row(
                        label: '${e.value.label ?? methodNames[e.key] ?? e.key} (${e.value.count})',
                        value: e.value.income - e.value.expense,
                        symbol: symbol,
                      ),
                  ],
                ),
              ),
            ),
          ],

          for (final (title, note) in [('Notas de apertura', s.openingNotes), ('Notas de cierre', s.closingNotes)])
            if (note != null && note.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(title, style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
                  subtitle: Text(note, style: const TextStyle(fontSize: 14, color: BarboraTheme.ink)),
                ),
              ),
            ],

          const SizedBox(height: 18),
          Text(
            'MOVIMIENTOS (${s.movements.length})',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: BarboraTheme.textMuted),
          ),
          const SizedBox(height: 10),
          if (s.movements.isEmpty)
            const Text('Sin movimientos en este turno.', style: TextStyle(color: BarboraTheme.textMuted))
          else
            for (final m in s.movements)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: CashMovementTile(movement: m, symbol: symbol),
              ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.symbol, this.strong = false, this.color});

  final String label;
  final double value;
  final String symbol;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sign = value < -0.004 ? '−' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 15 : 13.5,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? BarboraTheme.ink : BarboraTheme.textMuted,
              ),
            ),
          ),
          Text(
            '$sign$symbol ${value.abs().toStringAsFixed(2)}',
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

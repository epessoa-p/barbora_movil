import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/balance_report.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'profit_report_screen.dart';

const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);
const _blue = Color(0xFF2563EB);

/// Balance: lo que entró y salió de verdad, de caja y de tesorería.
///
///   Resultados   ingresos y egresos por categoría y la utilidad; los aportes
///                del dueño van aparte.
///   Movimientos  caja / tesorería / todo, con totales, por categoría y lista.
///   Cierres      los turnos de caja del periodo con su arqueo.
///
/// Los datos vienen de `GET /reports/balance`.
class BalanceReportScreen extends StatefulWidget {
  const BalanceReportScreen({super.key});

  @override
  State<BalanceReportScreen> createState() => _BalanceReportScreenState();
}

class _BalanceReportScreenState extends State<BalanceReportScreen> {
  BalanceReportView? _report;
  ApiException? _error;
  bool _loading = true;

  String _preset = 'mes';
  String _source = 'caja';
  String? _type;

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
      final body = await context.read<ApiClient>().get('/reports/balance', query: {
        'preset': _preset,
        'source': _source,
        'type': ?_type,
      });

      if (!mounted) return;
      setState(() => _report = BalanceReportView.fromJson(body));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: BarboraTheme.inkSoft,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Balance'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: BarboraTheme.copper,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(icon: Icon(Icons.assessment_outlined, size: 20), text: 'Resultados'),
              Tab(icon: Icon(Icons.swap_vert, size: 20), text: 'Movimientos'),
              Tab(icon: Icon(Icons.lock_clock_outlined, size: 20), text: 'Cierres'),
            ],
          ),
        ),
        body: _body(symbol),
      ),
    );
  }

  Widget _body(String symbol) {
    if (_loading && _report == null) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    final r = _report!;
    final money = _Money(symbol);

    Widget page(List<Widget> children) => RefreshIndicator(
          color: BarboraTheme.copper,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              ReportPeriodChips(
                period: r.period,
                onPick: (p) {
                  if (p != _preset) _set(() => _preset = p);
                },
              ),
              const SizedBox(height: 6),
              Text(r.period.label, style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        );

    return TabBarView(
      children: [
        page(_results(r, money)),
        page(_movements(r, money)),
        page(_closings(r, money)),
      ],
    );
  }

  /* ── Resultados ─────────────────────────────────────────────────────── */

  List<Widget> _results(BalanceReportView r, _Money money) {
    final positive = r.profit >= 0;

    return [
      _SideCard(title: 'Ingresos', color: _green, side: r.income, money: money, empty: 'Sin ingresos en el periodo.'),
      const SizedBox(height: 12),
      _SideCard(title: 'Egresos', color: _red, side: r.expense, money: money, empty: 'Sin egresos en el periodo.'),
      const SizedBox(height: 12),
      Card(
        color: positive ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resultado del periodo', style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
                    Text(positive ? 'Utilidad' : 'Pérdida', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Text(
                money(r.profit),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: positive ? _green : _red),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.savings_outlined, color: _blue, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Aportes de capital', style: TextStyle(fontWeight: FontWeight.w800)),
                    if (r.withdrawals > 0)
                      Text('Retiros: ${money(r.withdrawals)}', style: const TextStyle(fontSize: 12.5, color: _blue)),
                    const Text(
                      'Dinero que puso el dueño. No es ganancia: no entra en la utilidad.',
                      style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(money(r.contributions), style: const TextStyle(fontWeight: FontWeight.w800, color: _blue)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Cuenta el dinero, no lo vendido: una compra resta el día que se paga. '
        'Las transferencias entre cuentas no cuentan.',
        style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
      ),
    ];
  }

  /* ── Movimientos ────────────────────────────────────────────────────── */

  List<Widget> _movements(BalanceReportView r, _Money money) {
    final note = switch (r.source) {
      'caja' => 'Solo movimientos de caja: es lo que cuadra con los cierres.',
      'tesoreria' => 'Solo las cuentas (capital, banco…), sin transferencias entre ellas.',
      _ => 'Caja y tesorería juntas.',
    };
    final max = r.categories.fold<double>(1, (m, c) => c.total > m ? c.total : m);

    final list = <Widget>[];
    DateTime? day;
    for (final m in r.movements) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      if (day != d) {
        day = d;
        list.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            _capitalize(DateFormat("EEEE d 'de' MMMM", 'es').format(d)),
            style: const TextStyle(fontWeight: FontWeight.w700, color: BarboraTheme.textMuted, fontSize: 13),
          ),
        ));
      }
      list.add(_MovementTile(movement: m, money: money));
    }

    return [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'caja', label: Text('Caja'), icon: Icon(Icons.point_of_sale, size: 18)),
          ButtonSegment(value: 'tesoreria', label: Text('Tesorería'), icon: Icon(Icons.account_balance, size: 18)),
          ButtonSegment(value: 'todo', label: Text('Todo')),
        ],
        selected: {_source},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _set(() => _source = s.first),
      ),
      const SizedBox(height: 6),
      Text(note, style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _Stat(label: 'INGRESOS', value: money(r.flowIncome), color: _green)),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'EGRESOS', value: money(r.flowExpense), color: _red)),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'BALANCE', value: money(r.flowBalance))),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final (value, label) in [(null, 'Todos'), ('ingreso', 'Ingresos'), ('egreso', 'Egresos')])
            ChoiceChip(
              label: Text(label),
              selected: _type == value,
              onSelected: (_) {
                if (_type != value) _set(() => _type = value);
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Por categoría', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: r.categories.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Sin movimientos.', style: TextStyle(color: BarboraTheme.textMuted)),
                )
              : Column(
                  children: [
                    for (final c in r.categories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(c.label)),
                                Text(
                                  money(c.total),
                                  style: TextStyle(fontWeight: FontWeight.w700, color: c.isIncome ? _green : _red),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: c.total / max,
                                minHeight: 6,
                                color: c.isIncome ? _green : _red,
                                backgroundColor: (c.isIncome ? _green : _red).withValues(alpha: .12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Movimientos (${r.movementsCount})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (r.movementsCount > r.movements.length)
        Text(
          'Se muestran los ${r.movements.length} más recientes; los totales cuentan todos.',
          style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
        ),
      if (r.movements.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Sin movimientos en el periodo.', style: TextStyle(color: BarboraTheme.textMuted)),
        ),
      ...list,
    ];
  }

  /* ── Cierres ────────────────────────────────────────────────────────── */

  List<Widget> _closings(BalanceReportView r, _Money money) {
    if (r.closings.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 24),
          child: Center(
            child: Text('No hay turnos de caja en el periodo.', style: TextStyle(color: BarboraTheme.textMuted)),
          ),
        ),
      ];
    }

    return [
      for (final c in r.closings) ...[
        _ClosingCard(closing: c, money: money),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _Money {
  const _Money(this.symbol);

  final String symbol;

  String call(double v) => '$symbol ${NumberFormat('#,##0.00', 'en').format(v)}';
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _when(DateTime? d) => d == null ? '—' : DateFormat('dd/MM HH:mm').format(d);

/// Ingresos o egresos: una fila por categoría, el total y caja / tesorería.
class _SideCard extends StatelessWidget {
  const _SideCard({required this.title, required this.color, required this.side, required this.money, required this.empty});

  final String title;
  final Color color;
  final BalanceSide side;
  final _Money money;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
            const SizedBox(height: 8),
            if (side.lines.isEmpty) Text(empty, style: const TextStyle(color: BarboraTheme.textMuted)),
            for (final l in side.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(l.label)),
                    Text(money(l.total)),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(child: Text('Total ${title.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(money(side.total), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              children: [
                _SourceAmount(icon: Icons.point_of_sale, label: 'Caja ${money(side.cash)}'),
                _SourceAmount(icon: Icons.account_balance, label: 'Tesorería ${money(side.treasury)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceAmount extends StatelessWidget {
  const _SourceAmount({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: BarboraTheme.textMuted),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: BarboraTheme.textMuted, letterSpacing: .4)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.money});

  final BalanceMovement movement;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final color = m.isIncome ? _green : _red;
    final details = [
      m.categoryLabel,
      DateFormat('HH:mm').format(m.at),
      if (m.place.isNotEmpty) m.place,
      if (m.source == 'tesoreria') 'Tesorería' else ?m.method,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(m.isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color, size: 20),
        ),
        title: Text(m.concept, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: Text(
          '${m.isIncome ? '+' : '−'}${money(m.amount)}',
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

/// Un turno de caja: apertura, efectivo que entró y salió, esperado, contado
/// y la diferencia. Lo cobrado por otros medios va aparte: no está en el cajón.
class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.closing, required this.money});

  final BalanceClosing closing;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    final c = closing;
    final diff = c.difference ?? 0;

    Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: BarboraTheme.textMuted))),
              Text(value, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    final (diffText, diffColor) = diff.abs() < .01
        ? ('Exacto', _green)
        : diff > 0
            ? ('Sobrante ${money(diff)}', _blue)
            : ('Faltante ${money(-diff)}', _red);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.title.isEmpty ? (c.number ?? 'Caja') : c.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: (c.open ? const Color(0xFFEA580C) : _green).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.open ? 'Abierta' : 'Cerrada',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.open ? const Color(0xFFEA580C) : _green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Abrió ${c.openedBy ?? '—'} · ${_when(c.openedAt)}',
                style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
            if (c.closedAt != null)
              Text('Cerró ${c.closedBy ?? '—'} · ${_when(c.closedAt)}',
                  style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted)),
            const Divider(height: 22),
            row('Apertura', money(c.opening)),
            row('Ingresos efectivo', '+${money(c.cashIncome)}', color: _green),
            row('Egresos efectivo', '−${money(c.cashExpense)}', color: _red),
            row('Esperado en el cajón', money(c.expected), bold: true),
            if (!c.open) ...[
              row('Contado', money(c.counted ?? 0), bold: true),
              row('Diferencia', diffText, color: diffColor, bold: true),
            ],
            if (c.otherMethods.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Otros medios: ${c.otherMethods.map((o) => '${o.label} ${money(o.amount)}').join(' · ')}',
                style: const TextStyle(fontSize: 12.5, color: _blue),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

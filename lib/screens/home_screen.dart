import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/dashboard.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/appointment_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/report_chart.dart';
import 'appointment_detail_screen.dart';

/// El Inicio: el resumen del día para el jefe (permiso `dashboard.view`).
///
/// Citas de hoy y las próximas, lo cobrado frente a ayer con la semana en un
/// gráfico, el estado de la caja y lo que hay que reponer. Cada bloque llega
/// solo si el plan y los permisos lo dejan ver; si no, no se pinta.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenAgenda,
    this.onOpenCash,
    this.onOpenSales,
    this.onOpenInventory,
    this.onNewAppointment,
    this.onCheckout,
  });

  // Atajos a otras secciones (los pone HomeShell; null = no hay acceso).
  final VoidCallback? onOpenAgenda;
  final VoidCallback? onOpenCash;
  final VoidCallback? onOpenSales;
  final VoidCallback? onOpenInventory;
  final VoidCallback? onNewAppointment;
  final VoidCallback? onCheckout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Dashboard? _data;
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
      final body = await context.read<ApiClient>().get('/dashboard');
      if (!mounted) return;
      setState(() => _data = Dashboard.fromJson(body));
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

    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    final d = _data!;
    final name = auth.me?.personal?.fullName ?? auth.me?.user.name ?? '';
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    final today = DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now());

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            firstName.isEmpty ? 'Hola' : 'Hola, ${_capitalize(firstName.toLowerCase())}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.4),
          ),
          Text(
            _capitalize(today),
            style: const TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
          ),
          const SizedBox(height: 14),

          if (widget.onNewAppointment != null || widget.onCheckout != null) ...[
            Row(
              children: [
                if (widget.onNewAppointment != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onNewAppointment,
                      icon: const Icon(Icons.event_available, size: 19),
                      label: const Text('Nueva cita'),
                    ),
                  ),
                if (widget.onNewAppointment != null && widget.onCheckout != null)
                  const SizedBox(width: 10),
                if (widget.onCheckout != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onCheckout,
                      icon: const Icon(Icons.point_of_sale, size: 19),
                      label: const Text('Cobrar'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          if (d.sales != null) ...[
            _SalesCard(sales: d.sales!, symbol: symbol, onTap: widget.onOpenSales),
            const SizedBox(height: 12),
          ],

          if (d.agenda != null) ...[
            _AgendaCard(agenda: d.agenda!, symbol: symbol, onTap: widget.onOpenAgenda),
            const SizedBox(height: 12),
          ],

          if (d.cash != null) ...[
            _CashCard(cash: d.cash!, symbol: symbol, onTap: widget.onOpenCash),
            const SizedBox(height: 12),
          ],

          if (d.stock != null && d.stock!.lowCount > 0) ...[
            _StockCard(stock: d.stock!, onTap: widget.onOpenInventory),
            const SizedBox(height: 12),
          ],

          if (d.sales?.week != null && d.sales!.week!.hasData)
            ReportChartCard(chart: d.sales!.week!, symbol: symbol),
        ],
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Tarjeta base: título, contenido y, si se puede, «Ver» para ir a la sección.
class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.child, this.onTap, this.dark = false});

  final IconData icon;
  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : BarboraTheme.ink;
    final muted = dark ? BarboraTheme.titanium.withValues(alpha: .8) : BarboraTheme.textMuted;

    return Container(
      decoration: BoxDecoration(
        gradient: dark ? BarboraTheme.inkGradient : null,
        color: dark ? null : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: dark ? null : Border.all(color: BarboraTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: muted),
                    const SizedBox(width: 8),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: muted),
                    ),
                    const Spacer(),
                    if (onTap != null) Icon(Icons.chevron_right, color: muted, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.sales, required this.symbol, this.onTap});

  final DashSales sales;
  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = sales.vsYesterday;
    final up = (vs ?? 0) >= 0;

    return _Block(
      icon: Icons.payments_outlined,
      title: 'Cobrado hoy',
      onTap: onTap,
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$symbol ${sales.today.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (vs != null) ...[
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    size: 16, color: up ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
                const SizedBox(width: 4),
                Text(
                  '${up ? '+' : ''}${vs.toStringAsFixed(0)} % vs ayer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: up ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                  ),
                ),
              ] else
                Text(
                  'Ayer: $symbol ${sales.yesterday.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12.5, color: BarboraTheme.titanium.withValues(alpha: .8)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(value: '${sales.count}', label: sales.count == 1 ? 'venta' : 'ventas', dark: true),
              _MiniStat(value: '$symbol ${sales.average.toStringAsFixed(2)}', label: 'ticket medio', dark: true),
              _MiniStat(value: '$symbol ${sales.tips.toStringAsFixed(2)}', label: 'propinas', dark: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({required this.agenda, required this.symbol, this.onTap});

  final DashAgenda agenda;
  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Block(
      icon: Icons.calendar_today_outlined,
      title: 'Citas de hoy',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MiniStat(value: '${agenda.total}', label: 'citas'),
              _MiniStat(value: '${agenda.pending}', label: 'pendientes'),
              _MiniStat(value: '${agenda.attended}', label: 'atendidas', color: const Color(0xFF16A34A)),
              if (agenda.noShow > 0)
                _MiniStat(value: '${agenda.noShow}', label: 'no vinieron', color: BarboraTheme.copperDark),
            ],
          ),
          const SizedBox(height: 12),
          if (agenda.next.isEmpty)
            const Text(
              'No quedan citas pendientes hoy.',
              style: TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
            )
          else ...[
            const Text(
              'Próximas',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: BarboraTheme.textMuted),
            ),
            const SizedBox(height: 8),
            for (final a in agenda.next)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppointmentTile(
                  appointment: a,
                  showBarber: true,
                  currencySymbol: symbol,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointmentId: a.id)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({required this.cash, required this.symbol, this.onTap});

  final DashCash cash;
  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Block(
      icon: Icons.point_of_sale_outlined,
      title: 'Caja',
      onTap: onTap,
      child: cash.open
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cash.caja ?? 'Caja'} · abierta',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      if (cash.openedBy != null)
                        Text(
                          'Abrió ${cash.openedBy}',
                          style: const TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$symbol ${cash.expectedCash.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    const Text('en el cajón', style: TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted)),
                  ],
                ),
              ],
            )
          : const Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: BarboraTheme.copperDark),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No hay turno abierto: no se puede cobrar hasta abrirlo.',
                    style: TextStyle(fontSize: 13, color: BarboraTheme.copperDark),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.stock, this.onTap});

  final DashStock stock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD97706);

    return _Block(
      icon: Icons.warning_amber_rounded,
      title: 'Por reponer (${stock.lowCount})',
      onTap: onTap,
      child: Column(
        children: [
          for (final item in stock.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                  Text(item.stock, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: amber)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.color, this.dark = false});

  final String value;
  final String label;
  final Color? color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color ?? (dark ? Colors.white : BarboraTheme.ink),
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: dark ? BarboraTheme.titanium.withValues(alpha: .75) : BarboraTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

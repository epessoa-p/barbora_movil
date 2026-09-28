import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/commission.dart';
import '../state/my_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

/// Lo que el barbero lleva ganado y lo que la barbería todavía le debe.
class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({super.key});

  @override
  State<CommissionsScreen> createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  static const _presets = {
    'semana': 'Semana',
    'mes': 'Este mes',
    'mes_pasado': 'Mes pasado',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MyController>().loadCommissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final my = context.watch<MyController>();
    final report = my.commissions;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: () => my.loadCommissions(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SegmentedButton<String>(
            segments: _presets.entries
                .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                .toList(),
            selected: {my.preset},
            onSelectionChanged: (s) => my.loadCommissions(preset: s.first),
          ),
          const SizedBox(height: 18),

          if (my.loadingCommissions && report == null)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator(color: BarboraTheme.copper)),
            )
          else if (my.commissionsError != null)
            SizedBox(
              height: 320,
              child: ErrorView(
                error: my.commissionsError!,
                onRetry: () => my.loadCommissions(),
              ),
            )
          else if (report != null) ...[
            _PayoutCard(report: report),
            const SizedBox(height: 18),

            Row(
              children: [
                const Text(
                  'DETALLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: BarboraTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                // Expanded y no Spacer + Text: con una etiqueta de periodo larga,
                // o con el texto ampliado por accesibilidad, aquello desbordaba.
                // Así el texto ocupa lo que queda y se recorta si no cabe.
                Expanded(
                  child: Text(
                    report.periodLabel,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: BarboraTheme.titanium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (report.entries.isEmpty)
              const SizedBox(
                height: 200,
                child: EmptyView(
                  icon: Icons.savings_outlined,
                  title: 'Sin comisiones en este periodo',
                  subtitle: 'Aparecerán aquí en cuanto se cobre una atención tuya.',
                ),
              )
            else
              ...report.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _EntryTile(entry: e, symbol: report.currencySymbol),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// La tarjeta de arriba: lo que se va a cobrar. Es el dato que se busca al
/// abrir esta pantalla, así que va grande y en la marca.
class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.report});

  final CommissionReport report;

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
          Text(
            'PENDIENTE DE COBRO',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: BarboraTheme.titanium.withValues(alpha: .8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                report.currencySymbol,
                style: const TextStyle(
                  color: BarboraTheme.copperLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                report.totalToCollect.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Comisiones sin liquidar más propinas del periodo.',
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
              _Figure(
                label: 'Devengado',
                value: report.earned,
                symbol: report.currencySymbol,
              ),
              _Figure(
                label: 'Ya pagado',
                value: report.settled,
                symbol: report.currencySymbol,
                muted: true,
              ),
              _Figure(
                label: 'Propinas',
                value: report.tips,
                symbol: report.currencySymbol,
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
    this.muted = false,
  });

  final String label;
  final double value;
  final String symbol;
  final bool muted;

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
            '$symbol ${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: muted
                  ? BarboraTheme.titanium.withValues(alpha: .75)
                  : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.symbol});

  final CommissionEntry entry;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (entry.settled
                        ? const Color(0xFF16A34A)
                        : BarboraTheme.copper)
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                entry.settled ? Icons.check : Icons.schedule,
                size: 18,
                color: entry.settled ? const Color(0xFF16A34A) : BarboraTheme.copperDark,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description ?? 'Atención',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('d/MM · HH:mm', 'es').format(entry.earnedAt)}'
                    '${entry.rateLabel != null ? '  ·  ${entry.rateLabel}' : ''}',
                    style: const TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$symbol ${entry.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.settled ? 'Liquidada' : 'Pendiente',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: entry.settled
                        ? const Color(0xFF16A34A)
                        : BarboraTheme.copperDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

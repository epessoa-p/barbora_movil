import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/client.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/appointment_tile.dart';
import '../widgets/error_view.dart';
import 'appointment_detail_screen.dart';

/// La ficha del cliente: quién es, lo que la barbería sabe de él y su historia.
///
/// Carga `GET /clients/{id}`, que trae el resumen (visitas, gasto, última
/// visita) y las últimas citas. Lo que se ve de un vistazo antes de atenderlo:
/// qué suele pedir, si tiene alguna alergia y cuándo vino por última vez.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final int clientId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  ClientDetail? _detail;
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
      final body = await context.read<ApiClient>().get('/clients/${widget.clientId}');

      if (!mounted) return;
      setState(() => _detail =
          ClientDetail.fromJson(body['data'] as Map<String, dynamic>));
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
        title: const Text('Ficha del cliente'),
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

    final detail = _detail!;
    final c = detail.client;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _Header(client: c),
          const SizedBox(height: 16),

          _StatsRow(stats: detail.stats, symbol: symbol),

          if (c.allergies != null && c.allergies!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _AlertCard(text: c.allergies!),
          ],

          if (c.preferences != null && c.preferences!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _NoteCard(
              icon: Icons.content_cut,
              title: 'Preferencias',
              text: c.preferences!,
            ),
          ],

          if (c.phone != null || c.email != null || c.documentNumber != null) ...[
            const SizedBox(height: 14),
            _ContactCard(client: c),
          ],

          const SizedBox(height: 20),
          _RecentAppointments(detail: detail, symbol: symbol),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: BarboraTheme.inkGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: BarboraTheme.copperGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              client.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -.2,
                  ),
                ),
                if (client.documentNumber != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Doc. ${client.documentNumber}',
                    style: TextStyle(
                      color: BarboraTheme.titanium.withValues(alpha: .85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.symbol});

  final ClientStats stats;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final lastVisit = stats.lastVisit == null
        ? '—'
        : DateFormat("d MMM yyyy", 'es').format(stats.lastVisit!);

    return Row(
      children: [
        _StatCard(
          icon: Icons.event_repeat,
          value: '${stats.visits}',
          label: 'visitas',
        ),
        const SizedBox(width: 10),
        _StatCard(
          icon: Icons.payments_outlined,
          value: '$symbol ${stats.totalSpent.toStringAsFixed(0)}',
          label: 'gastado',
        ),
        const SizedBox(width: 10),
        _StatCard(
          icon: Icons.history,
          value: lastVisit,
          label: 'última visita',
          small: true,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.small = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: BarboraTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BarboraTheme.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: BarboraTheme.copperDark),
            const SizedBox(height: 7),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: small ? 12.5 : 16,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: BarboraTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alergias',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFFB45309),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF92400E), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: BarboraTheme.titanium),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: BarboraTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (client.phone != null)
            _ContactRow(icon: Icons.phone_outlined, label: 'Teléfono', value: client.phone!),
          if (client.phone != null && client.email != null)
            const Divider(height: 1, indent: 16, endIndent: 16),
          if (client.email != null)
            _ContactRow(icon: Icons.mail_outline, label: 'Correo', value: client.email!),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: BarboraTheme.titanium),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13, color: BarboraTheme.textMuted)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentAppointments extends StatelessWidget {
  const _RecentAppointments({required this.detail, required this.symbol});

  final ClientDetail detail;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final appointments = detail.recentAppointments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Row(
            children: [
              const Text(
                'ÚLTIMAS CITAS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: BarboraTheme.textMuted,
                ),
              ),
              if (detail.stats.upcoming > 0) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: BarboraTheme.copper.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${detail.stats.upcoming} por venir',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: BarboraTheme.copperDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (appointments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Todavía no tiene citas registradas.',
                style: TextStyle(color: BarboraTheme.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          for (final a in appointments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppointmentTile(
                appointment: a,
                showBarber: true,
                currencySymbol: symbol,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppointmentDetailScreen(appointmentId: a.id),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

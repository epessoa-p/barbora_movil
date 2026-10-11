import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/barber.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'barber_edit_screen.dart';

/// Gestión de barberos: lista (activos e inactivos), alta y edición.
class BarbersScreen extends StatefulWidget {
  const BarbersScreen({super.key});

  @override
  State<BarbersScreen> createState() => _BarbersScreenState();
}

class _BarbersScreenState extends State<BarbersScreen> {
  List<Barber> _barbers = const [];
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
      final body = await context.read<ApiClient>().get('/personal');
      if (!mounted) return;
      setState(() => _barbers = (body['data'] as List? ?? [])
          .map((e) => Barber.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canCreate => context.read<AuthController>().me?.can('personal.create') ?? false;
  bool get _canEdit => context.read<AuthController>().me?.can('personal.edit') ?? false;

  Future<void> _open({Barber? barber}) async {
    final saved = await Navigator.of(context).push<Barber>(
      MaterialPageRoute(builder: (_) => BarberEditScreen(barber: barber)),
    );

    if (saved == null || !mounted) return;

    setState(() {
      final i = _barbers.indexWhere((b) => b.id == saved.id);
      if (i >= 0) {
        _barbers[i] = saved;
      } else {
        _barbers = [..._barbers, saved]..sort((a, b) => a.fullName.compareTo(b.fullName));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${saved.fullName} guardado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body(),
      floatingActionButton: _canCreate && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo barbero', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    if (_barbers.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 100),
            EmptyView(
              icon: Icons.content_cut,
              title: 'Sin barberos',
              subtitle: 'Agrega al personal con el botón de abajo.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: _barbers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _BarberTile(
          barber: _barbers[i],
          onTap: _canEdit ? () => _open(barber: _barbers[i]) : null,
        ),
      ),
    );
  }
}

class _BarberTile extends StatelessWidget {
  const _BarberTile({required this.barber, required this.onTap});

  final Barber barber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(barber.agendaColor) ?? BarboraTheme.titanium;

    final row = Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: color.withValues(alpha: .18),
            foregroundImage: barber.photoUrl == null ? null : NetworkImage(barber.photoUrl!),
            child: Text(
              barber.initials,
              style: TextStyle(fontWeight: FontWeight.w800, color: BarboraTheme.ink, fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        barber.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                    ),
                    if (!barber.active) ...[
                      const SizedBox(width: 6),
                      _Tag(text: 'Inactivo', color: BarboraTheme.textMuted),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    barber.cargo ?? 'Sin cargo',
                    if (barber.specialty != null && barber.specialty!.isNotEmpty) barber.specialty!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (barber.bookable)
            const Icon(Icons.event_available, size: 18, color: Color(0xFF16A34A))
          else
            const Icon(Icons.event_busy_outlined, size: 18, color: BarboraTheme.titanium),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
          ],
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: BarboraTheme.canvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BarboraTheme.border),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

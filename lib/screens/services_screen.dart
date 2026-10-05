import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/service.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'service_edit_screen.dart';

/// El catálogo de servicios.
///
/// Para consultar precio y duración sin tener que entrar al cobro o a una cita.
/// Se crean y editan desde el panel web; aquí solo se miran.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Service> _services = const [];
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
      final body = await context.read<ApiClient>().get('/services');

      if (!mounted) return;
      setState(() => _services = (body['data'] as List? ?? [])
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Agrupa por categoría, conservando el orden en que llegaron (ya vienen
  /// ordenados del servidor). Lo sin categoría va al final, bajo «Otros».
  Map<String, List<Service>> get _byCategory {
    final groups = <String, List<Service>>{};
    for (final s in _services) {
      groups.putIfAbsent(s.category ?? 'Otros', () => []).add(s);
    }
    return groups;
  }

  bool get _canEdit => context.read<AuthController>().me?.can('services.edit') ?? false;

  Future<void> _edit(Service service) async {
    final updated = await Navigator.of(context).push<Service>(
      MaterialPageRoute(builder: (_) => ServiceEditScreen(service: service)),
    );

    if (updated == null || !mounted) return;

    // Se reemplaza en sitio para no recargar toda la lista.
    setState(() {
      final i = _services.indexWhere((s) => s.id == updated.id);
      if (i >= 0) _services[i] = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.name} actualizado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }

    if (_services.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyView(
              icon: Icons.design_services_outlined,
              title: 'Sin servicios',
              subtitle: 'Crea los servicios desde el panel web y aparecerán aquí.',
            ),
          ],
        ),
      );
    }

    final groups = _byCategory;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
              child: Row(
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: BarboraTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.length}',
                    style: const TextStyle(fontSize: 11.5, color: BarboraTheme.titanium),
                  ),
                ],
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (final (i, s) in entry.value.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _ServiceRow(
                      service: s,
                      symbol: symbol,
                      onEdit: _canEdit ? () => _edit(s) : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.symbol, this.onEdit});

  final Service service;
  final String symbol;

  /// Null si el usuario no puede editar (la fila entonces no es tocable).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        service.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                    ),
                    if (!service.active) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: BarboraTheme.canvas,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: BarboraTheme.border),
                        ),
                        child: const Text('Inactivo',
                            style: TextStyle(fontSize: 10, color: BarboraTheme.textMuted, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 13, color: BarboraTheme.titanium),
                    const SizedBox(width: 4),
                    Text(
                      '${service.durationMinutes} min',
                      style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                    ),
                  ],
                ),
                if (service.description != null && service.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    service.description!,
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$symbol ${service.price.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: BarboraTheme.titanium, size: 20),
          ],
        ],
      ),
    );

    if (onEdit == null) return row;

    return InkWell(onTap: onEdit, child: row);
  }
}

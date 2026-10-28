import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/appointment.dart';
import '../models/block_options.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'block_edit_screen.dart';

/// Bloqueos de agenda: vacaciones, feriados, descansos. Próximos o pasados,
/// con alta, edición y baja según permisos.
class BlocksScreen extends StatefulWidget {
  const BlocksScreen({super.key});

  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  List<AgendaBlock> _blocks = const [];
  BlockOptions _options = const BlockOptions();
  bool _past = false;
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
      final body = await context.read<ApiClient>().get(
        '/agenda-blocks',
        query: {if (_past) 'scope': 'pasados'},
      );
      if (!mounted) return;
      setState(() {
        _blocks = (body['data'] as List? ?? [])
            .map((e) => AgendaBlock.fromJson(e as Map<String, dynamic>))
            .toList();
        _options = BlockOptions.fromJson(body);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _can(String permission) => context.read<AuthController>().me?.can(permission) ?? false;

  Future<void> _open({AgendaBlock? block}) async {
    final result = await Navigator.of(context).push<BlockResult>(
      MaterialPageRoute(builder: (_) => BlockEditScreen(block: block, options: _options)),
    );

    if (result == null || !mounted) return;

    // Si avisa de citas que caen dentro, se deja más tiempo en pantalla para
    // que dé tiempo a leerlo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: Duration(seconds: result.warn ? 8 : 3),
        backgroundColor: result.warn ? const Color(0xFF92400E) : null,
      ),
    );

    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Próximos')),
                  ButtonSegment(value: true, label: Text('Pasados')),
                ],
                selected: {_past},
                onSelectionChanged: (s) {
                  setState(() => _past = s.first);
                  _load();
                },
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: _can('agenda_blocks.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo bloqueo', style: TextStyle(fontWeight: FontWeight.w700)),
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

    if (_blocks.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyView(
              icon: Icons.event_available_outlined,
              title: _past ? 'Sin bloqueos pasados' : 'Sin bloqueos próximos',
              subtitle: _past
                  ? 'Aquí quedan las vacaciones y feriados ya cumplidos.'
                  : 'Vacaciones, feriados o descansos: lo que se agregue aquí no se podrá reservar.',
            ),
          ],
        ),
      );
    }

    final canEdit = _can('agenda_blocks.edit');

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: _blocks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _BlockTile(
          block: _blocks[i],
          onTap: canEdit ? () => _open(block: _blocks[i]) : null,
        ),
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block, required this.onTap});

  final AgendaBlock block;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = reasonColor(block.reason);

    final row = Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(reasonIcon(block.reason), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  [block.scope, if (block.branch != null) block.branch!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  block.rangeLabel ?? '',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              block.reasonLabel,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
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
}

/// Mismos colores que la web (AgendaBlock::reasonColor).
Color reasonColor(String reason) => switch (reason) {
      'vacaciones' => const Color(0xFF0891B2),
      'feriado' => const Color(0xFFDC2626),
      'descanso' => const Color(0xFF64748B),
      'permiso' => const Color(0xFFD97706),
      _ => BarboraTheme.ink,
    };

IconData reasonIcon(String reason) => switch (reason) {
      'vacaciones' => Icons.beach_access_outlined,
      'feriado' => Icons.flag_outlined,
      'descanso' => Icons.free_breakfast_outlined,
      'permiso' => Icons.assignment_ind_outlined,
      _ => Icons.do_not_disturb_on_outlined,
    };

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

class ManualTopic {
  const ManualTopic({required this.title, required this.steps, this.note});

  final String title;
  final List<String> steps;
  final String? note;

  factory ManualTopic.fromJson(Map<String, dynamic> j) => ManualTopic(
        title: j['title'] as String? ?? '',
        steps: (j['steps'] as List? ?? []).map((e) => '$e').toList(),
        note: j['note'] as String?,
      );

  String get searchText => _plain([title, ...steps, note ?? ''].join(' '));
}

class ManualSection {
  const ManualSection({required this.key, required this.title, required this.intro, this.where, required this.topics});

  final String key;
  final String title;
  final String intro;
  final String? where;
  final List<ManualTopic> topics;

  factory ManualSection.fromJson(Map<String, dynamic> j) => ManualSection(
        key: j['key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        intro: j['intro'] as String? ?? '',
        where: j['where'] as String?,
        topics: (j['topics'] as List? ?? []).map((e) => ManualTopic.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Para buscar sin importar mayúsculas ni tildes.
String _plain(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  var out = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}

/// El manual de usuario: una sección por módulo, con buscador. El contenido
/// viene de `GET /manual`, el mismo de la web, con lo que este usuario puede usar.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key});

  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  List<ManualSection> _sections = const [];
  ApiException? _error;
  bool _loading = true;
  String _query = '';

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
      final body = await context.read<ApiClient>().get('/manual');
      if (!mounted) return;
      setState(() {
        _sections = (body['data'] as List? ?? []).map((e) => ManualSection.fromJson(e as Map<String, dynamic>)).toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Con búsqueda: solo los temas que la contienen (o toda la sección si está
  /// en su título).
  List<ManualSection> get _visible {
    final q = _plain(_query.trim());
    if (q.isEmpty) return _sections;

    return [
      for (final s in _sections)
        if (_plain(s.title).contains(q))
          s
        else if (s.topics.where((t) => t.searchText.contains(q)).toList() case final topics when topics.isNotEmpty)
          ManualSection(key: s.key, title: s.title, intro: s.intro, where: s.where, topics: topics),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final visible = _visible;

    return AdminPage(
      title: 'Manual de usuario',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Buscar: caja, comisión, fotos…',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Solo aparece lo que tu plan y tus permisos incluyen.',
                      style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                    ),
                    const SizedBox(height: 10),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Center(
                          child: Text('No encontramos nada con esa palabra.', style: TextStyle(color: BarboraTheme.textMuted)),
                        ),
                      ),
                    for (final s in visible)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          // Con otra clave al buscar, para que se abra sola.
                          key: PageStorageKey('${s.key}-$searching'),
                          initiallyExpanded: searching,
                          shape: const Border(),
                          title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          children: [
                            Text(s.intro),
                            if (s.where != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.place_outlined, size: 15, color: BarboraTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Dónde: ${s.where}',
                                      style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            for (final t in s.topics) _TopicView(topic: t),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _TopicView extends StatelessWidget {
  const _TopicView({required this.topic});

  final ManualTopic topic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (i, step) in topic.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}.', style: const TextStyle(color: BarboraTheme.textMuted)),
                  ),
                  Expanded(child: Text(step, style: const TextStyle(height: 1.35))),
                ],
              ),
            ),
          if (topic.note != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BarboraTheme.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BarboraTheme.border),
              ),
              child: Text(topic.note!, style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

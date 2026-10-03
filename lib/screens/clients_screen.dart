import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/client.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';
import 'client_detail_screen.dart';

/// La sección de clientes: buscar y abrir su ficha.
///
/// La lista se pagina y se busca en el servidor: una barbería con años puede
/// tener miles de clientes y el teléfono no los descarga todos.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<Client> _clients = const [];
  bool _loading = true;
  ApiException? _error;

  /// Descarta respuestas de búsquedas que ya no son la última.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(term));
  }

  Future<void> _load(String term) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/clients', query: {
        if (term.trim().isNotEmpty) 'q': term.trim(),
        'per_page': 30,
      });

      if (!mounted || request != _request) return;
      setState(() => _clients = (body['data'] as List? ?? [])
          .map((e) => Client.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error = e);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _openDetail(Client client) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: client.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nombre, teléfono o documento',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _search.clear();
                        _load('');
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    if (_loading && _clients.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: () => _load(_search.text));
    }

    if (_clients.isEmpty) {
      return RefreshIndicator(
        color: BarboraTheme.copper,
        onRefresh: () => _load(_search.text),
        child: ListView(
          children: [
            const SizedBox(height: 100),
            EmptyView(
              icon: Icons.people_outline,
              title: _search.text.isEmpty ? 'Sin clientes' : 'Sin resultados',
              subtitle: _search.text.isEmpty
                  ? 'Los clientes se dan de alta al reservar o cobrar.'
                  : 'Prueba con otro nombre o con el teléfono.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: () => _load(_search.text),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: _clients.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, i) => _ClientRow(client: _clients[i], onTap: () => _openDetail(_clients[i])),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.onTap});

  final Client client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [client.phone, client.documentNumber].whereType<String>().join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: BarboraTheme.canvas,
                child: Text(
                  client.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: BarboraTheme.ink,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (client.allergies != null && client.allergies!.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.warning_amber_rounded, size: 17, color: Color(0xFFB45309)),
                ),
              const Icon(Icons.chevron_right, color: BarboraTheme.titanium),
            ],
          ),
        ),
      ),
    );
  }
}

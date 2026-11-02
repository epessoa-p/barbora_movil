import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/admin.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/error_view.dart';

/// El catálogo público: una página con los servicios (y, si se quiere, los
/// productos) para compartir por enlace o poner con un QR en la puerta.
///
/// El PDF y el afiche imprimible se abren en el navegador: desde ahí se
/// guardan como PDF o se imprimen.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  CatalogSettings? _catalog;
  ApiException? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canEdit => context.read<AuthController>().me?.can('settings.edit') ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/admin/catalog');
      if (!mounted) return;
      setState(() => _catalog = CatalogSettings.fromJson(body['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function(ApiClient api) call) async {
    setState(() => _saving = true);
    try {
      final res = await call(context.read<ApiClient>());
      if (!mounted) return;
      setState(() => _catalog = CatalogSettings.fromJson(res['data'] as Map<String, dynamic>));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Guardado.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update({bool? enabled, bool? showProducts}) => _run((api) => api.put('/admin/catalog', body: {
        'enabled': ?enabled,
        'show_products': ?showProducts,
      }));

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Generar un enlace nuevo?'),
        content: const Text('El enlace actual y los QR ya impresos dejarán de funcionar.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Generar')),
        ],
      ),
    );
    if (ok == true) await _run((api) => api.post('/admin/catalog/regenerate'));
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el navegador.')));
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final c = _catalog!;
    final canEdit = _canEdit;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: c.enabled,
                  onChanged: canEdit && !_saving ? (v) => _update(enabled: v) : null,
                  activeThumbColor: BarboraTheme.copper,
                  title: const Text('Publicar el catálogo', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(c.enabled
                      ? 'Cualquiera con el enlace o el QR lo ve.'
                      : 'Apagado: el enlace y el QR no muestran nada.'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: c.showProducts,
                  onChanged: canEdit && !_saving ? (v) => _update(showProducts: v) : null,
                  activeThumbColor: BarboraTheme.copper,
                  title: const Text('Mostrar también los productos', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Los ${c.servicesCount} servicios activos salen siempre.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Con el catálogo apagado el QR se ve tenue: todavía no lleva a nada.
                  Opacity(
                    opacity: c.enabled ? 1 : .35,
                    child: QrImageView(
                      data: c.url,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    c.url,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                  if (!c.enabled) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Publica el catálogo para que el enlace funcione.',
                      style: TextStyle(fontSize: 12.5, color: BarboraTheme.copperDark, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copy(c.url),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar enlace'),
                      ),
                      OutlinedButton.icon(
                        onPressed: c.enabled ? () => _open(c.url) : null,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Ver / PDF'),
                      ),
                      FilledButton.icon(
                        onPressed: c.enabled ? () => _open(c.posterUrl) : null,
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('Afiche con QR'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'El catálogo y el afiche se abren en el navegador: desde ahí se guardan como PDF, '
                    'se imprimen o se descarga el QR.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),

          if (canEdit) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _regenerate,
              style: TextButton.styleFrom(foregroundColor: BarboraTheme.copperDark),
              icon: const Icon(Icons.autorenew, size: 18),
              label: const Text('Generar un enlace nuevo'),
            ),
          ],
        ],
      ),
    );
  }
}

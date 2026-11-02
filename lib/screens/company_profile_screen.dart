import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/admin.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

/// «Mi empresa»: nombre, contacto y pie del comprobante. Sin `settings.edit`
/// se ve pero no se guarda. El logo se cambia desde la web, y el NIT no se
/// edita (con él se verifica a quien pide soporte).
class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _footer = TextEditingController();

  CompanyProfile? _company;
  ApiException? _loadError;
  bool _loading = true;

  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _footer.dispose();
    super.dispose();
  }

  bool get _canEdit => context.read<AuthController>().me?.can('settings.edit') ?? false;

  void _fill(CompanyProfile c) {
    _company = c;
    _name.text = c.name;
    _address.text = c.address ?? '';
    _phone.text = c.phone ?? '';
    _email.text = c.email ?? '';
    _footer.text = c.receiptFooter ?? '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/admin/company');
      if (!mounted) return;
      setState(() => _fill(CompanyProfile.fromJson(body['data'] as Map<String, dynamic>)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    try {
      final res = await context.read<ApiClient>().put('/admin/company', body: {
        'name': upperName(_name.text),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'receipt_footer': _footer.text.trim(),
      });
      if (!mounted) return;

      setState(() => _fill(CompanyProfile.fromJson(res['data'] as Map<String, dynamic>)));

      // El nombre sale en la barra y en el menú, y los datos en el comprobante.
      await context.read<AuthController>().refreshMe();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos de la barbería actualizados.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in ['name', 'address', 'phone', 'email', 'receipt_footer']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Mi empresa',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : _form(),
    );
  }

  Widget _form() {
    final c = _company!;
    final canEdit = _canEdit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: BarboraTheme.copper.withValues(alpha: .15),
              foregroundImage: c.logoUrl == null ? null : NetworkImage(c.logoUrl!),
              child: const Icon(Icons.storefront, color: BarboraTheme.copperDark),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.taxId != null && c.taxId!.isNotEmpty)
                    Text('${c.taxIdLabel ?? 'NIT'}: ${c.taxId}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text(
                    'El logo se cambia desde la web.',
                    style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          enabled: canEdit,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseFormatter()],
          decoration: InputDecoration(labelText: 'Nombre de la barbería', errorText: _errors['name']),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _address,
          enabled: canEdit,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Dirección', errorText: _errors['address']),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phone,
          enabled: canEdit,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: 'Teléfono', errorText: _errors['phone']),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          enabled: canEdit,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'Correo', errorText: _errors['email']),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _footer,
          enabled: canEdit,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Pie del comprobante',
            hintText: '¡Gracias por tu visita!',
            errorText: _errors['receipt_footer'],
          ),
        ),
        AdminFormError(_error),
        if (canEdit) ...[
          const SizedBox(height: 20),
          AdminSaveButton(saving: _saving, label: 'Guardar cambios', onPressed: _save),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/admin.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

/// «Mi empresa»: logo, nombre, contacto y pie del comprobante. Sin
/// `settings.edit` se ve pero no se guarda. El NIT no se edita (con él se
/// verifica a quien pide soporte).
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
  bool _uploadingLogo = false;
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
    _cashCountMode = c.cashCountMode;
  }

  /// Cómo se cierra caja: «total» o «denominations».
  String _cashCountMode = 'total';

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
        'cash_count_mode': _cashCountMode,
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
        for (final f in ['name', 'address', 'phone', 'email', 'receipt_footer', 'cash_count_mode']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Elige una imagen de la galería y la sube como logo. Se reduce en el
  /// teléfono para no pasar del límite de 1 MB del servidor.
  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    await _sendLogo({}, picked.path);
  }

  Future<void> _removeLogo() => _sendLogo({'remove_logo': '1'}, null);

  Future<void> _sendLogo(Map<String, String> fields, String? path) async {
    setState(() => _uploadingLogo = true);

    try {
      final res = await context.read<ApiClient>().upload(
        '/admin/company/logo',
        fields: fields,
        fileField: path == null ? null : 'logo',
        filePath: path,
      );
      if (!mounted) return;

      setState(() => _company = CompanyProfile.fromJson(res['data'] as Map<String, dynamic>));

      // El logo sale en el menú lateral y en el comprobante.
      await context.read<AuthController>().refreshMe();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] as String? ?? 'Logo actualizado.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.firstErrorFor('logo') ?? e.message),
        backgroundColor: BarboraTheme.copperDark,
      ));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
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
                  if (canEdit)
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: _uploadingLogo ? null : _pickLogo,
                          icon: _uploadingLogo
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: BarboraTheme.copper),
                                )
                              : const Icon(Icons.image_outlined, size: 18),
                          label: Text(c.logoUrl == null ? 'Subir logo' : 'Cambiar logo'),
                        ),
                        if (c.logoUrl != null)
                          TextButton(
                            onPressed: _uploadingLogo ? null : _removeLogo,
                            style: TextButton.styleFrom(foregroundColor: BarboraTheme.textMuted),
                            child: const Text('Quitar'),
                          ),
                      ],
                    ),
                  const Text(
                    'PNG, JPG o WEBP, de hasta 1 MB.',
                    style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted),
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
        const SizedBox(height: 22),
        const Text('Cierre de caja', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        const Text(
          'Cómo se cuenta el efectivo al cerrar un turno. Solo se arquea el efectivo: '
          'QR, tarjeta y transferencias están en el banco.',
          style: TextStyle(fontSize: 12.5, color: BarboraTheme.textMuted),
        ),
        RadioGroup<String>(
          groupValue: _cashCountMode,
          onChanged: (v) {
            if (canEdit && v != null) setState(() => _cashCountMode = v);
          },
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'total',
                enabled: canEdit,
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo el total contado'),
                subtitle: const Text('Se escribe cuánto efectivo hay en el cajón.'),
              ),
              RadioListTile<String>(
                value: 'denominations',
                enabled: canEdit,
                contentPadding: EdgeInsets.zero,
                title: const Text('Contar billetes y monedas'),
                subtitle: const Text('Se indica cuántos hay de cada valor y el total se calcula solo.'),
              ),
            ],
          ),
        ),
        AdminFormError(_errors['cash_count_mode'] ?? _error),
        if (canEdit) ...[
          const SizedBox(height: 20),
          AdminSaveButton(saving: _saving, label: 'Guardar cambios', onPressed: _save),
        ],
      ],
    );
  }
}

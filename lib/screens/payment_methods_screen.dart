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

/// Métodos de pago de la barbería. Lo importante es «cuenta como efectivo»:
/// solo eso entra en el arqueo, porque es lo único que está en el cajón.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<PaymentMethodItem> _methods = const [];
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
      final body = await context.read<ApiClient>().get('/admin/payment-methods');
      if (!mounted) return;
      setState(() => _methods = (body['data'] as List? ?? [])
          .map((e) => PaymentMethodItem.fromJson(e as Map<String, dynamic>))
          .toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canEdit => context.read<AuthController>().me?.can('settings.edit') ?? false;

  Future<void> _open({PaymentMethodItem? method}) async {
    final saved = await Navigator.of(context).push<PaymentMethodItem>(
      MaterialPageRoute(builder: (_) => PaymentMethodEditScreen(method: method)),
    );

    if (saved == null || !mounted) return;

    // El cobro y el arqueo leen los métodos de /me: se refresca para que
    // el cambio se vea ya, sin cerrar sesión.
    context.read<AuthController>().refreshMe();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${saved.name} guardado.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Métodos de pago'),
      ),
      body: _body(),
      floatingActionButton: _canEdit && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo método', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    final canEdit = _canEdit;

    return RefreshIndicator(
      color: BarboraTheme.copper,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          for (final m in _methods)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminTile(
                icon: m.countsAsCash ? Icons.payments_outlined : Icons.credit_card,
                title: m.name,
                dimmed: !m.active,
                tags: [
                  if (m.countsAsCash) const AdminTag('Efectivo', color: Color(0xFF16A34A)),
                  if (m.requiresReference) const AdminTag('Pide referencia'),
                  if (!m.active) const AdminTag('Inactivo'),
                ],
                onTap: canEdit ? () => _open(method: m) : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Alta o edición de un método de pago. Devuelve el guardado, o null.
class PaymentMethodEditScreen extends StatefulWidget {
  const PaymentMethodEditScreen({super.key, this.method});

  final PaymentMethodItem? method;

  @override
  State<PaymentMethodEditScreen> createState() => _PaymentMethodEditScreenState();
}

class _PaymentMethodEditScreenState extends State<PaymentMethodEditScreen> {
  late final _name = TextEditingController(text: widget.method?.name ?? '');
  late bool _countsAsCash = widget.method?.countsAsCash ?? false;
  late bool _requiresReference = widget.method?.requiresReference ?? false;
  late bool _active = widget.method?.active ?? true;

  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors.clear();
      _error = null;
    });

    final body = {
      'name': upperName(_name.text),
      'counts_as_cash': _countsAsCash ? 1 : 0,
      'requires_reference': _requiresReference ? 1 : 0,
      'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.method == null
          ? await api.post('/admin/payment-methods', body: body)
          : await api.put('/admin/payment-methods/${widget.method!.id}', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(PaymentMethodItem.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final f in body.keys) {
          _errors[f] = e.firstErrorFor(f);
        }
        _error = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fieldError(String field) => _errors[field] == null
      ? const SizedBox.shrink()
      : Text(_errors[field]!, style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 12.5));

  @override
  Widget build(BuildContext context) {
    final editing = widget.method != null;

    return AdminPage(
      title: editing ? 'Editar método' : 'Nuevo método de pago',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej.: TIGO MONEY, QR BANCO…',
              errorText: _errors['name'],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _countsAsCash,
            onChanged: (v) => setState(() => _countsAsCash = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Cuenta como efectivo'),
            subtitle: const Text('Entra en el arqueo: es dinero que queda en el cajón.'),
          ),
          _fieldError('counts_as_cash'),
          SwitchListTile(
            value: _requiresReference,
            onChanged: (v) => setState(() => _requiresReference = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pide referencia'),
            subtitle: const Text('Al cobrar se anota el número de la operación.'),
          ),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeThumbColor: BarboraTheme.copper,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            subtitle: const Text('Un método inactivo deja de ofrecerse al cobrar.'),
          ),
          AdminFormError(_error),
          const SizedBox(height: 20),
          AdminSaveButton(
            saving: _saving,
            label: editing ? 'Guardar cambios' : 'Crear método',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

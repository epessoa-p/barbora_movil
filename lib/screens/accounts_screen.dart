import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/upper_case.dart';
import '../models/finance.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/error_view.dart';

IconData accountIcon(String type) => switch (type) {
      'capital' => Icons.savings_outlined,
      'caja_chica' => Icons.account_balance_wallet_outlined,
      'banco' => Icons.account_balance_outlined,
      'billetera' => Icons.phone_iphone,
      _ => Icons.payments_outlined,
    };

/// Las cuentas de la barbería: capital, caja chica, banco… con su saldo.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<FinanceAccount> _accounts = const [];
  Map<String, String> _types = const {};
  double _total = 0;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _can(String p) => context.read<AuthController>().me?.can(p) ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/finance/accounts');
      if (!mounted) return;
      setState(() {
        _accounts = (body['data'] as List? ?? []).map((e) => FinanceAccount.fromJson(e as Map<String, dynamic>)).toList();
        _total = (body['total'] as num?)?.toDouble() ?? 0;
        _types = (body['types'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v'));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<FinanceAccount>(
      MaterialPageRoute(builder: (_) => AccountEditScreen(types: _types)),
    );
    if (saved != null && mounted) _load();
  }

  Future<void> _open(FinanceAccount a) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountDetailScreen(account: a, types: _types)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: BarboraTheme.copper,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(gradient: BarboraTheme.inkGradient, borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SALDO DE LAS CUENTAS',
                                style: TextStyle(color: BarboraTheme.titanium.withValues(alpha: .8), fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('$symbol ${_total.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 50),
                          child: EmptyView(
                            icon: Icons.account_balance_outlined,
                            title: 'Sin cuentas',
                            subtitle: 'Crea el capital, la caja chica o tu cuenta de banco.',
                          ),
                        ),
                      for (final a in _accounts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AdminTile(
                            icon: accountIcon(a.type),
                            title: a.name,
                            dimmed: !a.active,
                            tags: [AdminTag(a.typeLabel), if (!a.active) const AdminTag('Inactiva')],
                            subtitle: '$symbol ${a.balance.toStringAsFixed(2)}'
                                '${a.bankName != null ? ' · ${a.bankName}' : ''}${a.branch != null ? ' · ${a.branch}' : ''}',
                            onTap: () => _open(a),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: _can('accounts.create') && !_loading && _error == null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _new,
              backgroundColor: BarboraTheme.copper,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva cuenta', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

/// Una cuenta: su saldo, sus movimientos, y registrar ingreso, egreso o
/// transferencia.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.account, required this.types});

  final FinanceAccount account;
  final Map<String, String> types;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late FinanceAccount _account = widget.account;
  List<FinanceMovement> _movements = const [];
  List<Map<String, dynamic>> _others = const [];
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _can(String p) => context.read<AuthController>().me?.can(p) ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await context.read<ApiClient>().get('/finance/accounts/${_account.id}/movements');
      if (!mounted) return;
      setState(() {
        _account = FinanceAccount.fromJson(body['account'] as Map<String, dynamic>);
        _movements = (body['data'] as List? ?? []).map((e) => FinanceMovement.fromJson(e as Map<String, dynamic>)).toList();
        _others = (body['other_accounts'] as List? ?? []).cast<Map<String, dynamic>>();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move({required bool transfer}) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MovementSheet(account: _account, transfer: transfer, others: _others),
    );
    if (done == true) _load();
  }

  Future<void> _cancel(FinanceMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Anular el movimiento?'),
        content: const Text('Se registra el movimiento contrario y el saldo se corrige.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await context.read<ApiClient>().patch('/finance/movements/${m.id}/cancel');
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<FinanceAccount>(
      MaterialPageRoute(builder: (_) => AccountEditScreen(account: _account, types: widget.types)),
    );
    if (saved != null && mounted) setState(() => _account = saved);
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    final canMove = _can('account_movements.create') && _account.active;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BarboraTheme.inkSoft,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_account.name),
        actions: [
          if (_can('accounts.edit'))
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BarboraTheme.copper))
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: BarboraTheme.copper,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_account.typeLabel, style: const TextStyle(color: BarboraTheme.textMuted)),
                              Text('$symbol ${_account.balance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: _account.balance < 0 ? BarboraTheme.copperDark : BarboraTheme.ink,
                                  )),
                              if (canMove) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _move(transfer: false),
                                        icon: const Icon(Icons.swap_vert, size: 18),
                                        label: const Text('Ingreso / egreso'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _others.isEmpty ? null : () => _move(transfer: true),
                                        icon: const Icon(Icons.compare_arrows, size: 18),
                                        label: const Text('Transferir'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_movements.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: EmptyView(icon: Icons.history, title: 'Sin movimientos'),
                        ),
                      for (final m in _movements)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onLongPress: m.canCancel && _can('account_movements.delete') ? () => _cancel(m) : null,
                            leading: Icon(
                              m.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                              color: m.cancelled ? BarboraTheme.titanium : (m.isIncome ? const Color(0xFF16A34A) : BarboraTheme.copperDark),
                            ),
                            title: Text(
                              m.concept,
                              style: TextStyle(decoration: m.cancelled ? TextDecoration.lineThrough : null, fontSize: 14),
                            ),
                            subtitle: Text([shortDate(m.occurredOn), m.originLabel, if (m.cancelled) 'Anulado'].join(' · ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${m.isIncome ? '+' : '−'}$symbol ${m.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: m.isIncome ? const Color(0xFF16A34A) : BarboraTheme.copperDark,
                                    )),
                                Text('$symbol ${m.balanceAfter.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11.5, color: BarboraTheme.textMuted)),
                              ],
                            ),
                          ),
                        ),
                      if (_movements.any((m) => m.canCancel) && _can('account_movements.delete'))
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Mantén pulsado un movimiento manual para anularlo.',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: BarboraTheme.textMuted)),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Ingreso / egreso, o transferencia a otra cuenta.
class _MovementSheet extends StatefulWidget {
  const _MovementSheet({required this.account, required this.transfer, required this.others});

  final FinanceAccount account;
  final bool transfer;
  final List<Map<String, dynamic>> others;

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  String _type = 'ingreso';
  int? _to;
  bool _busy = false;
  final _errors = <String, String?>{};

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors.clear();
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final api = context.read<ApiClient>();
      final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
      final res = widget.transfer
          ? await api.post('/finance/accounts/${widget.account.id}/transfer', body: {
              'to_account_id': _to, 'amount': amount, 'concept': _concept.text.trim(),
            })
          : await api.post('/finance/accounts/${widget.account.id}/movements', body: {
              'type': _type, 'amount': amount, 'concept': _concept.text.trim(),
            });
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(res['message'] as String? ?? 'Registrado.')));
    } on ApiException catch (e) {
      setState(() {
        for (final f in ['amount', 'concept', 'to_account_id', 'type']) {
          _errors[f] = e.firstErrorFor(f);
        }
        _errors['error'] = e.errors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<AuthController>().company?.symbol ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.transfer ? 'Transferir desde ${widget.account.name}' : 'Movimiento en ${widget.account.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (widget.transfer)
            DropdownButtonFormField<int>(
              initialValue: _to,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'A la cuenta', errorText: _errors['to_account_id']),
              items: [for (final o in widget.others) DropdownMenuItem(value: o['id'] as int, child: Text('${o['name']}'))],
              onChanged: (v) => setState(() => _to = v),
            )
          else
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ingreso', label: Text('Ingreso'), icon: Icon(Icons.add)),
                ButtonSegment(value: 'egreso', label: Text('Egreso'), icon: Icon(Icons.remove)),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Importe', prefixText: '$symbol ', errorText: _errors['amount']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _concept,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: widget.transfer ? 'Concepto (opcional)' : 'Concepto',
              hintText: widget.transfer ? null : 'Aporte de capital, depósito, retiro…',
              errorText: _errors['concept'],
            ),
          ),
          AdminFormError(_errors['error']),
          const SizedBox(height: 16),
          AdminSaveButton(saving: _busy, label: widget.transfer ? 'Transferir' : 'Registrar', onPressed: _save),
        ],
      ),
    );
  }
}

/// Alta o edición de una cuenta.
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, this.account, required this.types});

  final FinanceAccount? account;
  final Map<String, String> types;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _bank = TextEditingController(text: widget.account?.bankName ?? '');
  late final _number = TextEditingController(text: widget.account?.accountNumber ?? '');
  final _opening = TextEditingController();
  late String _type = widget.account?.type ?? 'caja_chica';
  late bool _active = widget.account?.active ?? true;
  bool _saving = false;
  final _errors = <String, String?>{};
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _bank, _number, _opening]) {
      c.dispose();
    }
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
      'type': _type,
      'bank_name': _bank.text.trim(),
      'account_number': _number.text.trim(),
      if (widget.account == null) 'opening_balance': double.tryParse(_opening.text.replaceAll(',', '.')) ?? 0,
      if (widget.account != null) 'active': _active ? 1 : 0,
    };

    try {
      final api = context.read<ApiClient>();
      final res = widget.account == null
          ? await api.post('/finance/accounts', body: body)
          : await api.put('/finance/accounts/${widget.account!.id}', body: body);
      if (!mounted) return;
      Navigator.of(context).pop(FinanceAccount.fromJson(res['data'] as Map<String, dynamic>));
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

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AuthController>().company?.symbol ?? '';
    final types = widget.types.isEmpty
        ? const {'capital': 'Capital', 'caja_chica': 'Caja chica', 'banco': 'Banco', 'billetera': 'Billetera digital', 'otro': 'Otra'}
        : widget.types;

    return AdminPage(
      title: widget.account == null ? 'Nueva cuenta' : 'Editar cuenta',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseFormatter()],
            decoration: InputDecoration(labelText: 'Nombre', hintText: 'CAJA CHICA, CAPITAL, BANCO…', errorText: _errors['name']),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(labelText: 'Tipo', errorText: _errors['type']),
            items: [for (final t in types.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 14),
          TextField(controller: _bank, decoration: const InputDecoration(labelText: 'Banco o billetera (opcional)')),
          const SizedBox(height: 14),
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'Nº de cuenta (opcional)')),
          if (widget.account == null) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Saldo inicial',
                prefixText: '$symbol ',
                helperText: 'Lo que hay hoy en la cuenta. Entra como primer movimiento.',
                errorText: _errors['opening_balance'],
              ),
            ),
          ] else
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeThumbColor: BarboraTheme.copper,
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
            ),
          AdminFormError(_error),
          const SizedBox(height: 20),
          AdminSaveButton(saving: _saving, label: widget.account == null ? 'Crear cuenta' : 'Guardar cambios', onPressed: _save),
        ],
      ),
    );
  }
}

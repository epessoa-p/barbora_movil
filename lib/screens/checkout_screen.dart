import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/cash.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/service.dart';
import '../state/auth_controller.dart';
import '../state/cash_controller.dart';
import '../state/checkout_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/client_picker.dart';
import '../widgets/error_view.dart';
import 'receipt_screen.dart';

/// Armar la comanda y cobrar.
///
/// El total sale de los precios del catálogo que ya trajimos, pero **el que
/// manda es el del servidor**: al cobrar se envían solo el id y la cantidad.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  List<Service> _services = const [];
  List<Product> _products = const [];
  ApiException? _error;
  bool _loading = true;
  bool _showProducts = false;

  /// Si el plan no incluye inventario, la pestaña de productos ni aparece.
  bool get _hasInventory =>
      context.read<AuthController>().me?.hasModule('inventario') ?? false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    // Barberos para atribuir cada servicio (comisiones); no bloquea el cobro.
    context.read<CheckoutController>().loadStaff();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = context.read<ApiClient>();

    try {
      final body = await api.get('/services');

      _services = (body['data'] as List? ?? [])
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList();

      // Los productos son opcionales: una barbería sin inventario contratado
      // vende solo servicios, y eso no es un error.
      if (_hasInventory) {
        try {
          final products = await api.get('/products');

          _products = (products['data'] as List? ?? [])
              .map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList();
        } on ApiException {
          _products = const [];
        }
      }

      setState(() {});
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ¿Se puede elegir cliente para la venta? Hace falta el módulo de clientes
  /// y permiso para verlos. Al cobrar una cita el cliente ya viene puesto, pero
  /// se deja cambiar igual.
  bool get _canPickClient {
    final me = context.read<AuthController>().me;
    return (me?.hasModule('clientes') ?? false) && (me?.can('clients.view') ?? false);
  }

  Future<void> _pickClient(CheckoutController checkout) async {
    final me = context.read<AuthController>().me;

    final client = await ClientPickerSheet.show(
      context,
      api: context.read<ApiClient>(),
      canCreate: me?.can('clients.create') ?? false,
    );

    if (client != null) checkout.setClient(client.id, client.fullName);
  }

  /// Elige el barbero que atiende un servicio (para su comisión). «Sin asignar»
  /// lo deja sin atribuir.
  Future<void> _pickBarber(CheckoutController checkout, CartLine line) async {
    if (checkout.staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay barberos para asignar.'),
      ));
      return;
    }

    final picked = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: BarboraTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Barbero para ${line.name}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_off_outlined, color: BarboraTheme.textMuted),
              title: const Text('Sin asignar'),
              trailing: line.personalId == null ? const Icon(Icons.check, color: BarboraTheme.copper) : null,
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final s in checkout.staff)
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: BarboraTheme.canvas,
                  child: Text(s.initials,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: BarboraTheme.ink)),
                ),
                title: Text(s.fullName),
                trailing: line.personalId == s.id ? const Icon(Icons.check, color: BarboraTheme.copper) : null,
                onTap: () => Navigator.of(context).pop(s.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    // -1 = «Sin asignar»; null = cerró sin elegir.
    if (picked != null) checkout.setLinePersonal(line, picked == -1 ? null : picked);
  }

  /// Diálogo para fijar descuento o propina. `max` acota el descuento al
  /// subtotal; la propina no tiene tope. «Quitar» lo deja en cero.
  Future<void> _editAmount({
    required String title,
    required double current,
    required String symbol,
    double? max,
    required ValueChanged<double> onSet,
  }) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(title: title, current: current, symbol: symbol, max: max),
    );

    if (value != null) onSet(value);
  }

  void _addProduct(CheckoutController checkout, Product product) {
    final added = checkout.addProduct(product);

    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No queda suficiente ${product.name}: ${product.stockLabel}.'),
        backgroundColor: BarboraTheme.copperDark,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutController>();
    final symbol = context.watch<AuthController>().company?.symbol ?? '';

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: BarboraTheme.inkGradient),
        ),
        title: const Text('Cobrar'),
        actions: [
          if (!checkout.isEmpty)
            TextButton(
              onPressed: () => checkout.reset(),
              style: TextButton.styleFrom(foregroundColor: BarboraTheme.titanium),
              child: const Text('Vaciar'),
            ),
        ],
      ),
      body: _body(checkout, symbol),
      bottomNavigationBar: checkout.isEmpty
          ? null
          : _TotalBar(
              total: checkout.total,
              symbol: symbol,
              onPay: () => _payments(context, checkout, symbol),
            ),
    );
  }

  Widget _body(CheckoutController checkout, String symbol) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BarboraTheme.copper));
    }

    if (_error != null) {
      return ErrorView(error: _error!, onRetry: _loadCatalog);
    }

    final showTabs = _hasInventory && _products.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!checkout.isEmpty) ...[
          _CartCard(
            checkout: checkout,
            symbol: symbol,
            onPickClient: _canPickClient ? () => _pickClient(checkout) : null,
            onPickBarber: (line) => _pickBarber(checkout, line),
            onEditDiscount: () => _editAmount(
              title: 'Descuento',
              current: checkout.discount,
              symbol: symbol,
              max: checkout.subtotal,
              onSet: checkout.setDiscount,
            ),
            onEditTip: () => _editAmount(
              title: 'Propina',
              current: checkout.tip,
              symbol: symbol,
              onSet: checkout.setTip,
            ),
          ),
          const SizedBox(height: 18),
        ],

        if (showTabs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Servicios'),
                  icon: Icon(Icons.content_cut, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Productos'),
                  icon: Icon(Icons.inventory_2_outlined, size: 16),
                ),
              ],
              selected: {_showProducts},
              onSelectionChanged: (s) => setState(() => _showProducts = s.first),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              'AÑADIR SERVICIO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: BarboraTheme.textMuted,
              ),
            ),
          ),

        if (_showProducts && showTabs)
          ..._productList(checkout, symbol)
        else
          ..._serviceList(checkout, symbol),
      ],
    );
  }

  List<Widget> _serviceList(CheckoutController checkout, String symbol) {
    if (_services.isEmpty) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No hay servicios activos en el catálogo.',
              style: TextStyle(color: BarboraTheme.textMuted, fontSize: 13),
            ),
          ),
        ),
      ];
    }

    return _services
        .map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ServiceTile(
              service: s,
              symbol: symbol,
              onAdd: () => checkout.addService(s),
            ),
          ),
        )
        .toList();
  }

  List<Widget> _productList(CheckoutController checkout, String symbol) {
    return _products
        .map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ProductTile(
              product: p,
              symbol: symbol,
              onAdd: () => _addProduct(checkout, p),
            ),
          ),
        )
        .toList();
  }

  /// Hoja de pago: cuánto entra por cada método. Tiene que cuadrar con el
  /// total o el servidor lo rechaza, así que se comprueba aquí antes.
  void _payments(BuildContext context, CheckoutController checkout, String symbol) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(symbol: symbol),
    );
  }
}

class _CartCard extends StatelessWidget {
  const _CartCard({
    required this.checkout,
    required this.symbol,
    this.onPickClient,
    required this.onPickBarber,
    required this.onEditDiscount,
    required this.onEditTip,
  });

  final CheckoutController checkout;
  final String symbol;

  /// Null cuando el plan o el permiso no dejan elegir cliente.
  final VoidCallback? onPickClient;

  /// Elegir el barbero de una línea de servicio (para comisiones).
  final void Function(CartLine line) onPickBarber;
  final VoidCallback onEditDiscount;
  final VoidCallback onEditTip;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Text(
                  'COMANDA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: BarboraTheme.textMuted,
                  ),
                ),
                const Spacer(),
                // El cliente de la venta. Se puede dejar en blanco (venta
                // suelta) o elegir uno, por ejemplo para su historial.
                if (onPickClient != null)
                  _ClientChip(name: checkout.clientName, onTap: onPickClient!)
                else if (checkout.clientName != null)
                  Flexible(
                    child: Text(
                      checkout.clientName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BarboraTheme.titanium),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          ...checkout.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '$symbol ${line.unitPrice.toStringAsFixed(2)} c/u',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: BarboraTheme.textMuted,
                          ),
                        ),
                        // Barbero que atiende el servicio (para su comisión).
                        if (line.isService) ...[
                          const SizedBox(height: 4),
                          _BarberChip(
                            name: checkout.staffById(line.personalId)?.fullName,
                            onTap: () => onPickBarber(line),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _Stepper(
                    quantity: line.quantity,
                    onChanged: (q) => checkout.changeQuantity(line, q),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      '$symbol ${line.total.toStringAsFixed(2)}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                _Line(label: 'Subtotal', value: checkout.subtotal, symbol: symbol),
                _AdjustRow(
                  label: 'Descuento',
                  value: checkout.discount,
                  symbol: symbol,
                  negative: true,
                  onTap: onEditDiscount,
                ),
                _AdjustRow(
                  label: 'Propina',
                  value: checkout.tip,
                  symbol: symbol,
                  onTap: onEditTip,
                ),
                const SizedBox(height: 6),
                _Line(label: 'Total', value: checkout.total, symbol: symbol, strong: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo numérico para descuento o propina. Dueño de su propio controlador:
/// así no se desecha mientras el campo aún se cierra, que es lo que reventaba.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.current,
    required this.symbol,
    this.max,
  });

  final String title;
  final double current;
  final String symbol;
  final double? max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _controller = TextEditingController(
    text: widget.current > 0 ? widget.current.toStringAsFixed(2) : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          prefixText: '${widget.symbol} ',
          hintText: '0.00',
          helperText:
              widget.max != null ? 'Máximo ${widget.symbol} ${widget.max!.toStringAsFixed(2)}' : null,
        ),
        onSubmitted: (_) => Navigator.of(context).pop(_value),
      ),
      actions: [
        if (widget.current > 0)
          TextButton(
            onPressed: () => Navigator.of(context).pop(0.0),
            style: TextButton.styleFrom(foregroundColor: BarboraTheme.copperDark),
            child: const Text('Quitar'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

/// Botón-ficha del cliente en la cabecera de la comanda.
class _ClientChip extends StatelessWidget {
  const _ClientChip({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = name != null && name!.isNotEmpty;

    return Flexible(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: has ? BarboraTheme.copper.withValues(alpha: .10) : BarboraTheme.canvas,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: has ? BarboraTheme.copper.withValues(alpha: .30) : BarboraTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                has ? Icons.person : Icons.person_add_alt,
                size: 14,
                color: has ? BarboraTheme.copperDark : BarboraTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  has ? name! : 'Cliente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: has ? BarboraTheme.copperDark : BarboraTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip del barbero de una línea de servicio. Sin barbero muestra «Asignar
/// barbero»; con uno, su nombre.
class _BarberChip extends StatelessWidget {
  const _BarberChip({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = name != null && name!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              has ? Icons.content_cut : Icons.person_add_alt,
              size: 13,
              color: has ? BarboraTheme.copperDark : BarboraTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                has ? name! : 'Asignar barbero',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: has ? BarboraTheme.copperDark : BarboraTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de descuento o propina: tócala para fijarla. Sin valor muestra
/// «Agregar»; con valor, el importe y un lápiz para cambiarlo.
class _AdjustRow extends StatelessWidget {
  const _AdjustRow({
    required this.label,
    required this.value,
    required this.symbol,
    required this.onTap,
    this.negative = false,
  });

  final String label;
  final double value;
  final String symbol;
  final VoidCallback onTap;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final has = value > 0;
    final shown = negative ? -value : value;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: BarboraTheme.textMuted),
            ),
            const Spacer(),
            if (has) ...[
              Text(
                '$symbol ${shown.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 14, color: BarboraTheme.textMuted),
            ] else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add, size: 15, color: BarboraTheme.copperDark),
                  SizedBox(width: 3),
                  Text(
                    'Agregar',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: BarboraTheme.copperDark,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onChanged});

  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          color: BarboraTheme.textMuted,
        ),
        SizedBox(
          width: 20,
          child: Text(
            quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add_circle_outline, size: 20),
          color: BarboraTheme.copperDark,
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.symbol,
    required this.onAdd,
  });

  final Service service;
  final String symbol;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${service.durationMinutes} min',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: BarboraTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$symbol ${service.price.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.add_circle, color: BarboraTheme.copper, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.symbol,
    required this.onAdd,
  });

  final Product product;
  final String symbol;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable;

    return Opacity(
      opacity: available ? 1 : .5,
      child: Card(
        child: InkWell(
          onTap: available ? onAdd : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            available ? product.stockLabel : 'Agotado',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: product.lowStock || !available
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: !available
                                  ? BarboraTheme.copperDark
                                  : (product.lowStock
                                      ? const Color(0xFFB45309)
                                      : BarboraTheme.textMuted),
                            ),
                          ),
                          if (product.lowStock && available) ...[
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Color(0xFFB45309),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '$symbol ${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(width: 10),
                Icon(
                  available ? Icons.add_circle : Icons.do_not_disturb_on,
                  color: available ? BarboraTheme.copper : BarboraTheme.titanium,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    required this.symbol,
    this.strong = false,
  });

  final String label;
  final double value;
  final String symbol;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: strong ? BarboraTheme.ink : BarboraTheme.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            '$symbol ${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: strong ? 18 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalBar extends StatelessWidget {
  const _TotalBar({required this.total, required this.symbol, required this.onPay});

  final double total;
  final String symbol;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 20),
          FilledButton(
            onPressed: onPay,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payments_outlined, size: 20),
                const SizedBox(width: 10),
                Text('Cobrar $symbol ${total.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reparto del cobro entre métodos de pago.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.symbol});

  final String symbol;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final List<PaymentMethod> _methods;
  late final Map<String, TextEditingController> _controllers;
  late String _primary;

  @override
  void initState() {
    super.initState();

    // Los métodos los define la barbería y llegan en /me; el fallback solo
    // actúa si la sesión todavía no cargó.
    final fromSession = context.read<AuthController>().me?.paymentMethods ?? const [];
    _methods = fromSession.isEmpty ? PaymentMethod.fallback : fromSession;

    _controllers = {
      for (final m in _methods) m.slug: TextEditingController(),
    };

    // Se rellena el primero que entre al cajón —normalmente el efectivo—, que
    // es como se cobra casi siempre.
    _primary = _methods.firstWhere(
      (m) => m.countsAsCash,
      orElse: () => _methods.first,
    ).slug;

    final total = context.read<CheckoutController>().total;
    _controllers[_primary]!.text = total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, double> get _payments => {
        for (final e in _controllers.entries)
          e.key: double.tryParse(e.value.text.replaceAll(',', '.')) ?? 0,
      };

  double get _paid => _payments.values.fold(0, (s, v) => s + v);

  /// Se rellena el método principal para que la suma cuadre con el total.
  void _autoFill() {
    final checkout = context.read<CheckoutController>();
    final others = _payments.entries
        .where((e) => e.key != _primary)
        .fold(0.0, (s, e) => s + e.value);

    _controllers[_primary]!.text =
        (checkout.total - others).clamp(0, double.infinity).toStringAsFixed(2);

    setState(() {});
  }

  Future<void> _pay() async {
    final checkout = context.read<CheckoutController>();
    final cash = context.read<CashController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final error = await checkout.checkout(_payments);

    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: BarboraTheme.copperDark,
      ));
      return;
    }

    final sale = checkout.lastSale;

    // La venta metió dinero en el cajón: la caja tiene que reflejarlo.
    await cash.refreshAfterSale();

    checkout.reset();

    navigator.pop(); // la hoja de pago
    navigator.pop(); // la pantalla de cobro

    // El comprobante sustituye a la pantalla de cobro: al cerrarlo se vuelve a
    // la caja, no a una comanda ya cobrada.
    if (sale != null) {
      navigator.push(MaterialPageRoute(builder: (_) => ReceiptScreen(sale: sale)));
      return;
    }

    messenger.showSnackBar(const SnackBar(
      content: Text('Venta cobrada.'),
      backgroundColor: Color(0xFF16A34A),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutController>();
    final difference = _paid - checkout.total;
    final squared = difference.abs() < 0.005;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BarboraTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  const Text(
                    'Total a cobrar',
                    style: TextStyle(fontSize: 14, color: BarboraTheme.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.symbol} ${checkout.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              ..._methods.map(
                (method) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[method.slug],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    onTap: () => setState(() => _primary = method.slug),
                    decoration: InputDecoration(
                      labelText: method.name,
                      // Se avisa de lo que NO entra al cajón: al arquear, ese
                      // dinero no estará ahí.
                      helperText: method.countsAsCash ? null : 'No entra al cajón',
                      prefixText: '${widget.symbol} ',
                      isDense: true,
                    ),
                  ),
                ),
              ),

              if (!squared) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 17,
                      color: BarboraTheme.copperDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        difference > 0
                            ? 'Sobran ${widget.symbol} ${difference.toStringAsFixed(2)}'
                            : 'Faltan ${widget.symbol} ${(-difference).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: BarboraTheme.copperDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _autoFill,
                      child: const Text('Cuadrar', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              FilledButton(
                onPressed: checkout.busy || !squared ? null : _pay,
                child: checkout.busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirmar cobro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

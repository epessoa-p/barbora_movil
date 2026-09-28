import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    await context.read<AuthController>().login(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BarboraTheme.inkGradient),
        child: Stack(
          children: [
            // Halo de cobre detrás del logo: da profundidad sin cargar nada.
            Positioned(
              top: -120,
              right: -90,
              child: _Glow(size: 300, color: BarboraTheme.copper.withValues(alpha: .18)),
            ),
            Positioned(
              bottom: -140,
              left: -110,
              child: _Glow(size: 320, color: BarboraTheme.copperDark.withValues(alpha: .12)),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandLogo.full(height: 78),
                        const SizedBox(height: 34),

                        _GlassCard(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (auth.error != null) ...[
                                  _ErrorBanner(message: auth.error!),
                                  const SizedBox(height: 18),
                                ],

                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  enabled: !auth.busy,
                                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'Correo',
                                    prefixIcon: const Icon(Icons.alternate_email, size: 20),
                                    errorText: auth.fieldError('email'),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty)
                                      ? 'Escribe tu correo'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                TextFormField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  obscureText: _obscure,
                                  enabled: !auth.busy,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                    suffixIcon: IconButton(
                                      iconSize: 20,
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                                ),
                                const SizedBox(height: 24),

                                FilledButton(
                                  onPressed: auth.busy ? null : _submit,
                                  child: auth.busy
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Entrar'),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),
                        // Solo fuera de producción: si la app no conecta, lo
                        // primero que hay que mirar es a dónde apunta. A un
                        // barbero la URL del servidor no le dice nada.
                        if (!Config.isProduction) Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 12,
                              color: BarboraTheme.titanium.withValues(alpha: .35),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              Config.apiBaseUrl,
                              style: TextStyle(
                                fontSize: 11,
                                color: BarboraTheme.titanium.withValues(alpha: .35),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta clara sobre el fondo oscuro, con un borde muy sutil.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: BarboraTheme.copper.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BarboraTheme.copper.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 19, color: BarboraTheme.copperDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: BarboraTheme.copperDark,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

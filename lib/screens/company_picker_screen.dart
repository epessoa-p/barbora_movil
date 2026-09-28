import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../theme/barbora_theme.dart';
import '../widgets/brand_logo.dart';

/// Cuando el usuario trabaja en más de una barbería hay que preguntar en cuál
/// está. Lo elegido viaja luego en la cabecera X-Company-Id de cada petición.
class CompanyPickerScreen extends StatelessWidget {
  const CompanyPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: BarboraTheme.inkGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const BrandLogo.mark(height: 30),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: auth.busy
                              ? null
                              : () => context.read<AuthController>().logout(),
                          icon: const Icon(Icons.logout, size: 17),
                          label: const Text('Salir'),
                          style: TextButton.styleFrom(
                            foregroundColor: BarboraTheme.titanium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Hola, ${auth.me?.user.name ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '¿En qué barbería vas a trabajar hoy?',
                      style: TextStyle(
                        color: BarboraTheme.titanium.withValues(alpha: .85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: auth.busy && auth.companies.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (auth.error != null) ...[
                        _Notice(message: auth.error!),
                        const SizedBox(height: 14),
                      ],

                      if (auth.companies.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(Icons.store_mall_directory_outlined,
                                    size: 44, color: Colors.black26),
                                SizedBox(height: 12),
                                Text(
                                  'Todavía no estás asignado a ninguna barbería',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Habla con el administrador para que te dé acceso.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: BarboraTheme.textMuted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...auth.companies.map(
                          (company) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: auth.busy
                                    ? null
                                    : () => context
                                        .read<AuthController>()
                                        .chooseCompany(company),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: BarboraTheme.copperGradient,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          company.name.isEmpty
                                              ? '?'
                                              : company.name
                                                  .substring(0, 1)
                                                  .toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15.5,
                                              ),
                                            ),
                                            if (company.currency != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                company.currency!,
                                                style: const TextStyle(
                                                  color: BarboraTheme.textMuted,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: BarboraTheme.titanium),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BarboraTheme.copper.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BarboraTheme.copper.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 19, color: BarboraTheme.copperDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: BarboraTheme.copperDark, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

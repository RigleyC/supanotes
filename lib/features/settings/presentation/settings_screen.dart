library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/app_version/app_version_provider.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(authControllerProvider).value;
    final packageInfo = ref.watch(appPackageInfoProvider);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Configurações')),
      body: ListView(
        padding: EdgeInsets.only(
          top: PlatformInfo.isIOS26OrHigher()
              ? AppSpacing.ios26ToolbarHeight
              : 0.0,
          bottom: AppSpacing.lg,
        ),
        children: [
          AppTile(
            leading: const Icon(Icons.person_outline),
            title: account?.name ?? '—',
          ),
          AppTile(
            leading: const Icon(Icons.alternate_email),
            title: account?.email ?? '—',
          ),
          AppTile(
            leading: const Icon(Icons.developer_mode_outlined),
            title: 'Protocolo de Contexto (MCP)',
            onTap: () => context.push(AppRoutes.mcp),
            trailing: const Icon(Icons.chevron_right),
          ),
          packageInfo.when(
            data: (info) => AppTile(
              leading: const Icon(Icons.info_outline),
              title: 'Versão',
              subtitle: '${info.version}+${info.buildNumber}',
            ),
            loading: () => const AppTile(
              leading: Icon(Icons.info_outline),
              title: 'Versão',
              subtitle: 'Carregando…',
            ),
            error: (error, _) => AppTile(
              leading: const Icon(Icons.info_outline),
              title: 'Versão',
              subtitle: 'Indisponível: $error',
            ),
          ),
          AppTile(
            leading: const Icon(Icons.logout),
            title: 'Sair da conta',
            onTap: () => _confirmLogout(context, ref),
            enabled: account != null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Sair da conta?',
      message: 'Você precisará fazer login novamente para acessar suas notas.',
      confirmLabel: 'Sair',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }
}

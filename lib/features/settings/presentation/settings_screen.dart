library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:supanotes/features/settings/presentation/widgets/settings_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authControllerProvider).value;
    final pushEnabled = ref.watch(pushServiceProvider);

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'Configurações'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          const SettingsSectionHeader(title: 'Conta'),
          SettingsTile.action(
            icon: Icons.alternate_email,
            title: 'Email',
            subtitle: account?.email ?? '—',
          ),
          SettingsTile.action(
            icon: Icons.person_outline,
            title: 'Nome',
            subtitle: account?.name ?? '—',
          ),
          SettingsTile.action(
            icon: Icons.logout,
            title: 'Sair da conta',
            onTap: () => _confirmLogout(context, ref),
            enabled: account != null,
          ),

          const SettingsSectionHeader(title: 'Notificações'),
          SettingsTile.toggle(
            icon: Icons.notifications_outlined,
            title: 'Receber push',
            subtitle: 'Notificações de briefs e lembretes (em breve).',
            value: pushEnabled,
            onChanged: (v) =>
                ref.read(pushServiceProvider.notifier).toggle(v),
          ),

          const SettingsSectionHeader(title: 'Avançado'),
          SettingsTile.navigation(
            icon: Icons.auto_awesome_outlined,
            title: 'Personalidade do agent',
            subtitle: 'Edite o prompt da SOUL.',
            onTap: () => context.push(AppRoutes.soul),
          ),
          SettingsTile.navigation(
            icon: Icons.folder_outlined,
            title: 'Contextos',
            subtitle: 'Pastas que agrupam suas notas.',
            onTap: () => context.push(AppRoutes.contexts),
          ),
          SettingsTile.navigation(
            icon: Icons.send_outlined,
            title: 'Telegram',
            subtitle: 'Conecte sua conta do Telegram.',
            onTap: () => context.push(AppRoutes.telegram),
          ),
          SettingsTile.navigation(
            icon: Icons.developer_mode_outlined,
            title: 'Protocolo de Contexto (MCP)',
            subtitle: 'Token de acesso e configuração.',
            onTap: () => context.push(AppRoutes.mcp),
          ),
          SettingsTile.navigation(
            icon: Icons.cloud_sync_outlined,
            title: 'Dados',
            subtitle: 'Informações da última sincronização.',
            onTap: () => _showSyncDialog(context, ref),
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

  Future<void> _showSyncDialog(BuildContext context, WidgetRef ref) async {
    final sync = ref.watch(syncStateProvider);
    final lastSynced = sync.lastSyncedAt;
    final message = lastSynced == null
        ? 'Nenhuma sincronização registrada.'
        : 'Última sync: ${timeago.format(lastSynced, locale: 'pt_BR')}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sincronização'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

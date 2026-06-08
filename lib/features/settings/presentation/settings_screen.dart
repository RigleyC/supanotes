library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/features/settings/presentation/widgets/settings_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class _SettingsStrings {
  _SettingsStrings._();

  static const String title = 'Configurações';

  static const String accountSection = 'Conta';
  static const String notificationsSection = 'Notificações';
  static const String advancedSection = 'Avançado';

  static const String emailTile = 'Email';
  static const String nameTile = 'Nome';
  static const String fallbackName = '—';
  static const String fallbackEmail = '—';
  static const String logoutTile = 'Sair da conta';
  static const String logoutConfirmTitle = 'Sair da conta?';
  static const String logoutConfirmMessage =
      'Você precisará fazer login novamente para acessar suas notas.';
  static const String logoutConfirmLabel = 'Sair';

  static const String pushTile = 'Receber push';
  static const String pushSubtitle =
      'Notificações de briefs e lembretes (em breve).';

  static const String soulTile = 'Personalidade do agent';
  static const String soulSubtitle = 'Edite o prompt da SOUL.';
  static const String contextsTile = 'Contextos';
  static const String contextsSubtitle = 'Pastas que agrupam suas notas.';
  static const String telegramTile = 'Telegram';
  static const String telegramSubtitle = 'Conecte sua conta do Telegram.';
  static const String dataTile = 'Dados';
  static const String dataSubtitle = 'Informações da última sincronização.';

  static const String dataDialogTitle = 'Sincronização';
  static const String dataDialogNoSync = 'Nenhuma sincronização registrada.';
  static String dataDialogLastSynced(String relative) =>
      'Última sync: $relative';
  static const String dataDialogClose = 'Fechar';

  static const String soulRoute = '/soul';
  static const String contextsRoute = '/contexts';
  static const String telegramRoute = '/telegram';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushEnabled = false;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authControllerProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text(_SettingsStrings.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            const SettingsSectionHeader(
              title: _SettingsStrings.accountSection,
            ),
            SettingsTile.action(
              icon: Icons.alternate_email,
              title: _SettingsStrings.emailTile,
              subtitle: account?.email ?? _SettingsStrings.fallbackEmail,
            ),
            SettingsTile.action(
              icon: Icons.person_outline,
              title: _SettingsStrings.nameTile,
              subtitle: account?.name ?? _SettingsStrings.fallbackName,
            ),
            SettingsTile.action(
              icon: Icons.logout,
              title: _SettingsStrings.logoutTile,
              onTap: () => _confirmLogout(context, ref),
              enabled: account != null,
            ),

            const SettingsSectionHeader(
              title: _SettingsStrings.notificationsSection,
            ),
            SettingsTile.toggle(
              icon: Icons.notifications_outlined,
              title: _SettingsStrings.pushTile,
              subtitle: _SettingsStrings.pushSubtitle,
              value: _pushEnabled,
              onChanged: (_) => setState(() => _pushEnabled = !_pushEnabled),
            ),

            const SettingsSectionHeader(
              title: _SettingsStrings.advancedSection,
            ),
            SettingsTile.navigation(
              icon: Icons.auto_awesome_outlined,
              title: _SettingsStrings.soulTile,
              subtitle: _SettingsStrings.soulSubtitle,
              onTap: () => context.push(_SettingsStrings.soulRoute),
            ),
            SettingsTile.navigation(
              icon: Icons.folder_outlined,
              title: _SettingsStrings.contextsTile,
              subtitle: _SettingsStrings.contextsSubtitle,
              onTap: () => context.push(_SettingsStrings.contextsRoute),
            ),
            SettingsTile.navigation(
              icon: Icons.send_outlined,
              title: _SettingsStrings.telegramTile,
              subtitle: _SettingsStrings.telegramSubtitle,
              onTap: () => context.push(_SettingsStrings.telegramRoute),
            ),
            SettingsTile.navigation(
              icon: Icons.cloud_sync_outlined,
              title: _SettingsStrings.dataTile,
              subtitle: _SettingsStrings.dataSubtitle,
              onTap: () => _showSyncDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: _SettingsStrings.logoutConfirmTitle,
      message: _SettingsStrings.logoutConfirmMessage,
      confirmLabel: _SettingsStrings.logoutConfirmLabel,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  Future<void> _showSyncDialog(BuildContext context, WidgetRef ref) async {
    final sync = ref.read(syncStateProvider);
    final lastSynced = sync.lastSyncedAt;
    final message = lastSynced == null
        ? _SettingsStrings.dataDialogNoSync
        : _SettingsStrings.dataDialogLastSynced(
            timeago.format(lastSynced, locale: 'pt_BR'),
          );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(_SettingsStrings.dataDialogTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(_SettingsStrings.dataDialogClose),
          ),
        ],
      ),
    );
  }
}

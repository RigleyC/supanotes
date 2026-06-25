import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class _McpStrings {
  _McpStrings._();

  static const String title = 'MCP';
  static const String tokenCardTitle = 'Token de Acesso';
  static const String generateToken = 'Gerar Token';
  static const String generatedTokenLabel = 'Seu token (mostrado apenas uma vez):';
  static const String copyToken = 'Copiar Token';
  static const String tokenWarning =
      'Este token será exibido apenas uma vez. Copie-o agora e armazene em um local seguro.';
  static const String tokenCopied = 'Token copiado!';
  static const String tokenGenerated = 'Token gerado com sucesso.';

  static const String claudeCardTitle = 'Claude Desktop';
  static const String claudeInstructions =
      'Adicione esta configuração ao seu arquivo claude_desktop_config.json:';
  static const String copyConfig = 'Copiar Configuração';
  static const String configCopied = 'Configuração copiada!';

  static const String cursorCardTitle = 'Cursor';
  static const String cursorInstructions =
      'No Cursor, vá em Settings > Features > MCP Servers e adicione um novo servidor MCP com:';
  static const String cursorSseUrl = 'URL (SSE):';
  static const String cursorHeader = 'Header:';
}

String _sseUrl() => '${ApiConstants.baseUrl}/mcp';

String _buildClaudeConfigJson({required String sseUrl, String? token}) {
  final buffer = StringBuffer()
    ..writeln('{')
    ..writeln('  "mcpServers": {')
    ..writeln('    "supanotes": {')
    ..writeln('      "type": "sse",')
    ..writeln('      "url": "$sseUrl"');
  if (token != null && token.isNotEmpty) {
    buffer.writeln('      "headers": {');
    buffer.writeln('        "Authorization": "Bearer $token"');
    buffer.writeln('      }');
  }
  buffer
    ..writeln('    }')
    ..writeln('  }')
    ..write('}');
  return buffer.toString();
}

class McpScreen extends ConsumerStatefulWidget {
  const McpScreen({super.key});

  @override
  ConsumerState<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends ConsumerState<McpScreen> {
  String? _generatedToken;
  bool _isGenerating = false;

  Future<void> _generateToken() async {
    setState(() => _isGenerating = true);
    try {
      final token = await ref.read(settingsRepositoryProvider).generateMcpToken();
      if (!mounted) return;
      setState(() {
        _generatedToken = token;
        _isGenerating = false;
      });
      AppMessenger.showSuccess(context, _McpStrings.tokenGenerated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      AppMessenger.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const AdaptiveSliverNavBar(title: Text(_McpStrings.title)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _TokenCard(
                  generatedToken: _generatedToken,
                  isGenerating: _isGenerating,
                  onGenerate: _generateToken,
                ),
                const SizedBox(height: AppSpacing.md),
                _ClaudeCard(
                  token: _generatedToken,
                ),
                const SizedBox(height: AppSpacing.md),
                _CursorCard(
                  token: _generatedToken,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({
    required this.generatedToken,
    required this.isGenerating,
    required this.onGenerate,
  });

  final String? generatedToken;
  final bool isGenerating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _McpStrings.tokenCardTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (generatedToken != null) ...[
              Text(
                _McpStrings.generatedTokenLabel,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: SelectableText(
                  generatedToken!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                text: _McpStrings.copyToken,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: generatedToken!));
                  AppMessenger.showSuccess(context, _McpStrings.tokenCopied);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: AppSpacing.iconSm,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _McpStrings.tokenWarning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              AppButton(
                text: _McpStrings.generateToken,
                isLoading: isGenerating,
                onPressed: isGenerating ? null : onGenerate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClaudeCard extends StatelessWidget {
  const _ClaudeCard({required this.token});

  final String? token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sseUrl = _sseUrl();
    final configJson = _buildClaudeConfigJson(sseUrl: sseUrl, token: token);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _McpStrings.claudeCardTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _McpStrings.claudeInstructions,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: SelectableText(
                configJson,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              text: _McpStrings.copyConfig,
              variant: AppButtonVariant.tonal,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: configJson));
                AppMessenger.showSuccess(context, _McpStrings.configCopied);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CursorCard extends StatelessWidget {
  const _CursorCard({required this.token});

  final String? token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sseUrl = _sseUrl();
    final headerValue = token != null
        ? 'Bearer $token'
        : 'Bearer <seu_token>';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal_outlined),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _McpStrings.cursorCardTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _McpStrings.cursorInstructions,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _McpStrings.cursorSseUrl,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    sseUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _McpStrings.cursorHeader,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            headerValue,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        if (token != null)
                          IconButton(
                            icon: const Icon(Icons.copy, size: AppSpacing.iconSm),
                            tooltip: _McpStrings.copyToken,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: 'Bearer $token'),
                              );
                              AppMessenger.showSuccess(
                                context,
                                _McpStrings.tokenCopied,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

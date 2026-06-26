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
      AppMessenger.showSuccess('Token gerado com sucesso.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      AppMessenger.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const AdaptiveSliverNavBar(title: Text('MCP')),
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
                  'Token de Acesso',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (generatedToken != null) ...[
              Text(
                'Seu token (mostrado apenas uma vez):',
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
                text: 'Copiar Token',
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: generatedToken!));
                  AppMessenger.showSuccess('Token copiado!');
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
                        'Este token será exibido apenas uma vez. Copie-o agora e armazene em um local seguro.',
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
                text: 'Gerar Token',
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
                  'Claude Desktop',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Adicione esta configuração ao seu arquivo claude_desktop_config.json:',
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
              text: 'Copiar Configuração',
              variant: AppButtonVariant.tonal,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: configJson));
                AppMessenger.showSuccess('Configuração copiada!');
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
                  'Cursor',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No Cursor, vá em Settings > Features > MCP Servers e adicione um novo servidor MCP com:',
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
                    'URL (SSE):',
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
                    'Header:',
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
                            tooltip: 'Copiar Token',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: 'Bearer $token'),
                              );
                              AppMessenger.showSuccess(
                                'Token copiado!',
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

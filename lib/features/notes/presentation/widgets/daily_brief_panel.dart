import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../../routines/presentation/controllers/daily_brief_provider.dart';

class DailyBriefPanel extends ConsumerWidget {
  const DailyBriefPanel({super.key});

  static const String _placeholder =
      'Suas prioridades, notas recentes e proximos passos aparecem aqui.';
  static const String _error = 'Nao foi possivel carregar o brief agora.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefAsync = ref.watch(dailyBriefProvider);

    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: briefAsync.when(
              data: (text) => _BriefText(text: _briefText(text)),
              loading: () => const _BriefText(text: _placeholder),
              error: (_, _) => const _BriefText(text: _error),
            ),
          ),
        ),
      ),
    );
  }

  String _briefText(String? text) {
    final value = text?.trim();
    return value == null || value.isEmpty ? _placeholder : value;
  }
}

class _BriefText extends StatelessWidget {
  const _BriefText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Cue.onChange(
      key: ValueKey(text),
      value: text,
      motion: .smooth(),
      acts: [.fadeIn(), .slideY(from: -0.1)],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Morning brief',
            style: textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

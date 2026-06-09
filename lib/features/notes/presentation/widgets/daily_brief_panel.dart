import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../../routines/presentation/controllers/daily_brief_provider.dart';

class DailyBriefPanel extends ConsumerWidget {
  const DailyBriefPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final briefAsync = ref.watch(dailyBriefProvider);

    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: briefAsync.when(
            data: (text) {
              if (text == null || text.isEmpty) return const SizedBox.shrink();
              return Cue.onMount(
                motion: .smooth(),
                acts: [.fadeIn(), .slideY(from: -0.1)],
                child: Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(
              'Não foi possível carregar o brief',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder home screen used until FE-4 ships the real shell.
///
/// Lays out a header with the (currently unauthenticated) user name and
/// a sign-out button. The button wires through the [AuthController] so
/// we can manually verify the full auth loop (login → home → logout →
/// /login) in the integration tests without depending on the real home
/// UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final name = state.maybeWhen(
      data: (auth) => auth is AuthAuthenticated ? auth.name : 'there',
      orElse: () => 'there',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hello, $name.',
                style: textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'This is a placeholder home screen. The real inbox, '
                'notes list, and agent chat will land in FE-4 onward.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () => ref
                    .read(authControllerProvider.notifier)
                    .logout(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

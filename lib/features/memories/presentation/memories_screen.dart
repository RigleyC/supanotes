library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/memories/domain/memory_model.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'memories_controller.dart';

class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(memoriesControllerProvider);

    ref.listen<AsyncValue<List<MemoryModel>>>(memoriesControllerProvider, (
      prev,
      next,
    ) {
      next.whenOrNull(
        error: (err, _) {
          if (prev == null || prev.hasError == false) {
            AppMessenger.showError(err.toString());
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Memórias')),
      body: asyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (memories) => memories.isEmpty
            ? const EmptyState(
                icon: Icons.auto_awesome,
                title: 'Nenhuma memória',
                subtitle: 'Memórias serão exibidas aqui.',
              )
            : ListView.builder(
                itemCount: memories.length,
                itemBuilder: (context, index) {
                  final memory = memories[index];
                  return ListTile(
                    title: Text(memory.content),
                    subtitle: memory.contextSlug != null
                        ? Text(memory.contextSlug!)
                        : null,
                    trailing: AdaptiveButton.icon(
                      style: AdaptiveButtonStyle.plain,
                      padding: EdgeInsets.zero,
                      icon: Icons.delete_outline,
                      onPressed: () => ref
                          .read(memoriesControllerProvider.notifier)
                          .deleteMemory(memory.id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

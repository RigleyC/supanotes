library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

import 'memories_controller.dart';

class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoriesControllerProvider);

    ref.listen<MemoriesState>(memoriesControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        AppMessenger.showError(context, next.error!);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Memórias')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.memories.isEmpty
              ? const EmptyState(
                  icon: Icons.auto_awesome,
                  title: 'Nenhuma memória',
                  subtitle: 'Memórias serão exibidas aqui.',
                )
              : ListView.builder(
                  itemCount: state.memories.length,
                  itemBuilder: (context, index) {
                    final memory = state.memories[index];
                    return ListTile(
                      title: Text(memory.content),
                      subtitle: memory.contextSlug != null
                          ? Text(memory.contextSlug!)
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(memoriesControllerProvider.notifier)
                            .deleteMemory(memory.id),
                      ),
                    );
                  },
                ),
    );
  }
}

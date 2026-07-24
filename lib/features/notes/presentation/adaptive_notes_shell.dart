import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_sidebar.dart';
import 'package:supanotes/features/notes/presentation/widgets/resize_drag_handle.dart';
import 'package:uuid/uuid.dart';

class AdaptiveNotesShell extends ConsumerStatefulWidget {
  final Widget child;

  const AdaptiveNotesShell({super.key, required this.child});

  @override
  ConsumerState<AdaptiveNotesShell> createState() => _AdaptiveNotesShellState();
}

class _AdaptiveNotesShellState extends ConsumerState<AdaptiveNotesShell> {
  double _sidebarWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final isDesktop = isDesktopLayout(context);

    if (!isDesktop) {
      return widget.child;
    }

    final state = GoRouterState.of(context);
    final selectedNoteId = state.pathParameters['id'];

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: NotesSidebar(
              selectedNoteId: selectedNoteId,
              onNoteTap: (note) {
                context.go(AppRoutes.note(note.id));
              },
              onNewNote: () async {
                final id = const Uuid().v4();
                await ref
                    .read(notesRepositoryProvider)
                    .createLocalNote(id: id);
                if (!context.mounted) return;
                context.go(AppRoutes.note(id));
              },
              onOpenSettings: () {
                context.push(AppRoutes.settings);
              },
            ),
          ),
          ResizeDragHandle(
            onDrag: (delta) {
              setState(() {
                _sidebarWidth = (_sidebarWidth + delta).clamp(260.0, 480.0);
              });
            },
          ),
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

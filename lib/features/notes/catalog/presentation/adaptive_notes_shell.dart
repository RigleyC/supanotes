import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/desktop_sidebar_surface.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_sidebar.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/resize_drag_handle.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_open_options.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';
import 'package:uuid/uuid.dart';

const _desktopSidebarWidthPreferenceKey = 'desktop_sidebar_width';

class AdaptiveNotesShell extends ConsumerStatefulWidget {
  final Widget child;

  const AdaptiveNotesShell({super.key, required this.child});

  @override
  ConsumerState<AdaptiveNotesShell> createState() => _AdaptiveNotesShellState();
}

class _AdaptiveNotesShellState extends ConsumerState<AdaptiveNotesShell> {
  late double _sidebarWidth;

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(sharedPreferencesProvider);
    _sidebarWidth =
        preferences.getDouble(_desktopSidebarWidthPreferenceKey) ??
        DesktopLayoutTokens.sidebarInitialWidth;
  }

  void _updateSidebarWidth(double delta, double viewportWidth) {
    final nextWidth = DesktopLayoutTokens.clampSidebarWidth(
      _sidebarWidth + delta,
      viewportWidth: viewportWidth,
    );
    if (nextWidth == _sidebarWidth) return;

    setState(() {
      _sidebarWidth = nextWidth;
    });
    final preferences = ref.read(sharedPreferencesProvider);
    unawaited(
      preferences.setDouble(_desktopSidebarWidthPreferenceKey, nextWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = isDesktopLayout(context);

    if (!isDesktop) {
      return widget.child;
    }

    final state = GoRouterState.of(context);
    final selectedNoteId = state.pathParameters['id'];
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = DesktopLayoutTokens.clampSidebarWidth(
      _sidebarWidth,
      viewportWidth: viewportWidth,
    );

    return Scaffold(
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            SizedBox(
              key: const ValueKey('desktop-sidebar-container'),
              width: sidebarWidth,
              child: DesktopSidebarSurface(
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
                    context.go(
                      AppRoutes.note(id),
                      extra: const NoteEditorOpenOptions.newNote(),
                    );
                  },
                  onOpenSettings: () {
                    context.push(AppRoutes.settings);
                  },
                ),
              ),
            ),
            ResizeDragHandle(
              onDrag: (delta) => _updateSidebarWidth(delta, viewportWidth),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

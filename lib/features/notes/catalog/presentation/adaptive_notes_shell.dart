import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/catalog/application/desktop_layout_preferences.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/desktop_content_surface.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/desktop_sidebar_surface.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_sidebar.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/resize_drag_handle.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_open_options.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:uuid/uuid.dart';

class AdaptiveNotesShell extends ConsumerStatefulWidget {
  final Widget child;

  const AdaptiveNotesShell({super.key, required this.child});

  @override
  ConsumerState<AdaptiveNotesShell> createState() => _AdaptiveNotesShellState();
}

class _AdaptiveNotesShellState extends ConsumerState<AdaptiveNotesShell> {
  late double _sidebarWidth;
  late bool _sidebarCollapsed;
  bool _isSidebarResizing = false;

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(desktopLayoutPreferencesProvider);
    _sidebarWidth =
        preferences.sidebarWidth ?? DesktopLayoutTokens.sidebarInitialWidth;
    _sidebarCollapsed = preferences.sidebarCollapsed;
  }

  void _toggleSidebar() {
    final nextCollapsed = !_sidebarCollapsed;
    setState(() {
      _sidebarCollapsed = nextCollapsed;
    });
    unawaited(
      ref
          .read(desktopLayoutPreferencesProvider)
          .saveSidebarCollapsed(nextCollapsed),
    );
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
    final preferences = ref.read(desktopLayoutPreferencesProvider);
    unawaited(preferences.saveSidebarWidth(nextWidth));
  }

  void _startSidebarResize() {
    setState(() {
      _isSidebarResizing = true;
    });
  }

  void _endSidebarResize() {
    if (!mounted) return;
    setState(() {
      _isSidebarResizing = false;
    });
  }

  Future<void> _editNoteIcon(NoteModel note) async {
    await showNoteIconPicker(
      context: context,
      note: note,
      onSelected: (icon) =>
          ref.read(notesRepositoryProvider).updateNoteIcon(note.id, icon),
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
    final visibleSidebarWidth = _sidebarCollapsed
        ? DesktopLayoutTokens.sidebarCollapsedWidth
        : sidebarWidth;

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: scheme.surfaceContainerLowest.withValues(
          alpha: DesktopLayoutTokens.surfaceOpacity,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              key: const ValueKey('desktop-sidebar-container'),
              duration: _isSidebarResizing
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: visibleSidebarWidth,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  child: _sidebarCollapsed
                      ? _CollapsedSidebarRail(
                          key: const ValueKey('collapsed-sidebar-rail'),
                          onExpand: _toggleSidebar,
                        )
                      : OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: sidebarWidth,
                          maxWidth: sidebarWidth,
                          child: DesktopSidebarSurface(
                            key: const ValueKey('expanded-sidebar-surface'),
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
                              onEditIcon: _editNoteIcon,
                              onToggleCollapsed: _toggleSidebar,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (!_sidebarCollapsed)
              ResizeDragHandle(
                onDragStart: _startSidebarResize,
                onDragEnd: _endSidebarResize,
                onDrag: (delta) => _updateSidebarWidth(delta, viewportWidth),
              ),
            Expanded(child: DesktopContentSurface(child: widget.child)),
          ],
        ),
      ),
    );
  }
}

class _CollapsedSidebarRail extends StatelessWidget {
  const _CollapsedSidebarRail({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('desktop-sidebar-rail'),
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          SizedBox(
            height: DesktopLayoutTokens.chromeHeight,
            child: AppIconButton(
              tooltip: 'Expandir sidebar',
              icon: const Icon(Icons.chevron_right),
              onPressed: onExpand,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
            ),
          ),
          Divider(
            height: DesktopLayoutTokens.dividerWidth,
            thickness: DesktopLayoutTokens.dividerWidth,
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

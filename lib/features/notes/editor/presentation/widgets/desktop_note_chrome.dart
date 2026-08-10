import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/desktop_translucent_surface.dart';

/// Compact desktop-only document chrome.
///
/// The screen owns the callbacks and providers. This widget only presents the
/// current note state and keeps note actions above the document surface.
class DesktopNoteChrome extends StatelessWidget {
  final NoteModel? note;
  final NotePreferenceMutationStatus preferenceStatus;
  final FocusNode? editorFocusNode;
  final bool? readOnlyOverride;
  final ValueChanged<String> onMenuSelected;
  final VoidCallback onExitFocus;

  const DesktopNoteChrome({
    super.key,
    required this.note,
    required this.preferenceStatus,
    required this.editorFocusNode,
    this.readOnlyOverride,
    required this.onMenuSelected,
    required this.onExitFocus,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentNote = note;
    final isReadOnly = readOnlyOverride ?? currentNote?.isReadOnly ?? false;

    return DesktopTranslucentSurface(
      key: const ValueKey('desktop-note-chrome'),
      color: scheme.surface,
      child: Container(
        height: DesktopLayoutTokens.chromeHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesktopLayoutTokens.sidebarContentPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: isReadOnly && currentNote?.sharedByEmail != null
                  ? Text(
                      '${NoteStrings.sharedByPrefix} ${currentNote!.sharedByEmail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : const SizedBox.shrink(),
            ),
            if (currentNote != null) ...[
              if (!isReadOnly)
                AdaptivePopupMenuButton.icon<String>(
                  icon: PlatformInfo.isIOS26OrHigher()
                      ? 'ellipsis'
                      : Icons.more_vert,
                  items: [
                    if (currentNote.isOwner)
                      AdaptivePopupMenuItem<String>(
                        label: NoteStrings.shareLabel,
                        icon: PlatformInfo.isIOS26OrHigher()
                            ? 'square.and.arrow.up'
                            : Icons.share_outlined,
                        value: 'share',
                      ),
                    AdaptivePopupMenuItem<String>(
                      label: currentNote.hideCompleted
                          ? NoteStrings.showCompleted
                          : NoteStrings.hideCompleted,
                      icon: PlatformInfo.isIOS26OrHigher()
                          ? (currentNote.hideCompleted ? 'eye' : 'eye.slash')
                          : (currentNote.hideCompleted
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                      value: 'hide_completed',
                    ),
                    if (currentNote.isOwner)
                      AdaptivePopupMenuItem<String>(
                        label: currentNote.collapseImages
                            ? 'Expandir imagens'
                            : 'Colapsar imagens',
                        icon: PlatformInfo.isIOS26OrHigher()
                            ? 'photo'
                            : Icons.image_outlined,
                        value: 'collapse_images',
                      ),
                  ],
                  onSelected: (index, entry) {
                    final value = entry.value;
                    if (value != null) onMenuSelected(value);
                  },
                ),
              _PreferenceStatusIndicator(status: preferenceStatus),
              if (!isReadOnly && editorFocusNode != null)
                AnimatedBuilder(
                  animation: editorFocusNode!,
                  builder: (context, _) {
                    if (!editorFocusNode!.hasFocus) {
                      return const SizedBox.shrink();
                    }
                    return AppIconButton(
                      tooltip: 'Sair do foco',
                      icon: const Icon(Icons.check, size: 20),
                      onPressed: onExitFocus,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreferenceStatusIndicator extends StatelessWidget {
  const _PreferenceStatusIndicator({required this.status});

  final NotePreferenceMutationStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      NotePreferenceMutationStatus.idle => const SizedBox.shrink(),
      NotePreferenceMutationStatus.saving => const SizedBox(
        width: DesktopLayoutTokens.chromeControlHeight,
        height: DesktopLayoutTokens.chromeControlHeight,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      NotePreferenceMutationStatus.error => const Tooltip(
        message: 'Não foi possível salvar a preferência',
        child: Icon(Icons.error_outline, size: 20),
      ),
    };
  }
}

// Compact horizontal toolbar for the note editor.
//
// The toolbar requests formatting presentation from its parent. It does not
// own formatting state, keyboard state, or focus.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'note_editor_interaction.dart';
import 'note_toolbar_button.dart';
import 'selection_formatting.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

class NoteToolbar extends StatelessWidget {
  const NoteToolbar({
    super.key,
    required this.editor,
    required this.composer,
    required this.onOpenFormatting,
    this.onAttachFile,
    this.onAttachImage,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final VoidCallback onOpenFormatting;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 8,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ToolbarButton(
                      icon: Icons.text_format,
                      isActive: false,
                      haptic: ToolbarHaptic.controlTap,
                      onPressed: onOpenFormatting,
                      semanticLabel: 'Abrir formatação',
                    ),
                    const ToolbarDivider(),
                    ToolbarButton(
                      icon: Icons.horizontal_rule,
                      isActive: false,
                      haptic: ToolbarHaptic.selectionChange,
                      onPressed: _insertDivider,
                    ),
                    const ToolbarDivider(),
                    ToolbarButton(
                      icon: Icons.image,
                      isActive: false,
                      haptic: ToolbarHaptic.controlTap,
                      onPressed: onAttachImage,
                    ),
                    ToolbarButton(
                      icon: Icons.attach_file,
                      isActive: false,
                      haptic: ToolbarHaptic.controlTap,
                      onPressed: onAttachFile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _insertDivider() {
    final selection = composer.selection;
    if (selection == null ||
        !isEditorSelectionValid(editor.context.document, selection)) {
      NoteEditorCommands.insertDividerAtEnd(editor, dividerCount: 35);
      return;
    }
    NoteEditorCommands.insertDivider(editor, dividerCount: 35);
  }
}

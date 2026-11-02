import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_box_blocks.dart';
import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:url_launcher/url_launcher.dart';

/// Type sizes and spacing of the note editor, shared by every block.
///
/// These are the metrics of the previous editor's mobile stylesheet, so notes
/// look the same after the switch.
abstract final class NoteEditorMetrics {
  static const bodySize = 17.0;
  static const h1Size = 32.0;
  static const h2Size = 26.0;
  static const h3Size = 22.0;
  static const quoteSize = 20.0;
  static const lineHeight = 1.4;
  static const horizontalPadding = 24.0;

  /// Width of one indentation level (2.4 × body size).
  static const indentUnit = bodySize * 0.6 * 4;

  /// Gap between a list marker or checkbox and its text.
  static const markerGap = 8.0;
}

/// What happens when the user taps a link inside the text.
final class NoteLinkHandler {
  const NoteLinkHandler({
    this.onNoteTap,
    this.allowInternalNoteLinks = true,
    this.webOnly = false,
  });

  /// Opens another note (`note://<id>` links).
  final void Function(String noteId)? onNoteTap;

  /// Whether `note://` links are followed.
  final bool allowInternalNoteLinks;

  /// Whether only http(s) links open (public share pages).
  final bool webOnly;

  /// Follows [href], or returns false when it is not allowed here.
  bool open(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) return false;
    if (uri.scheme == 'note') {
      if (!allowInternalNoteLinks || onNoteTap == null) return false;
      onNoteTap!(href.replaceFirst('note://', ''));
      return true;
    }
    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    if (webOnly && !isWeb) return false;
    unawaited(_launch(uri));
    return true;
  }

  static Future<void> _launch(Uri uri) async {
    try {
      if (await launchUrl(uri)) return;
      throw StateError('Could not launch linked URI: $uri');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'supanotes note editor',
          context: ErrorDescription('while opening a note link'),
        ),
      );
    }
  }
}

/// The editor-wide style: fonts, colors and link rendering.
EditorStyle noteEditorStyle(
  BuildContext context, {
  required NoteLinkHandler links,
  EdgeInsets padding = const EdgeInsets.symmetric(
    horizontal: NoteEditorMetrics.horizontalPadding,
  ),
}) {
  final scheme = Theme.of(context).colorScheme;
  return EditorStyle.mobile(
    padding: padding,
    cursorColor: scheme.primary,
    dragHandleColor: scheme.primary,
    selectionColor: scheme.primary.withValues(alpha: 0.25),
    textStyleConfiguration: TextStyleConfiguration(
      text: TextStyle(
        color: scheme.onSurface,
        fontSize: NoteEditorMetrics.bodySize,
        height: NoteEditorMetrics.lineHeight,
      ),
      lineHeight: NoteEditorMetrics.lineHeight,
      href: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
    ),
    textSpanDecorator: (context, node, index, text, before, after) {
      final href = text.attributes?[AppFlowyRichTextKeys.href] as String?;
      if (href == null) return before;
      final isNoteLink = href.startsWith('note://');
      return TextSpan(
        text: text.text,
        style: isNoteLink
            ? before.style?.copyWith(
                color: scheme.onPrimary,
                decoration: TextDecoration.none,
                background: Paint()..color = scheme.primary,
              )
            : before.style,
        recognizer: TapGestureRecognizer()..onTap = () => links.open(href),
      );
    },
  );
}

/// Block renderers for every SupaNotes block type.
Map<String, BlockComponentBuilder> noteBlockBuilders(
  BuildContext context, {
  required NoteTaskActions taskActions,
  required bool readOnly,
  required bool hideCompleted,
  required bool collapseImages,
  AttachmentDelivery? attachmentDelivery,
  bool allowInternalNoteLinks = true,
  String placeholder = 'Escreva algo…',
}) {
  final scheme = Theme.of(context).colorScheme;
  final body = TextStyle(
    color: scheme.onSurface,
    fontSize: NoteEditorMetrics.bodySize,
    height: NoteEditorMetrics.lineHeight,
  );
  final placeholderStyle = body.copyWith(color: scheme.outline);

  bool isFirst(Node node) =>
      node.parent?.type == 'page' && node.path.first == 0;
  bool isListLike(Node? node) =>
      node != null &&
      (node.type == BulletedListBlockKeys.type ||
          node.type == NumberedListBlockKeys.type);

  EdgeInsets indent(Node node, TextDirection direction) =>
      direction == TextDirection.ltr
      ? const EdgeInsets.only(left: NoteEditorMetrics.indentUnit)
      : const EdgeInsets.only(right: NoteEditorMetrics.indentUnit);

  BlockComponentConfiguration config({
    required EdgeInsets Function(Node node) padding,
    TextStyle? style,
    String Function(Node node)? placeholderText,
  }) => BlockComponentConfiguration(
    padding: padding,
    indentPadding: indent,
    textStyle: (node, {textSpan}) => style ?? body,
    placeholderTextStyle: (node, {textSpan}) =>
        (style ?? body).copyWith(color: scheme.outline),
    placeholderText: placeholderText ?? (_) => ' ',
  );

  final listPadding = (Node node) => EdgeInsets.only(
    top: 8,
    // The last item of a list keeps some air before the next block.
    bottom: isListLike(node.next) || node.children.isNotEmpty ? 0 : 12,
  );

  TextStyle heading(double size) => body.copyWith(
    fontSize: size,
    fontWeight: FontWeight.bold,
    height: 1.25,
  );

  return {
    PageBlockKeys.type: PageBlockComponentBuilder(),
    ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
      configuration: config(
        padding: (node) => EdgeInsets.only(top: isFirst(node) ? 0 : 16),
        // Hint only on an empty note, like the previous editor.
        placeholderText: (node) =>
            node.path.first == 0 && node.next == null ? placeholder : ' ',
      ).copyWith(placeholderTextStyle: (node, {textSpan}) => placeholderStyle),
    ),
    HeadingBlockKeys.type: HeadingBlockComponentBuilder(
      configuration: config(
        padding: (node) {
          final level = node.attributes[HeadingBlockKeys.level] as int? ?? 1;
          final top = switch (level) {
            1 => 24.0,
            2 => 20.0,
            _ => 16.0,
          };
          return EdgeInsets.only(
            top: isFirst(node) ? 0 : top,
            bottom: level == 3 ? 8 : 12,
          );
        },
      ),
      textStyleBuilder: (level) => heading(switch (level) {
        1 => NoteEditorMetrics.h1Size,
        2 => NoteEditorMetrics.h2Size,
        _ => NoteEditorMetrics.h3Size,
      }),
    ),
    QuoteBlockKeys.type: QuoteBlockComponentBuilder(
      configuration: config(
        padding: (_) => const EdgeInsets.symmetric(vertical: 8),
        style: body.copyWith(
          fontSize: NoteEditorMetrics.quoteSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      iconBuilder: (context, node) => Container(
        width: 3,
        margin: const EdgeInsetsDirectional.only(
          end: NoteEditorMetrics.markerGap + 4,
        ),
        decoration: BoxDecoration(
          color: scheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
    BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
      configuration: config(padding: listPadding),
      iconBuilder: (context, node) => _ListMarker(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.onSurface,
          ),
        ),
      ),
    ),
    NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
      configuration: config(padding: listPadding),
      iconBuilder: (context, node, direction) => _ListMarker(
        alignment: AlignmentDirectional.centerStart,
        child: Text('${_listIndex(node)}.', style: body),
      ),
    ),
    TodoListBlockKeys.type: NoteTaskBlockComponentBuilder(
      actions: taskActions,
      readOnly: readOnly,
      hideCompleted: hideCompleted,
      configuration: config(padding: (_) => const EdgeInsets.only(top: 14)),
    ),
    DividerBlockKeys.type: noteDividerBlockBuilder()
      ..configuration = BlockComponentConfiguration(
        padding: (_) => const EdgeInsets.symmetric(vertical: 4),
      ),
    NoteNodeTypes.attachment: noteAttachmentBlockBuilder(
      collapseImages: collapseImages,
      readOnly: readOnly,
      attachmentDelivery: attachmentDelivery,
    ),
    NoteNodeTypes.richLink: noteRichLinkBlockBuilder(
      allowInternalNoteLinks: allowInternalNoteLinks,
    ),
  };
}

/// 1-based position of [node] among the consecutive numbered items around it.
int _listIndex(Node node) {
  var index = 1;
  var previous = node.previous;
  while (previous != null && previous.type == NumberedListBlockKeys.type) {
    index++;
    previous = previous.previous;
  }
  return index;
}

/// A list marker box as tall as the first line of text.
class _ListMarker extends StatelessWidget {
  const _ListMarker({
    required this.child,
    this.alignment = AlignmentDirectional.center,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: NoteEditorMetrics.bodySize * NoteEditorMetrics.lineHeight,
    margin: const EdgeInsetsDirectional.only(end: NoteEditorMetrics.markerGap),
    alignment: alignment,
    child: child,
  );
}

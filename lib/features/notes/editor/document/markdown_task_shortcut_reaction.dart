import 'package:super_editor/super_editor.dart';

/// Converts an empty Markdown task prefix into an incomplete task node.
///
/// Supported prefixes are `[] ` and `- [ ] `.
class MarkdownTaskShortcutConversionReaction
    extends ParagraphPrefixConversionReaction {
  static final _taskPrefix = RegExp(r'^(?:\[\]|- \[ \]) ');

  const MarkdownTaskShortcutConversionReaction();

  @override
  RegExp get pattern => _taskPrefix;

  @override
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  ) {
    requestDispatcher.execute([
      DeleteContentRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            nodeId: paragraph.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
          end: DocumentPosition(
            nodeId: paragraph.id,
            nodePosition: TextNodePosition(offset: match.length),
          ),
        ),
      ),
      ConvertParagraphToTaskRequest(nodeId: paragraph.id),
    ]);
  }
}

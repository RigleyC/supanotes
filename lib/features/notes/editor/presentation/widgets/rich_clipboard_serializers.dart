import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

bool _isConfigured = false;

void configureRichClipboardSerializers() {
  if (_isConfigured) return;
  _isConfigured = true;

  SuperEditorClipboardConfig.setNodeHtmlSerializers([
    _taskNodeToHtml,
    ...defaultNodeHtmlSerializerChain,
  ]);
}

String? _taskNodeToHtml(
  Document document,
  DocumentNode node,
  NodeSelection? selection,
  InlineHtmlSerializerChain inlineSerializers,
) {
  if (node is! TaskNode) return null;
  if (selection != null && selection is! TextNodeSelection) return null;

  final textSelection = selection as TextNodeSelection?;
  if (textSelection?.isCollapsed == true) return '';

  final content = node.text.toHtml(
    serializers: inlineSerializers,
    start: textSelection?.start,
    end: textSelection?.end,
  );
  final checked = node.isComplete ? ' checked' : '';
  return '<ul class="task-list"><li><input type="checkbox"$checked> '
      '$content</li></ul>';
}

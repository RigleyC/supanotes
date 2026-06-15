library;

import 'package:markdown/markdown.dart' as md hide Document;
import 'package:super_editor/super_editor.dart';

const String _kTaskIdMarkerPrefix = '<!-- task:';
const String _kTaskIdMarkerSuffix = ' -->';

final RegExp _taskIdMarkerRegExp = RegExp(
  r'<!--\s*task:(.*?)\s*-->',
);

MutableDocument parseNoteToMarkdown(String markdown) {
  final doc = deserializeMarkdownToDocument(
    markdown,
    customBlockSyntax: [
      _DividerWithMetadataSyntax(),
    ],
    customElementToNodeConverters: [
      const _TaskElementConverter(),
      _DividerElementConverter(),
    ],
  );

  final nodes = doc.toList(growable: true);

  if (nodes.last is! ParagraphNode) {
    nodes.add(ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(''),
    ));
  }

  return MutableDocument(nodes: nodes);
}

String serializeNoteToMarkdown(MutableDocument doc) {
  return serializeDocumentToMarkdown(
    doc,
    syntax: MarkdownSyntax.superEditor,
    customNodeSerializers: [
      const _TaskNodeSerializer(),
      _DividerNodeSerializer(),
    ],
  ).trimRight();
}

class _TaskNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<TaskNode> {
  const _TaskNodeSerializer();

  @override
  String doSerialization(Document document, TaskNode node, {NodeSelection? selection}) {
    if (selection != null && selection is! TextNodeSelection) return '';
    final textSelection = selection as TextNodeSelection?;
    if (textSelection != null && textSelection.isCollapsed) return '';
    final textToConvert = textSelection != null
        ? node.text.copyText(textSelection.start, textSelection.end)
        : node.text;
    final idMarker = ' $_kTaskIdMarkerPrefix${node.id}$_kTaskIdMarkerSuffix';
    return '- [${node.isComplete ? 'x' : ' '}] ${textToConvert.toMarkdown()}$idMarker';
  }
}

class _DividerNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<HorizontalRuleNode> {
  @override
  String doSerialization(Document document, HorizontalRuleNode node, {NodeSelection? selection}) {
    final index = node.getMetadataValue('dividerIndex') ?? 1;
    return '--- <!-- divider:${node.id}|index:$index -->';
  }
}

class _DividerWithMetadataSyntax extends md.BlockSyntax {
  static final _pattern = RegExp(r'^---\s+<!--\s*divider:(.*?)\s*-->$');

  @override
  RegExp get pattern => _pattern;

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = _pattern.firstMatch(parser.current.content);
    parser.advance();

    final raw = match!.group(1)!;
    final id = raw.split('|').first;
    final indexMatch = RegExp(r'index:(\d+)').firstMatch(raw);
    final index = indexMatch != null ? int.parse(indexMatch.group(1)!) : 1;

    return md.Element('hr-divider', [])
      ..attributes['id'] = id
      ..attributes['index'] = '$index';
  }
}

class _DividerElementConverter implements ElementToNodeConverter {
  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.tag != 'hr-divider') return null;

    final id = element.attributes['id'] ?? Editor.createNodeId();
    final index = int.tryParse(element.attributes['index'] ?? '') ?? 1;

    return HorizontalRuleNode(
      id: id,
      metadata: {'dividerIndex': index},
    );
  }
}

class _TaskElementConverter implements ElementToNodeConverter {
  const _TaskElementConverter();

  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.tag != 'li' || element.attributes['class'] != 'task-list-item') {
      return null;
    }

    final textContent = element.textContent;
    final idMatch = _taskIdMarkerRegExp.firstMatch(textContent);
    final taskId = idMatch?.group(1) ?? Editor.createNodeId();
    final cleanText = textContent.replaceFirst(_taskIdMarkerRegExp, '').trim();

    bool checked = false;
    if (element.children != null && element.children!.isNotEmpty && element.children!.first is md.Element) {
      final firstChild = element.children!.first as md.Element;
      if (firstChild.tag == 'input') {
        checked = firstChild.attributes['checked'] == 'true';
      }
    }

    return TaskNode(
      id: taskId,
      text: parseInlineMarkdown(cleanText),
      isComplete: checked,
    );
  }
}

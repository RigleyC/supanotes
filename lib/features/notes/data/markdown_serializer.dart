library;

import 'package:markdown/markdown.dart' as md hide Document;
import 'package:super_editor/super_editor.dart';

const String _kTaskIdMarkerPrefix = '<!-- task:';
const String _kTaskIdMarkerSuffix = ' -->';

final RegExp _taskIdMarkerRegExp = RegExp(r'<!--\s*task:(.*?)\s*-->');

MutableDocument parseNoteToMarkdown(String markdown) {
  final doc = deserializeMarkdownToDocument(
    markdown,
    customBlockSyntax: [_DividerWithMetadataSyntax()],
    customElementToNodeConverters: [
      const _TaskElementConverter(),
      _DividerElementConverter(),
    ],
  );

  final nodes = _normalizeListsAfterTasks(doc.toList(growable: true));

  if (nodes.last is! ParagraphNode) {
    nodes.add(
      ParagraphNode(id: Editor.createNodeId(), text: AttributedText('')),
    );
  }

  return MutableDocument(nodes: nodes);
}

List<DocumentNode> _normalizeListsAfterTasks(List<DocumentNode> nodes) {
  final normalized = <DocumentNode>[];
  var followsTask = false;

  for (final node in nodes) {
    if (node is ListItemNode && followsTask && node.indent > 0) {
      normalized.add(node.copyListItemWith(indent: node.indent - 1));
    } else {
      normalized.add(node);
    }

    followsTask = node is TaskNode || (followsTask && node is ListItemNode);
  }

  return normalized;
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

class _TaskNodeSerializer
    extends NodeTypedDocumentNodeMarkdownSerializer<TaskNode> {
  const _TaskNodeSerializer();

  @override
  String doSerialization(
    Document document,
    TaskNode node, {
    NodeSelection? selection,
  }) {
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

class _DividerNodeSerializer
    extends NodeTypedDocumentNodeMarkdownSerializer<HorizontalRuleNode> {
  @override
  String doSerialization(
    Document document,
    HorizontalRuleNode node, {
    NodeSelection? selection,
  }) {
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

    return HorizontalRuleNode(id: id, metadata: {'dividerIndex': index});
  }
}

class _TaskElementConverter implements ElementToNodeConverter {
  const _TaskElementConverter();

  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.tag != 'li' ||
        element.attributes['class'] != 'task-list-item') {
      return null;
    }

    // markdown v7.3+ may parse `<!-- task:... -->` as an inline HTML element
    // (via InlineHtmlSyntax) rather than plain text, so the marker may not
    // appear in the task paragraph text. Read only the task's own paragraph,
    // not nested lists, or child bullets get folded into the task text.
    final taskChildren = _taskTextChildren(element);
    final textContent = taskChildren.map((child) => child.textContent).join();
    var idMatch = _taskIdMarkerRegExp.firstMatch(textContent);
    String? taskId = idMatch?.group(1);

    final filteredChildren = <md.Node>[];
    bool checked = false;
    if (taskChildren.isNotEmpty) {
      for (final child in taskChildren) {
        if (child is md.Element && child.tag == 'input') {
          checked = child.attributes['checked'] == 'true';
          continue;
        }
        if (idMatch == null && child is md.Element) {
          final childText = child.textContent;
          final childMatch = _taskIdMarkerRegExp.firstMatch(childText);
          if (childMatch != null) {
            idMatch = childMatch;
            taskId = childMatch.group(1);
            continue;
          }
        }
        filteredChildren.add(child);
      }
    }

    taskId ??= Editor.createNodeId();

    final filteredText = filteredChildren.map((c) => c.textContent).join();
    final cleanText = filteredText.replaceFirst(_taskIdMarkerRegExp, '').trim();

    final node = TaskNode(
      id: taskId,
      text: parseInlineMarkdown(cleanText),
      isComplete: checked,
    );
    _removeTaskTextChildren(element);
    return node;
  }

  List<md.Node> _taskTextChildren(md.Element element) {
    final children = element.children;
    if (children == null || children.isEmpty) {
      return const [];
    }

    final firstChild = children.first;
    if (firstChild is md.Element && firstChild.tag == 'p') {
      return firstChild.children ?? const [];
    }

    return children
        .where((child) {
          return child is! md.Element ||
              (child.tag != 'ul' && child.tag != 'ol');
        })
        .toList(growable: false);
  }

  void _removeTaskTextChildren(md.Element element) {
    final children = element.children;
    if (children == null || children.isEmpty) {
      return;
    }

    final firstChild = children.first;
    if (firstChild is md.Element && firstChild.tag == 'p') {
      children.removeAt(0);
      return;
    }

    children.removeWhere((child) {
      return child is! md.Element || (child.tag != 'ul' && child.tag != 'ol');
    });
  }
}

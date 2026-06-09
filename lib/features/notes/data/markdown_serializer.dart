/// Bidirectional serializer between a `super_editor` [MutableDocument] and
/// a markdown text body.
///
/// This is the contract that downstream feature agents (note editor,
/// inbox screen) will rely on for both display and persistence:
///
///   * `parseMarkdownToDocument` converts the raw text stored in the
///     Drift `notes.content` column into the rich-document tree that
///     `SuperEditor` can render and edit.
///   * `serializeDocumentToMarkdown` does the reverse — the editor's
///     current state is flattened back to a markdown string for storage
///     and for the `/sync/push` payload.
///
/// Round-tripping is best-effort but stable for the supported syntax set:
///   * `# H1`, `## H2`, `### H3` → `ParagraphNode` with the matching
///     header block attribution
///   * `**bold**` and `*italic*` → inline `AttributedSpans` (bold / italic)
///   * `- bullet` → `ListItemNode` (unordered)
///   * `1. numbered` → `ListItemNode` (ordered)
///   * `> quote` → `ParagraphNode` with the block-quote attribution
///   * `- [ ] task` and `- [x] task` → `TaskNode`
///   * blank lines and any other line → `ParagraphNode`
///
/// `TaskNode` instances preserve their stable id via a hidden HTML-style
/// marker — `<!-- task:UUID -->` — appended at the end of the text. The
/// existing inbox/note editor code already reads / writes that marker; the
/// serializer transparently strips it on parse and reinjects it on
/// serialize so existing notes round-trip without losing task ids.
library;

import 'package:super_editor/super_editor.dart';

/// Marker used to round-trip `TaskNode` ids through markdown storage.
///
/// Matches the literal `<!-- task:UUID -->` form, where `UUID` is whatever
/// id `Editor.createNodeId()` produced (any non-greedy characters).
const String _kTaskIdMarkerPrefix = '<!-- task:';
const String _kTaskIdMarkerSuffix = ' -->';

final RegExp _taskIdMarkerRegExp = RegExp(
  r'<!--\s*task:(.*?)\s*-->',
);

/// Builds a [MutableDocument] tree from a markdown [markdown] string.
MutableDocument parseMarkdownToDocument(String markdown) {
  if (markdown.isEmpty) {
    return MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(''),
        ),
      ],
    );
  }

  final lines = markdown.split('\n');
  final nodes = <DocumentNode>[];

  for (final rawLine in lines) {
    if (rawLine.trim().isEmpty) continue;

    final line = rawLine.trim();

    // Headers — represented as ParagraphNode with header block-attribution.
    if (line.startsWith('### ')) {
      nodes.add(ParagraphNode(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(line.substring(4)),
        metadata: const {'blockType': header3Attribution},
      ));
      continue;
    }
    if (line.startsWith('## ')) {
      nodes.add(ParagraphNode(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(line.substring(3)),
        metadata: const {'blockType': header2Attribution},
      ));
      continue;
    }
    if (line.startsWith('# ')) {
      nodes.add(ParagraphNode(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(line.substring(2)),
        metadata: const {'blockType': header1Attribution},
      ));
      continue;
    }

    // Block quote.
    if (line.startsWith('> ')) {
      nodes.add(ParagraphNode(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(line.substring(2)),
        metadata: const {'blockType': blockquoteAttribution},
      ));
      continue;
    }

    // Task list.
    if (line.startsWith('- [ ] ') || line.startsWith('- [x] ')) {
      final isComplete = line.startsWith('- [x] ');
      var text = line.substring(6);
      String id = Editor.createNodeId();

      final idMatch = _taskIdMarkerRegExp.firstMatch(text);
      if (idMatch != null) {
        id = idMatch.group(1)!;
        text = text.replaceFirst(idMatch.group(0)!, '').trim();
      }

      nodes.add(TaskNode(
        id: id,
        text: _applyInlineFormatting(text),
        isComplete: isComplete,
      ));
      continue;
    }

    // Unordered list.
    if (line.startsWith('- ')) {
      nodes.add(ListItemNode.unordered(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(line.substring(2)),
      ));
      continue;
    }

    // Ordered list — `1.`, `2.`, …
    final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
    if (orderedMatch != null) {
      nodes.add(ListItemNode.ordered(
        id: Editor.createNodeId(),
        text: _applyInlineFormatting(orderedMatch.group(2)!),
      ));
      continue;
    }

    // Fallback: plain paragraph.
    nodes.add(ParagraphNode(
      id: Editor.createNodeId(),
      text: _applyInlineFormatting(line),
    ));
  }

  if (nodes.isEmpty) {
    nodes.add(ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(''),
    ));
  }

  // UX: sempre termina com um parágrafo vazio para que o usuário
  // consiga colocar o cursor após a última task/lista e continuar
  // digitando normalmente.
  if (nodes.last is! ParagraphNode) {
    nodes.add(ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(''),
    ));
  }

  return MutableDocument(nodes: nodes);
}

/// Serializes a [MutableDocument] tree back to its markdown string form.
String serializeDocumentToMarkdown(MutableDocument doc) {
  final buffer = StringBuffer();
  for (final node in doc) {
    if (node is TaskNode) {
      final marker = node.isComplete ? 'x' : ' ';
      final idMarker =
          ' $_kTaskIdMarkerPrefix${node.id}$_kTaskIdMarkerSuffix';
      buffer.writeln('- [$marker] ${node.text.toPlainText()}$idMarker');
    } else if (node is ListItemNode) {
      final plain = node.text.toPlainText();
      switch (node.type) {
        case ListItemType.unordered:
          buffer.writeln('- $plain');
        case ListItemType.ordered:
          buffer.writeln('1. $plain');
      }
    } else if (node is ParagraphNode) {
      final plain = node.text.toPlainText();
      final blockType = node.getMetadataValue('blockType');
      if (blockType == header1Attribution) {
        buffer.writeln('# $plain');
      } else if (blockType == header2Attribution) {
        buffer.writeln('## $plain');
      } else if (blockType == header3Attribution) {
        buffer.writeln('### $plain');
      } else if (blockType == blockquoteAttribution) {
        buffer.writeln('> $plain');
      } else if (plain.isEmpty) {
        // Skip empty paragraphs to keep the document compact.
        continue;
      } else {
        buffer.writeln(plain);
      }
    } else if (node is TextNode) {
      // Generic fallback for any other text-bearing node we might add.
      buffer.writeln(node.text.toPlainText());
    }
  }

  // Trim trailing newlines so callers can store the result directly.
  final result = buffer.toString().trimRight();
  return result;
}

/// Applies the supported inline formatting (`**bold**`, `*italic*`) to
/// [source] and returns the resulting [AttributedText].
///
/// Markdown markers are stripped from the output; their semantics are
/// encoded into the [AttributedSpans] of the resulting text instead.
AttributedText _applyInlineFormatting(String source) {
  final spans = AttributedSpans();
  final text = StringBuffer();
  var i = 0;
  var bold = false;
  var italic = false;

  // Build attributed text by walking the source character by character.
  // We track open `*` and `**` runs and toggle attributes accordingly.
  while (i < source.length) {
    final remaining = source.substring(i);

    if (remaining.startsWith('**')) {
      bold = !bold;
      i += 2;
      continue;
    }
    if (remaining.startsWith('*')) {
      italic = !italic;
      i += 1;
      continue;
    }

    final start = text.length;
    text.write(source[i]);
    final end = text.length;
    if (bold) {
      spans.addAttribution(
        newAttribution: boldAttribution,
        start: start,
        end: end,
      );
    }
    if (italic) {
      spans.addAttribution(
        newAttribution: italicsAttribution,
        start: start,
        end: end,
      );
    }
    i += 1;
  }

  return AttributedText(text.toString(), spans);
}

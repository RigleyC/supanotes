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
///   * `**bold**`, `*italic*`, `~strikethrough~` → inline `AttributedSpans`
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
      buffer.writeln('- [$marker] ${_serializeInlineFormatting(node.text)}$idMarker');
    } else if (node is ListItemNode) {
      final plain = _serializeInlineFormatting(node.text);
      switch (node.type) {
        case ListItemType.unordered:
          buffer.writeln('- $plain');
        case ListItemType.ordered:
          buffer.writeln('1. $plain');
      }
    } else if (node is ParagraphNode) {
      final plain = _serializeInlineFormatting(node.text);
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
      buffer.writeln(_serializeInlineFormatting(node.text));
    }
  }

  // Trim trailing newlines so callers can store the result directly.
  final result = buffer.toString().trimRight();
  return result;
}

/// Serializes inline attributions (bold, italic, strikethrough) in [text]
/// back to their markdown markers: `**bold**`, `*italic*`, `~strikethrough~`.
///
/// The algorithm works in a single pass over character positions:
/// 1. For each position, collect which attributions start or end there.
/// 2. Emit closing markers for attributions that end (in reverse open order).
/// 3. Emit opening markers for attributions that start.
/// 4. Write the plain character.
///
/// Overlapping spans (e.g. bold+italic on the same range) are handled
/// correctly because each attribution's open/close markers are tracked
/// independently.
String _serializeInlineFormatting(AttributedText text) {
  final plain = text.toPlainText();
  if (plain.isEmpty) return plain;

  // Collect all spans for the three supported attributions.
  final range = SpanRange(0, plain.length);
  final boldSpans = text.getAttributionSpansInRange(
    attributionFilter: (a) => a == boldAttribution,
    range: range,
  );
  final italicSpans = text.getAttributionSpansInRange(
    attributionFilter: (a) => a == italicsAttribution,
    range: range,
  );
  final strikeSpans = text.getAttributionSpansInRange(
    attributionFilter: (a) => a == strikethroughAttribution,
    range: range,
  );

  if (boldSpans.isEmpty && italicSpans.isEmpty && strikeSpans.isEmpty) {
    return plain;
  }

  // Build a map of position → list of (marker, isOpen) events.
  // Events at the same position are sorted: closes before opens so that
  // `**bold *bold-italic***` doesn't produce malformed nesting.
  final events = <int, List<(String, bool)>>{};
  void addEvent(int pos, String marker, bool isOpen) {
    events.putIfAbsent(pos, () => []).add((marker, isOpen));
  }

  for (final s in boldSpans) {
    addEvent(s.start, '**', true);
    addEvent(s.end, '**', false);
  }
  for (final s in italicSpans) {
    addEvent(s.start, '*', true);
    addEvent(s.end, '*', false);
  }
  for (final s in strikeSpans) {
    addEvent(s.start, '~', true);
    addEvent(s.end, '~', false);
  }

  final buffer = StringBuffer();
  for (var i = 0; i <= plain.length; i++) {
    final evs = events[i];
    if (evs != null) {
      // Emit closes first, then opens.
      for (final (marker, _) in evs.where((e) => !e.$2)) {
        buffer.write(marker);
      }
      for (final (marker, _) in evs.where((e) => e.$2)) {
        buffer.write(marker);
      }
    }
    if (i < plain.length) buffer.write(plain[i]);
  }
  return buffer.toString();
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
  var strikethrough = false;

  while (i < source.length) {
    final remaining = source.substring(i);

    if (remaining.startsWith('**')) {
      bold = !bold;
      i += 2;
      continue;
    }
    if (remaining.startsWith('~')) {
      strikethrough = !strikethrough;
      i += 1;
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
    if (strikethrough) {
      spans.addAttribution(
        newAttribution: strikethroughAttribution,
        start: start,
        end: end,
      );
    }
    i += 1;
  }

  return AttributedText(text.toString(), spans);
}

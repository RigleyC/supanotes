import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:super_editor/super_editor.dart';

class _CodeNodeSerializer implements DocumentNodeMarkdownSerializer {
  @override
  String? serialize(Document document, DocumentNode node, {NodeSelection? selection}) {
    if (node is ParagraphNode && node.metadata['blockType'] == const NamedAttribution('code')) {
      // It's a code block
      final text = node.text.toPlainText();
      // super_editor's default paragraph serializer escapes markdown characters.
      // For code block, we just want to wrap it in triple backticks.
      return '```\n\$text\n```';
    }
    return null; // Let other serializers handle it
  }
}

void main() {
  test('Markdown serialization stability', () {
    final markdown = '''
- [ ] Task 1
Line 2
Line 3 <!-- task:id1 -->

```
Line A
Line B
```
''';

    var currentMarkdown = markdown;
    for (int i = 1; i <= 3; i++) {
      final doc = parseNoteToMarkdown(currentMarkdown);
      
      final reserialized = serializeDocumentToMarkdown(
        doc,
        syntax: MarkdownSyntax.superEditor,
        customNodeSerializers: [
          _CodeNodeSerializer(),
        ],
      ).trimRight();

      print('=== ITERATION \$i ===');
      print('Length: \${reserialized.length}');
      print(reserialized);
      currentMarkdown = reserialized;
    }
  });
}

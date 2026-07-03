import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  test('TaskNode excerpt test', () {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: '1',
        text: AttributedText('Comprar pao'),
        isComplete: false,
      ),
    ]);

    final fullText = document
        .where((n) => n is TextNode || n is TaskNode)
        .map((n) {
          if (n is TaskNode) {
            return '- [${n.isComplete ? 'x' : ' '}] ${n.text.toPlainText()}';
          }
          return (n as TextNode).text.toPlainText();
        })
        .join('\n');

    print('fullText: "$fullText"');
    expect(fullText.isNotEmpty, true);
    expect(fullText, '- [ ] Comprar pao');
  });
}

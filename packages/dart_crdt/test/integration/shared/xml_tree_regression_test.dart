import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('shared XML/tree regressions', () {
    test('emits deep events for nested attributes and text updates', () {
      final doc = Doc();
      final fragment = doc.get('xml', SharedTypeKind.xmlFragment);
      final events = <String>[];
      fragment.observeDeep((event) {
        events.add('${event.target.name}:${event.keys.join(',')}');
      });

      final article = fragment.appendXmlElement('article')
        ..setAttr('data-id', 'a&b');
      final title = article.appendXmlElement('title')..appendXmlText('Hello');
      final body = article.appendXmlElement('body')..appendXmlText('One < Two');

      title.appendXmlText('!');
      body.setAttr('class', 'lead');

      expect(fragment.toXmlString(), contains('data-id="a&amp;b"'));
      expect(fragment.toXmlString(), contains('One &lt; Two'));
      expect(fragment.walkXmlTree().map((node) => node.name).toList(), [
        'xml',
        'article',
        'title',
        'body',
      ]);
      expect(events, contains('title:5'));
      expect(events, contains('body:class'));
    });

    test('keeps siblings correct after delete and clone operations', () {
      final fragment = SharedType(kind: SharedTypeKind.xmlFragment);
      final first = fragment.appendXmlElement('p')..appendXmlText('one');
      final middle = fragment.appendXmlElement('p')..appendXmlText('two');
      final last = fragment.appendXmlElement('p')..appendXmlText('three');

      fragment.delete(1);
      final clone = fragment.copy();
      last.appendXmlText('!');

      expect(middle.parent, isNull);
      expect(first.nextSibling, same(last));
      expect(last.previousSibling, same(first));
      expect(clone.toXmlString(), '<p>one</p><p>three</p>');
      expect(fragment.toXmlString(), '<p>one</p><p>three!</p>');
      expect(clone.firstChild!.parent, same(clone));
    });

    test('handles text nodes, scalar children, and XML escaping policy', () {
      final element = SharedType(kind: SharedTypeKind.xmlElement, name: 'root')
        ..appendXmlText('A & B')
        ..push(42)
        ..push(null)
        ..appendXmlElement('br');

      expect(element.firstChild!.name, 'br');
      expect(element.firstChild!.previousSibling, isNull);
      expect(element.toXmlString(), '<root>A &amp; B42<br/></root>');
    });
  });
}

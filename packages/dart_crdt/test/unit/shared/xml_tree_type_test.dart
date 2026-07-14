import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('SharedType XML/tree APIs', () {
    test('serializes XML elements with escaped attributes and text', () {
      final element = SharedType(kind: SharedTypeKind.xmlElement, name: 'note')
        ..setAttr('to', 'A&B"')
        ..setAttr('from', "C'D")
        ..appendXmlText('Hi <there> & ok');

      expect(
        element.toXmlString(),
        '<note to="A&amp;B&quot;" from="C&apos;D">'
        'Hi &lt;there&gt; &amp; ok</note>',
      );
      expect(element.toString(), element.toXmlString());
    });

    test('serializes fragments and exposes siblings', () {
      final fragment = SharedType(kind: SharedTypeKind.xmlFragment);
      final first = fragment.appendXmlElement('p')..appendXmlText('one');
      final breakElement = fragment.appendXmlElement('br');
      final second = fragment.appendXmlElement('p')..appendXmlText('two');

      expect(fragment.firstChild, same(first));
      expect(fragment.lastChild, same(second));
      expect(fragment.xmlChildren.toList(), [first, breakElement, second]);
      expect(first.nextSibling, same(breakElement));
      expect(breakElement.previousSibling, same(first));
      expect(breakElement.nextSibling, same(second));
      expect(second.nextSibling, isNull);
      expect(
        fragment.toXmlString(),
        '<p>one</p><br/><p>two</p>',
      );
    });

    test('inserts XML children after a reference node', () {
      final fragment = SharedType(kind: SharedTypeKind.xmlFragment);
      final first = SharedType(kind: SharedTypeKind.xmlElement, name: 'first');
      final middle =
          SharedType(kind: SharedTypeKind.xmlElement, name: 'middle');
      final last = SharedType(kind: SharedTypeKind.xmlElement, name: 'last');

      fragment
        ..insertXmlAfter(null, [middle])
        ..insertXmlAfter(null, [first])
        ..insertXmlAfter(middle, [last]);

      expect(fragment.xmlChildren.toList(), [first, middle, last]);
      expect(first.nextSibling, same(middle));
      expect(last.previousSibling, same(middle));
      expect(fragment.toXmlString(), '<first/><middle/><last/>');
      expect(
        () => fragment.insertXmlAfter(
          SharedType(kind: SharedTypeKind.xmlElement, name: 'detached'),
          [SharedType(kind: SharedTypeKind.xmlElement, name: 'unused')],
        ),
        throwsStateError,
      );
    });

    test('walks nested trees and clones independently', () {
      final fragment = SharedType(kind: SharedTypeKind.xmlFragment);
      final section = fragment.appendXmlElement('section');
      final title = section.appendXmlElement('title')..appendXmlText('Title');
      final paragraph = section.appendXmlElement('p')..appendXmlText('Body');

      final clone = fragment.copy();
      final clonedSection = clone.firstChild!;

      paragraph.appendXmlText(' updated');

      expect(
        fragment.walkXmlTree().toList(),
        [fragment, section, title, paragraph],
      );
      expect(clone.walkXmlTree().map((node) => node.name).toList(), [
        '',
        'section',
        'title',
        'p',
      ]);
      expect(clonedSection.parent, same(clone));
      expect(
        clone.toXmlString(),
        '<section><title>Title</title><p>Body</p></section>',
      );
      expect(fragment.toXmlString(), contains('Body updated'));
    });

    test('supports nested XML text nodes', () {
      final text = SharedType(kind: SharedTypeKind.xmlText)
        ..insertText(0, 'A & B');
      final element = SharedType(kind: SharedTypeKind.xmlElement, name: 'span')
        ..push(text);

      expect(text.toXmlString(), 'A &amp; B');
      expect(element.toXmlString(), '<span>A &amp; B</span>');
      expect(text.parent, same(element));
      expect(text.previousSibling, isNull);
    });

    test('rejects malformed XML element and attribute names', () {
      expect(
        () => SharedType(kind: SharedTypeKind.xmlElement, name: 'bad name'),
        throwsArgumentError,
      );

      final element = SharedType(kind: SharedTypeKind.xmlElement, name: 'ok')
        ..setAttr('bad name', 'value');

      expect(element.toXmlString, throwsArgumentError);
    });
  });
}

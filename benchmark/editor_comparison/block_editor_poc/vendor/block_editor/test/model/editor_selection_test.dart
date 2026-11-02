import 'package:block_editor/src/model/editor_selection.dart';
import 'package:test/test.dart';

void main() {
  group('SelectionPoint', () {
    test('equality is structural', () {
      const a = SelectionPoint(blockId: 'b1', offset: 3);
      const b = SelectionPoint(blockId: 'b1', offset: 3);
      expect(a, equals(b));
    });

    test('copyWith replaces only specified fields', () {
      const original = SelectionPoint(blockId: 'b1', offset: 3);
      final copy = original.copyWith(offset: 7);
      expect(copy.blockId, 'b1');
      expect(copy.offset, 7);
    });

    test('different offsets are not equal', () {
      const a = SelectionPoint(blockId: 'b1', offset: 3);
      const b = SelectionPoint(blockId: 'b1', offset: 4);
      expect(a, isNot(equals(b)));
    });

    test('different block ids are not equal', () {
      const a = SelectionPoint(blockId: 'b1', offset: 3);
      const b = SelectionPoint(blockId: 'b2', offset: 3);
      expect(a, isNot(equals(b)));
    });
  });

  group('EditorSelection.none', () {
    test('is a NoSelection instance', () {
      expect(EditorSelection.none, isA<NoSelection>());
    });

    test('is the same instance on repeated access', () {
      expect(identical(EditorSelection.none, EditorSelection.none), isTrue);
    });
  });

  group('CollapsedSelection', () {
    const point = SelectionPoint(blockId: 'b1', offset: 5);

    test('equality is structural', () {
      const a = CollapsedSelection(point);
      const b = CollapsedSelection(point);
      expect(a, equals(b));
    });

    test('copyWith replaces point', () {
      const a = CollapsedSelection(point);
      const newPoint = SelectionPoint(blockId: 'b2', offset: 0);
      final b = a.copyWith(point: newPoint);
      expect(b.point, newPoint);
    });

    test('different points are not equal', () {
      const a = CollapsedSelection(SelectionPoint(blockId: 'b1', offset: 0));
      const b = CollapsedSelection(SelectionPoint(blockId: 'b1', offset: 1));
      expect(a, isNot(equals(b)));
    });
  });

  group('ExpandedSelection.resolveOrder', () {
    const ids = ['b1', 'b2', 'b3'];

    test('anchor before focus in document order — unchanged', () {
      const sel = ExpandedSelection(
        anchor: SelectionPoint(blockId: 'b1', offset: 2),
        focus: SelectionPoint(blockId: 'b3', offset: 1),
      );
      final resolved = sel.resolveOrder(ids);
      expect(resolved.start.blockId, 'b1');
      expect(resolved.end.blockId, 'b3');
    });

    test('focus before anchor in document order — swapped', () {
      const sel = ExpandedSelection(
        anchor: SelectionPoint(blockId: 'b3', offset: 0),
        focus: SelectionPoint(blockId: 'b1', offset: 4),
      );
      final resolved = sel.resolveOrder(ids);
      expect(resolved.start.blockId, 'b1');
      expect(resolved.end.blockId, 'b3');
    });

    test('same block, anchor offset before focus offset — unchanged', () {
      const sel = ExpandedSelection(
        anchor: SelectionPoint(blockId: 'b2', offset: 1),
        focus: SelectionPoint(blockId: 'b2', offset: 5),
      );
      final resolved = sel.resolveOrder(ids);
      expect(resolved.start.offset, 1);
      expect(resolved.end.offset, 5);
    });

    test('same block, focus offset before anchor offset — swapped', () {
      const sel = ExpandedSelection(
        anchor: SelectionPoint(blockId: 'b2', offset: 8),
        focus: SelectionPoint(blockId: 'b2', offset: 2),
      );
      final resolved = sel.resolveOrder(ids);
      expect(resolved.start.offset, 2);
      expect(resolved.end.offset, 8);
    });

    test('unknown block id — anchor treated as start', () {
      const sel = ExpandedSelection(
        anchor: SelectionPoint(blockId: 'unknown', offset: 0),
        focus: SelectionPoint(blockId: 'b1', offset: 0),
      );
      final resolved = sel.resolveOrder(ids);
      expect(resolved.start.blockId, 'unknown');
    });
  });

  group('ExpandedSelection', () {
    const a = SelectionPoint(blockId: 'b1', offset: 0);
    const b = SelectionPoint(blockId: 'b2', offset: 3);

    test('equality is structural', () {
      const x = ExpandedSelection(anchor: a, focus: b);
      const y = ExpandedSelection(anchor: a, focus: b);
      expect(x, equals(y));
    });

    test('copyWith replaces focus only', () {
      const x = ExpandedSelection(anchor: a, focus: b);
      const newFocus = SelectionPoint(blockId: 'b3', offset: 1);
      final y = x.copyWith(focus: newFocus);
      expect(y.anchor, a);
      expect(y.focus, newFocus);
    });

    test('swapped anchor and focus are not equal', () {
      const x = ExpandedSelection(anchor: a, focus: b);
      const y = ExpandedSelection(anchor: b, focus: a);
      expect(x, isNot(equals(y)));
    });
  });
}

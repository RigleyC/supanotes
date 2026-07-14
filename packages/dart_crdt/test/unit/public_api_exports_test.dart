import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  test('exports stable public placeholders and relative positions', () {
    expect(packageName, 'dart_crdt');

    final position = RelativePosition.root('body');

    expect(decodeRelativePosition(encodeRelativePosition(position)), position);
    expect(decodeSnapshot(encodeSnapshot(emptySnapshot)), emptySnapshot);
    expect(snapshotContainsUpdate(emptySnapshot, const [0, 0]), isTrue);
    expect(const SnapshotRestoreException('x').reason, 'x');
    expect(StackItem().isEmpty, isTrue);
    expect(noAttributionManager, isA<AttributionManager>());
    expect(Attributions.empty().isEmpty, isTrue);
    expect(Awareness(localClientId: ClientId(1)), isA<Awareness>());
    expect(
      createAttributionManagerFromSnapshots(emptySnapshot),
      isA<SnapshotAttributionManager>(),
    );
  });
}

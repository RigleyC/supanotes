import 'package:dart_crdt/src/events/event_handler.dart';
import 'package:test/test.dart';

void main() {
  group('EventHandler supplemental coverage', () {
    test('handles empty lifecycle and repeated cancellation', () {
      final handler = EventHandler<int>();
      final subscription = handler.add((_) {});

      handler
        ..clear()
        ..clear()
        ..emit(1);
      subscription.cancel();

      expect(subscription.isActive, isFalse);
      expect(handler.hasListeners, isFalse);
      expect(handler.listenerCount, 0);
    });

    test('formats single and multiple dispatch failures', () {
      final single = EventHandler<String>()
        ..add((_) => throw StateError('one'));
      final multiple = EventHandler<String>()
        ..add((_) => throw StateError('one'))
        ..add((_) => throw ArgumentError('two'));

      try {
        single.emit('x');
        fail('expected a dispatch exception');
      } on EventDispatchException<String> catch (error) {
        expect(error.toString(), contains('1 listener failed'));
        expect(error.toString(), contains("Instance of 'StateError'"));
      }

      try {
        multiple.emit('x');
        fail('expected a dispatch exception');
      } on EventDispatchException<String> catch (error) {
        expect(error.toString(), contains('2 listeners failed'));
        expect(error.toString(), contains("1: Instance of 'StateError'"));
        expect(error.toString(), contains("2: Instance of 'ArgumentError'"));
      }
    });
  });
}

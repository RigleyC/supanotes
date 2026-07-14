import 'package:dart_crdt/src/events/event_handler.dart';
import 'package:test/test.dart';

void main() {
  group('EventHandler', () {
    test('dispatches listeners in registration order', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      final first = handler.add((event) => calls.add('first:$event'));
      handler.add((event) => calls.add('second:$event'));

      expect(handler.hasListeners, isTrue);
      expect(handler.listenerCount, 2);

      handler.emit('a');
      first.cancel();
      handler.emit('b');

      expect(calls, ['first:a', 'second:a', 'second:b']);
      expect(first.isActive, isFalse);
      expect(handler.listenerCount, 1);

      handler.clear();

      expect(handler.hasListeners, isFalse);
      expect(handler.listenerCount, 0);
    });

    test('treats duplicate callback registrations independently', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      void record(String event) => calls.add(event);

      final first = handler.add(record);
      final second = handler.add(record);

      handler.emit('a');
      first.cancel();
      handler.emit('b');

      expect(calls, ['a', 'a', 'b']);
      expect(first.isActive, isFalse);
      expect(second.isActive, isTrue);
      expect(handler.listenerCount, 1);
    });

    test('does not dispatch new listeners until the next emit', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      var added = false;

      handler
        ..add((event) {
          calls.add('first:$event');
          if (!added) {
            added = true;
            handler.add((value) => calls.add('late:$value'));
          }
        })
        ..add((event) => calls.add('second:$event'));

      handler.emit('a');
      handler.emit('b');

      expect(calls, [
        'first:a',
        'second:a',
        'first:b',
        'second:b',
        'late:b',
      ]);
      expect(handler.listenerCount, 3);
    });

    test('dispatches one-shot listeners once and then cancels them', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      final subscription = handler.once((event) {
        calls.add('once:$event');
        handler.emit('nested');
      });
      handler.add((event) => calls.add('persistent:$event'));

      handler.emit('a');
      handler.emit('b');

      expect(calls, [
        'once:a',
        'persistent:nested',
        'persistent:a',
        'persistent:b',
      ]);
      expect(subscription.isActive, isFalse);
      expect(handler.listenerCount, 1);
    });

    test('skips listeners removed before their dispatch turn', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      late final EventSubscription second;

      handler.add((event) {
        calls.add('first:$event');
        second.cancel();
      });
      second = handler.add((event) => calls.add('second:$event'));
      handler.add((event) => calls.add('third:$event'));

      handler.emit('a');

      expect(calls, ['first:a', 'third:a']);
      expect(second.isActive, isFalse);
      expect(handler.listenerCount, 2);
    });

    test('removes the first active listener matching a callback', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      void record(String event) => calls.add(event);

      handler
        ..add(record)
        ..add(record);

      expect(handler.remove(record), isTrue);
      handler.emit('a');

      expect(calls, ['a']);
      expect(handler.remove(record), isTrue);
      expect(handler.remove(record), isFalse);
      expect(handler.listenerCount, 0);
    });

    test('continues dispatching after listener exceptions and cleans up', () {
      final handler = EventHandler<String>();
      final calls = <String>[];
      late final EventSubscription third;

      handler.add((event) {
        calls.add('first:$event');
        throw StateError('broken');
      });
      handler.add((event) {
        calls.add('second:$event');
        third.cancel();
      });
      third = handler.add((event) => calls.add('third:$event'));

      expect(
        () => handler.emit('a'),
        throwsA(
          isA<EventDispatchException<String>>()
              .having((error) => error.event, 'event', 'a')
              .having((error) => error.errors, 'errors', hasLength(1))
              .having(
                (error) => error.stackTraces,
                'stackTraces',
                hasLength(1),
              ),
        ),
      );

      expect(calls, ['first:a', 'second:a']);
      expect(third.isActive, isFalse);
      expect(handler.listenerCount, 2);
    });
  });
}

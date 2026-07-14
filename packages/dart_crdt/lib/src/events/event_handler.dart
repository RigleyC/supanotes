/// Synchronous observer registration and dispatch primitives.
library;

/// Handles one event notification.
typedef EventListener<TEvent> = void Function(TEvent event);

/// A cancellable event listener registration.
final class EventSubscription {
  EventSubscription._(this._onCancel);

  void Function()? _onCancel;
  bool _isActive = true;

  /// Whether this subscription is still registered.
  bool get isActive => _isActive;

  /// Cancels this subscription.
  void cancel() {
    if (!_isActive) {
      return;
    }

    _isActive = false;
    final onCancel = _onCancel;
    _onCancel = null;
    onCancel?.call();
  }
}

/// Failure thrown after one or more listeners fail during dispatch.
final class EventDispatchException<TEvent> implements Exception {
  EventDispatchException._({
    required this.event,
    required List<Object> errors,
    required List<StackTrace> stackTraces,
  })  : errors = List<Object>.unmodifiable(errors),
        stackTraces = List<StackTrace>.unmodifiable(stackTraces);

  /// Event value that was being dispatched.
  final TEvent event;

  /// Listener errors in dispatch order.
  final List<Object> errors;

  /// Stack traces aligned with [errors].
  final List<StackTrace> stackTraces;

  @override
  String toString() {
    final buffer = StringBuffer('EventDispatchException: ')
      ..write(errors.length)
      ..write(errors.length == 1 ? ' listener failed' : ' listeners failed');

    for (var index = 0; index < errors.length; index += 1) {
      buffer
        ..write('\n')
        ..write(index + 1)
        ..write(': ')
        ..write(Error.safeToString(errors[index]));
    }
    return buffer.toString();
  }
}

/// Synchronous event dispatcher with explicit listener lifecycle.
final class EventHandler<TEvent> {
  /// Creates an empty event handler.
  EventHandler();

  final List<_ListenerEntry<TEvent>> _listeners = <_ListenerEntry<TEvent>>[];
  var _dispatchDepth = 0;
  var _pendingCompaction = false;

  /// Whether at least one active listener is registered.
  bool get hasListeners => _listeners.any((entry) => entry.isActive);

  /// Number of active listeners currently registered.
  int get listenerCount {
    var count = 0;
    for (final entry in _listeners) {
      if (entry.isActive) {
        count += 1;
      }
    }
    return count;
  }

  /// Registers [listener] and returns its subscription.
  EventSubscription add(EventListener<TEvent> listener) {
    late final _ListenerEntry<TEvent> entry;
    final subscription = EventSubscription._(() => _removeEntry(entry));
    entry = _ListenerEntry<TEvent>(listener, subscription);
    _listeners.add(entry);
    return subscription;
  }

  /// Registers [listener] for only the next event.
  EventSubscription once(EventListener<TEvent> listener) {
    late final EventSubscription subscription;
    subscription = add((event) {
      subscription.cancel();
      listener(event);
    });
    return subscription;
  }

  /// Removes the first active registration that uses [listener].
  bool remove(EventListener<TEvent> listener) {
    for (var index = 0; index < _listeners.length; index += 1) {
      final entry = _listeners[index];
      if (entry.isActive && entry.listener == listener) {
        entry.subscription.cancel();
        return true;
      }
    }
    return false;
  }

  /// Cancels every active listener registration.
  void clear() {
    if (_listeners.isEmpty) {
      return;
    }

    final snapshot = List<_ListenerEntry<TEvent>>.of(_listeners);
    for (final entry in snapshot) {
      entry.subscription.cancel();
    }
    if (_dispatchDepth == 0) {
      _compactListeners();
    }
  }

  /// Dispatches [event] to active listeners in registration order.
  void emit(TEvent event) {
    if (!hasListeners) {
      return;
    }

    final snapshot = List<_ListenerEntry<TEvent>>.of(_listeners);
    final errors = <Object>[];
    final stackTraces = <StackTrace>[];
    _dispatchDepth += 1;
    try {
      for (final entry in snapshot) {
        if (!entry.isActive) {
          continue;
        }

        try {
          entry.listener(event);
        } on Object catch (error, stackTrace) {
          errors.add(error);
          stackTraces.add(stackTrace);
        }
      }
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && _pendingCompaction) {
        _compactListeners();
      }
    }

    if (errors.isNotEmpty) {
      throw EventDispatchException<TEvent>._(
        event: event,
        errors: errors,
        stackTraces: stackTraces,
      );
    }
  }

  void _removeEntry(_ListenerEntry<TEvent> entry) {
    if (_dispatchDepth > 0) {
      _pendingCompaction = true;
      return;
    }
    _listeners.remove(entry);
  }

  void _compactListeners() {
    _listeners.removeWhere((entry) => !entry.isActive);
    _pendingCompaction = false;
  }
}

final class _ListenerEntry<TEvent> {
  _ListenerEntry(this.listener, this.subscription);

  final EventListener<TEvent> listener;
  final EventSubscription subscription;

  bool get isActive => subscription.isActive;
}

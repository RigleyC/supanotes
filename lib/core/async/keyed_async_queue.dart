/// Serializes asynchronous operations independently for each key.
final class KeyedAsyncQueue {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String key, Future<T> Function() operation) {
    final previous = _tails[key] ?? Future<void>.value();
    final current = previous.then((_) => operation());
    final tail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[key] = tail;
    void removeTail() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }

    current.then<void>(
      (_) => removeTail(),
      onError: (Object _, StackTrace _) => removeTail(),
    );
    return current;
  }
}

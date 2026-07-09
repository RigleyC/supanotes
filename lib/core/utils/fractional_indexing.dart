import 'package:fractional_indexing_dart/fractional_indexing_dart.dart';

class FractionalIndex {
  static String between(String? prev, String? next) {
    // Treat empty string as null bounds for standard fractional indexing
    final a = (prev != null && prev.isNotEmpty) ? prev : null;
    final b = (next != null && next.isNotEmpty) ? next : null;
    return FractionalIndexing.generateKeyBetween(a, b);
  }
}

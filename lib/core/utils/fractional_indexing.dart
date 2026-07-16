import 'package:fractional_indexing_dart/fractional_indexing_dart.dart';

class FractionalIndex {
  static String between(String? prev, String? next, String clientId) {
    final prevBase = (prev != null && prev.isNotEmpty) ? prev.split('!').first : null;
    final nextBase = (next != null && next.isNotEmpty) ? next.split('!').first : null;
    
    // Defensive check: If positions are duplicated or out of order due to legacy data
    // fallback to generating a key after 'prevBase' to prevent the crash 'Exception: a >= b'.
    if (prevBase != null && nextBase != null && prevBase.compareTo(nextBase) >= 0) {
      final result = FractionalIndexing.generateKeyBetween(prevBase, null);
      return '$result!$clientId';
    }
    
    final result = FractionalIndexing.generateKeyBetween(prevBase, nextBase);
    return '$result!$clientId';
  }
}

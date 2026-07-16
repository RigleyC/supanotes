import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/utils/fractional_indexing.dart';

void main() {
  test('P1: B9 - Fractional index without salt (prevents identical key generation)', () {
    // Generate a first key with salt A
    final key1 = FractionalIndex.between(null, null, 'client-A');
    // base might be a0!client-A
    expect(key1, endsWith('!client-A'));
    
    // Generate a key with salt B at the exact same logical position (null, null)
    final key2 = FractionalIndex.between(null, null, 'client-B');
    expect(key2, endsWith('!client-B'));
    
    // They share the same base, so base is identical but their full strings are different
    expect(key1.split('!').first, key2.split('!').first);
    expect(key1 == key2, isFalse);
    
    // Now imagine both keys were generated concurrently and merged.
    // We want to insert between key1 and a hypothetical next key, or between key1 and key1 (if they collided)
    
    // If we try to insert between a0!client-A and a0!client-B, it should safely generate a valid key
    final betweenKeys = FractionalIndex.between(key1, key2, 'client-C');
    expect(betweenKeys, endsWith('!client-C'));
    
    // Test the defensive check: if we pass the same key twice (a >= b)
    final fallbackKey = FractionalIndex.between(key1, key1, 'client-D');
    expect(fallbackKey, endsWith('!client-D'));
    // The fallback key should be strictly greater than key1's base
    expect(fallbackKey.split('!').first.compareTo(key1.split('!').first) > 0, isTrue);
  });
}

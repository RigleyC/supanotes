library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';

/// Current authenticated user id, or null if signed out / loading.
final currentUserIdProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(authControllerProvider).value?.id;
});

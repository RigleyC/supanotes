library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/di/providers.dart';

class PushService extends Notifier<bool> {
  late final ApiClient _api;

  @override
  bool build() {
    _api = ref.read(apiClientProvider);
    return false;
  }

  Future<void> enable() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _api.post('/device-tokens', data: {'token': token});
        state = true;
      }
    } catch (e) {
      debugPrint('push enable failed: $e');
    }
  }

  Future<void> disable() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _api.delete('/device-tokens', data: {'token': token});
      }
      state = false;
    } catch (e) {
      debugPrint('push disable failed: $e');
    }
  }

  Future<void> toggle(bool newValue) async {
    if (newValue) {
      await enable();
    } else {
      await disable();
    }
  }
}

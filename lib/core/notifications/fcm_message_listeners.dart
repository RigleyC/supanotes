import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class FcmMessageListeners {
  FcmMessageListeners({required this.context});

  final BuildContext context;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  void start() {
    _onMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
      onError: (e) => debugPrint('FCM onMessage error: $e'),
    );

    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp
        .listen(
          _handleOpenedMessage,
          onError: (e) => debugPrint('FCM onMessageOpenedApp error: $e'),
        );
  }

  void dispose() {
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title;
    if (title == null || title.isEmpty) return;

    AppMessenger.showInfo(context, title);
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['brief_type'] != null) {
      GoRouter.of(context).go(AppRoutes.routinesLogs);
    }
  }
}

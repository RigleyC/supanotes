import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';


/// Warns at startup when running on an Android physical device that
/// probably can't reach the backend.
///
/// For Android physical devices, the host backend is reachable only if the
/// developer ran `adb reverse tcp:<port> tcp:<port>` (or the baseUrl was
/// overridden via --dart-define=API_BASE_URL=...). This helper doesn't try to
/// detect the reverse port itself (that would require spawning `adb` and
/// parsing output on device, which Flutter apps can't do); it just reminds
/// the developer on the first run of a debug session.
void warnIfAndroidBackendUnreachable({int port = 8080}) {
  if (kIsWeb || kDebugMode == false || !Platform.isAndroid) {
    return;
  }
  developer.log(
    'Running on Android. If the backend is not reachable at '
    'http://localhost:$port, run:\n'
    '  adb reverse tcp:$port tcp:$port\n'
    'or pass --dart-define=API_BASE_URL=http://<host-ip>:$port/api/v1',
    name: 'ApiClient',
  );
}

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appLinkProvider = StreamProvider.autoDispose<Uri>((ref) {
  final controller = StreamController<Uri>();
  final links = AppLinks();
  final subscription = links.uriLinkStream.listen(controller.add);
  links.getInitialLink().then((uri) {
    if (uri != null) controller.add(uri);
  });
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

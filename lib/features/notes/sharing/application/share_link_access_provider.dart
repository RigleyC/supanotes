import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_access_repository.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';

final shareLinkAccessResolverProvider =
    Provider.autoDispose<ShareLinkAccessResolver>(
      (ref) =>
          ShareLinkAccessResolver(ref.watch(shareLinkAccessRepositoryProvider)),
    );

final shareLinkAccessProvider = FutureProvider.autoDispose
    .family<ShareLinkAccessDecision, String>((ref, token) async {
      final User? user = await ref.watch(authControllerProvider.future);
      return ref
          .watch(shareLinkAccessResolverProvider)
          .resolve(token, user: user);
    });

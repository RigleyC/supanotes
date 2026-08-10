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
      User? user;
      try {
        user = await ref.watch(authControllerProvider.future);
      } catch (_) {
        // An unavailable session must not prevent a valid public link from
        // opening the guest reader.
        user = null;
      }
      return ref
          .watch(shareLinkAccessResolverProvider)
          .resolve(token, user: user);
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_access_repository.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';

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

/// Hydrates an authenticated share target into the normal local catalog.
///
/// The route only opens after this completes. That keeps the editor's
/// existing session provider and REST/OT revision path authoritative.
final shareLinkNoteHydrationProvider = FutureProvider.autoDispose
    .family<void, String>((ref, noteId) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        throw StateError('Share-link hydration requires authentication');
      }
      final repository = ref.watch(shareLinkAccessRepositoryProvider);
      final metadata = await repository.getNoteMetadata(noteId);
      await ref
          .watch(noteCatalogSyncServiceProvider)
          .hydrateRemoteNoteFromJson(userId: userId, metadata: metadata);
    });

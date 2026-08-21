import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/application/shared_link_delivery.dart';
import 'package:supanotes/features/notes/share/domain/share_note_index.dart';

/// Result of attempting to deliver a pending native share.
sealed class PendingShareResult {
  const PendingShareResult();
}

/// Nothing pending (or no authenticated user) — nothing was done.
final class PendingShareNone extends PendingShareResult {
  const PendingShareNone();
}

/// Pending text had no usable URL; the pending share was discarded.
final class PendingShareInvalidUrl extends PendingShareResult {
  const PendingShareInvalidUrl();
}

/// The user dismissed the note picker (or none was available).
final class PendingShareDismissed extends PendingShareResult {
  const PendingShareDismissed();
}

/// The link was appended to [note].
final class PendingShareDelivered extends PendingShareResult {
  const PendingShareDelivered(this.note);

  final NoteModel note;
}

/// Serializes all share-bridge interactions and owns every side effect of
/// moving data between the native share extension and the app.
///
/// Triggered from the app shell (app resume, auth changes, notes updates).
/// Delivery failures propagate to the caller so they can be surfaced.
class ShareIntakeCoordinator {
  ShareIntakeCoordinator(this._ref);

  final Ref _ref;
  Future<void> _tail = Future<void>.value();

  /// User id whose credentials are currently published to the native side.
  String? _publishedForUserId;

  /// Best-effort refresh of the note index exposed to the share extension.
  /// A stale index only affects what the extension suggests; failures are
  /// logged and retried on the next notes emission.
  Future<void> publishNotesIndex(List<NoteModel> notes) async {
    final user = _ref.read(authControllerProvider).asData?.value;
    if (user == null) return;
    try {
      await _ref
          .read(nativeShareBridgeProvider)
          .publishNotesIndex(ShareNoteIndex.fromNotes(user.id, notes));
    } catch (error) {
      debugPrint('Error publishing native share index: $error');
    }
  }

  /// Keeps the native credential store in sync with the auth session:
  /// publishes tokens on sign-in and clears them on sign-out/expiry.
  Future<void> onAuthStateChanged(User? user) =>
      _serialize(() => _onAuthStateChanged(user));

  Future<void> _onAuthStateChanged(User? user) async {
    final bridge = _ref.read(nativeShareBridgeProvider);
    if (user == null) {
      if (_publishedForUserId == null) return;
      _publishedForUserId = null;
      try {
        await bridge.clearShareSession();
      } catch (error) {
        debugPrint('Error clearing native share session: $error');
      }
      return;
    }
    if (_publishedForUserId == user.id) return;
    final tokens = _ref.read(authTokenManagerProvider);
    final access = await tokens.getAccessToken();
    final refresh = await tokens.getRefreshToken();
    if (access == null || refresh == null) return;
    _publishedForUserId = user.id;
    try {
      await bridge.publishSessionCredentials(
        ownerUserId: user.id,
        accessToken: access,
        refreshToken: refresh,
        apiBaseUrl: ApiConstants.baseUrl,
      );
      // Fresh credentials make previously-queued durable deliveries viable.
      unawaited(bridge.retryPendingShares());
    } catch (error) {
      debugPrint('Error publishing native share session: $error');
    }
  }

  /// Reads and delivers at most one pending shared link. Concurrent calls
  /// are serialized; each call sees the state left by the previous one.
  Future<PendingShareResult> processPendingShare({
    required Future<NoteModel?> Function(List<NoteModel> editableNotes)
    pickNote,
  }) => _serialize(() => _processPendingShare(pickNote));

  Future<PendingShareResult> _processPendingShare(
    Future<NoteModel?> Function(List<NoteModel> editableNotes) pickNote,
  ) async {
    final user = _ref.read(authControllerProvider).asData?.value;
    if (user == null) return const PendingShareNone();

    final bridge = _ref.read(nativeShareBridgeProvider);
    // Native durable deliveries (WorkManager) resume independently of the
    // in-app flow below; both paths are idempotent by shareId.
    unawaited(bridge.retryPendingShares());
    final pending = await bridge.readPendingShare();
    if (pending == null ||
        pending.text.trim().isEmpty ||
        pending.shareId.isEmpty) {
      return const PendingShareNone();
    }

    if (!pending.isValidForUser(user.id)) {
      // Pending share belongs to another account session; ignore for this user.
      return const PendingShareNone();
    }

    final url = SharedLinkDelivery.extractUrlFromText(pending.text);
    if (url == null) {
      await bridge.clearPendingShare();
      return const PendingShareInvalidUrl();
    }

    final notes = await _ref.read(activeNotesProvider.future);
    final targetNoteId = pending.noteId;
    NoteModel? note;
    if (targetNoteId != null && targetNoteId.isNotEmpty) {
      for (final candidate in notes) {
        if (candidate.id == targetNoteId) {
          note = candidate;
          break;
        }
      }
    }
    note ??= await pickNote(notes.where((n) => !n.isReadOnly).toList());
    if (note == null) return const PendingShareDismissed();

    // On failure the pending share stays queued so the next trigger retries
    // delivery; the error propagates to the caller for surfacing.
    await _ref
        .read(sharedLinkDeliveryProvider)
        .appendToNote(noteId: note.id, url: url, shareId: pending.shareId);
    await bridge.clearPendingShare();
    return PendingShareDelivered(note);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }
}

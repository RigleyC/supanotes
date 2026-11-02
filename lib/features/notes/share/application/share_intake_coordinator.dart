import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/core/constants/api_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/application/native_share_bridge.dart';
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

  /// User id and access token currently published to the native side.
  String? _publishedForUserId;
  String? _publishedAccessToken;

  /// Mirrors the current notes catalog to the native share extension.
  ///
  /// The extension only runs while the app is in the background, so the
  /// index is published when the app leaves the foreground and after sign-in,
  /// instead of on every catalog change (every autosave while typing), which
  /// serialized the whole index over a platform channel and wrote it to disk
  /// on the platform thread. A stale index only affects what the extension
  /// suggests; failures are logged and retried at the next publish.
  Future<void> publishCurrentNotesIndex() async {
    if (_ref.read(authControllerProvider).asData?.value == null) return;
    try {
      final notes = await _ref.read(notesRepositoryProvider).watchNotes().first;
      await publishNotesIndex(notes);
    } catch (error) {
      debugPrint('Error reading notes for the native share index: $error');
    }
  }

  /// Publishes [notes] as the index exposed to the share extension.
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

  /// Best-effort nudge for native durable deliveries; a failure must never
  /// escape as an unhandled async error.
  Future<void> _retryPendingShares(NativeShareBridge bridge) async {
    try {
      await bridge.retryPendingShares();
    } on Object catch (error) {
      debugPrint('Error retrying pending native shares: $error');
    }
  }

  /// Keeps the native credential store in sync with the auth session:
  /// publishes tokens on sign-in / refresh and clears them on sign-out/expiry.
  Future<void> onAuthStateChanged(User? user) =>
      _serialize(() => _onAuthStateChanged(user));

  Future<void> _onAuthStateChanged(User? user) async {
    final bridge = _ref.read(nativeShareBridgeProvider);
    if (user == null) {
      if (_publishedForUserId == null && _publishedAccessToken == null) return;
      _publishedForUserId = null;
      _publishedAccessToken = null;
      try {
        await bridge.clearShareSession();
      } catch (error) {
        debugPrint('Error clearing native share session: $error');
      }
      return;
    }
    final tokens = _ref.read(authTokenManagerProvider);
    final access = await tokens.getAccessToken();
    final refresh = await tokens.getRefreshToken();
    if (access == null || refresh == null) return;
    if (_publishedForUserId != user.id || _publishedAccessToken != access) {
      _publishedForUserId = user.id;
      _publishedAccessToken = access;
      try {
        await bridge.publishSessionCredentials(
          ownerUserId: user.id,
          accessToken: access,
          refreshToken: refresh,
          apiBaseUrl: ApiConstants.baseUrl,
        );
        // Fresh credentials make previously-queued durable deliveries viable.
        unawaited(_retryPendingShares(bridge));
      } catch (error) {
        debugPrint('Error publishing native share session: $error');
      }
    }
    await publishCurrentNotesIndex();
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
    unawaited(_retryPendingShares(bridge));
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
        if (candidate.id == targetNoteId && !candidate.isReadOnly) {
          note = candidate;
          break;
        }
      }
    }
    note ??= await pickNote(notes.where((n) => !n.isReadOnly).toList());
    if (note == null) return const PendingShareDismissed();

    final shareId = pending.shareId.isNotEmpty
        ? pending.shareId
        : const Uuid().v4();

    try {
      await _ref
          .read(sharedLinkDeliveryProvider)
          .appendToNote(noteId: note.id, url: url, shareId: shareId);
    } catch (_) {
      // If delivery failed (e.g. shareId was already reserved for a different note), retry with a fresh UUID
      final freshShareId = const Uuid().v4();
      await _ref
          .read(sharedLinkDeliveryProvider)
          .appendToNote(noteId: note.id, url: url, shareId: freshShareId);
    }

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

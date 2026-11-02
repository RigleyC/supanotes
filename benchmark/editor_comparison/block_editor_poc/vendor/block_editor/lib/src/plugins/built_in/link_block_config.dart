library;

import 'package:flutter/widgets.dart';

/// Configuration for LinkBlock.
///
/// Supply an instance via BlockEditorScope to customise link block
/// behaviour. All fields are optional — when null the block uses its own
/// internal defaults.
@immutable
final class LinkBlockConfig {
  /// Creates a [LinkBlockConfig].
  const LinkBlockConfig({
    this.onOpen,
    this.onError,
    this.previewEnabled = true,
  });

  /// Called when the user activates the link.
  ///
  /// Receives the URL stored in block attributes. When null the block
  /// handles opening via its default mechanism.
  final Future<void> Function(String url)? onOpen;

  /// Builder for the widget shown when the link action fails.
  final Widget Function(BuildContext context, Object error)? onError;

  /// Whether a link preview card is shown beneath the URL.
  final bool previewEnabled;

  /// Returns a copy of this config with the given fields replaced.
  LinkBlockConfig copyWith({
    Future<void> Function(String url)? onOpen,
    Widget Function(BuildContext context, Object error)? onError,
    bool? previewEnabled,
  }) {
    return LinkBlockConfig(
      onOpen: onOpen ?? this.onOpen,
      onError: onError ?? this.onError,
      previewEnabled: previewEnabled ?? this.previewEnabled,
    );
  }
}

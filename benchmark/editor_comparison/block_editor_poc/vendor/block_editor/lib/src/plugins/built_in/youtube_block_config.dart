library;

import 'package:flutter/widgets.dart';

/// Configuration for YouTubeBlock.
///
/// Supply an instance via BlockEditorScope to customise YouTube embed
/// behaviour. All fields are optional — when null the block uses its own
/// internal defaults.
@immutable
final class YouTubeBlockConfig {
  /// Creates a [YouTubeBlockConfig].
  const YouTubeBlockConfig({
    this.onError,
    this.onLoading,
    this.autoPlay = false,
    this.showControls = true,
    this.privacyEnhanced = true,
  });

  /// Builder for the widget shown when the embed fails to load.
  final Widget Function(BuildContext context, Object error)? onError;

  /// Builder for the widget shown while the embed is loading.
  final Widget Function(BuildContext context)? onLoading;

  /// Whether the video starts playing automatically when rendered.
  final bool autoPlay;

  /// Whether playback controls are shown over the video.
  final bool showControls;

  /// When true uses the youtube-nocookie.com domain for privacy-enhanced mode.
  final bool privacyEnhanced;

  /// Returns a copy of this config with the given fields replaced.
  YouTubeBlockConfig copyWith({
    Widget Function(BuildContext context, Object error)? onError,
    Widget Function(BuildContext context)? onLoading,
    bool? autoPlay,
    bool? showControls,
    bool? privacyEnhanced,
  }) {
    return YouTubeBlockConfig(
      onError: onError ?? this.onError,
      onLoading: onLoading ?? this.onLoading,
      autoPlay: autoPlay ?? this.autoPlay,
      showControls: showControls ?? this.showControls,
      privacyEnhanced: privacyEnhanced ?? this.privacyEnhanced,
    );
  }
}

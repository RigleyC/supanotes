library;

import 'package:flutter/widgets.dart';

/// Configuration for VideoBlock.
///
/// Supply an instance via BlockEditorScope to customise video rendering
/// behaviour. All fields are optional — when null the block uses its own
/// internal defaults.
@immutable
final class VideoBlockConfig {
  /// Creates a [VideoBlockConfig].
  const VideoBlockConfig({
    this.onError,
    this.onLoading,
    this.autoPlay = false,
    this.showControls = true,
  });

  /// Builder for the widget shown when the video fails to load.
  final Widget Function(BuildContext context, Object error)? onError;

  /// Builder for the widget shown while the video is loading.
  final Widget Function(BuildContext context)? onLoading;

  /// Whether the video starts playing automatically when rendered.
  final bool autoPlay;

  /// Whether playback controls are shown over the video.
  final bool showControls;

  /// Returns a copy of this config with the given fields replaced.
  VideoBlockConfig copyWith({
    Widget Function(BuildContext context, Object error)? onError,
    Widget Function(BuildContext context)? onLoading,
    bool? autoPlay,
    bool? showControls,
  }) {
    return VideoBlockConfig(
      onError: onError ?? this.onError,
      onLoading: onLoading ?? this.onLoading,
      autoPlay: autoPlay ?? this.autoPlay,
      showControls: showControls ?? this.showControls,
    );
  }
}

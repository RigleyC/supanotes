library;

import 'package:flutter/widgets.dart';

/// Configuration for ImageBlock.
///
/// Supply an instance via BlockEditorScope to customise image rendering
/// behaviour. All fields are optional — when null the block uses its own
/// internal defaults.
@immutable
final class ImageBlockConfig {
  /// Creates an [ImageBlockConfig].
  const ImageBlockConfig({
    this.onUploadRequested,
    this.onError,
    this.onLoading,
    this.scale = 1.0,
    this.borderRadius = BorderRadius.zero,
    this.fit = BoxFit.contain,
  });

  /// Called when the block requests an upload for a local file path.
  ///
  /// The host app performs the upload and returns the resulting network URL.
  /// The block emits a CustomBlockEvent with `eventType: 'image_upload_requested'`
  /// to trigger this flow.
  final Future<String> Function(String localPath)? onUploadRequested;

  /// Builder for the widget shown when the image fails to load.
  final Widget Function(BuildContext context, Object error)? onError;

  /// Builder for the widget shown while the image is loading.
  final Widget Function(BuildContext context)? onLoading;

  /// The scale factor applied to the rendered image.
  final double scale;

  /// The border radius applied to the image container.
  final BorderRadius borderRadius;

  /// How the image should be inscribed into its allocated space.
  final BoxFit fit;

  /// Returns a copy of this config with the given fields replaced.
  ImageBlockConfig copyWith({
    Future<String> Function(String localPath)? onUploadRequested,
    Widget Function(BuildContext context, Object error)? onError,
    Widget Function(BuildContext context)? onLoading,
    double? scale,
    BorderRadius? borderRadius,
    BoxFit? fit,
  }) {
    return ImageBlockConfig(
      onUploadRequested: onUploadRequested ?? this.onUploadRequested,
      onError: onError ?? this.onError,
      onLoading: onLoading ?? this.onLoading,
      scale: scale ?? this.scale,
      borderRadius: borderRadius ?? this.borderRadius,
      fit: fit ?? this.fit,
    );
  }
}

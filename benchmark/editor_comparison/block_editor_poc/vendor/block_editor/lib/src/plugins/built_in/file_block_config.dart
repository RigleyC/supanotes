library;

import 'package:flutter/widgets.dart';

/// Configuration for FileBlock.
///
/// Supply an instance via BlockEditorScope to customise file attachment
/// behaviour. All fields are optional — when null the block uses its own
/// internal defaults.
@immutable
final class FileBlockConfig {
  /// Creates a [FileBlockConfig].
  const FileBlockConfig({
    this.onDownload,
    this.onOpen,
    this.onError,
    this.allowedExtensions = const [],
  });

  /// Called when the user taps the download action for a file.
  ///
  /// Receives the file URL or local path stored in block attributes.
  final Future<void> Function(String path)? onDownload;

  /// Called when the user taps the open action for a file.
  ///
  /// Receives the file URL or local path stored in block attributes.
  final Future<void> Function(String path)? onOpen;

  /// Builder for the widget shown when the file action fails.
  final Widget Function(BuildContext context, Object error)? onError;

  /// The list of permitted file extensions shown in the file picker.
  ///
  /// An empty list means all extensions are permitted.
  final List<String> allowedExtensions;

  /// Returns a copy of this config with the given fields replaced.
  FileBlockConfig copyWith({
    Future<void> Function(String path)? onDownload,
    Future<void> Function(String path)? onOpen,
    Widget Function(BuildContext context, Object error)? onError,
    List<String>? allowedExtensions,
  }) {
    return FileBlockConfig(
      onDownload: onDownload ?? this.onDownload,
      onOpen: onOpen ?? this.onOpen,
      onError: onError ?? this.onError,
      allowedExtensions: allowedExtensions ?? this.allowedExtensions,
    );
  }
}

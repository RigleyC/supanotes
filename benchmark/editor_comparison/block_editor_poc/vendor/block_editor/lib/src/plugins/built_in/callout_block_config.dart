library;

import 'package:flutter/widgets.dart';

/// Configuration for CalloutBlock.
///
/// Supply an instance via BlockEditorScope to customise callout block
/// colours, icons, and shape. All fields are optional — when null the block
/// uses its own internal defaults.
@immutable
final class CalloutBlockConfig {
  /// Creates a [CalloutBlockConfig].
  const CalloutBlockConfig({
    this.infoColor,
    this.warningColor,
    this.errorColor,
    this.infoIcon,
    this.warningIcon,
    this.errorIcon,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  /// The background colour used for info-variant callouts.
  final Color? infoColor;

  /// The background colour used for warning-variant callouts.
  final Color? warningColor;

  /// The background colour used for error-variant callouts.
  final Color? errorColor;

  /// The leading icon widget used for info-variant callouts.
  final Widget? infoIcon;

  /// The leading icon widget used for warning-variant callouts.
  final Widget? warningIcon;

  /// The leading icon widget used for error-variant callouts.
  final Widget? errorIcon;

  /// The border radius applied to the callout container.
  final BorderRadius borderRadius;

  /// Returns a copy of this config with the given fields replaced.
  CalloutBlockConfig copyWith({
    Object? infoColor = _sentinel,
    Object? warningColor = _sentinel,
    Object? errorColor = _sentinel,
    Object? infoIcon = _sentinel,
    Object? warningIcon = _sentinel,
    Object? errorIcon = _sentinel,
    BorderRadius? borderRadius,
  }) {
    return CalloutBlockConfig(
      infoColor: infoColor == _sentinel ? this.infoColor : infoColor as Color?,
      warningColor: warningColor == _sentinel
          ? this.warningColor
          : warningColor as Color?,
      errorColor: errorColor == _sentinel
          ? this.errorColor
          : errorColor as Color?,
      infoIcon: infoIcon == _sentinel ? this.infoIcon : infoIcon as Widget?,
      warningIcon: warningIcon == _sentinel
          ? this.warningIcon
          : warningIcon as Widget?,
      errorIcon: errorIcon == _sentinel ? this.errorIcon : errorIcon as Widget?,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}

const Object _sentinel = Object();

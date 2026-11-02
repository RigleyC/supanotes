library;

import 'package:meta/meta.dart';

/// Configuration for CodeBlock.
///
/// Supply an instance via BlockEditorScope to customise code block
/// rendering behaviour. All fields are optional — when null the block uses
/// its own internal defaults.
@immutable
final class CodeBlockConfig {
  /// Creates a [CodeBlockConfig].
  const CodeBlockConfig({
    this.theme,
    this.fontSize = 14.0,
    this.showLineNumbers = true,
    this.showLanguageSelector = true,
    this.tabSize = 2,
  });

  /// The syntax highlighting theme name.
  ///
  /// When null the block uses its default theme.
  final String? theme;

  /// The font size used for code text.
  final double fontSize;

  /// Whether line numbers are shown to the left of the code.
  final bool showLineNumbers;

  /// Whether the language selector dropdown is shown above the code.
  final bool showLanguageSelector;

  /// The number of spaces inserted per tab key press.
  final int tabSize;

  /// Returns a copy of this config with the given fields replaced.
  CodeBlockConfig copyWith({
    Object? theme = _sentinel,
    double? fontSize,
    bool? showLineNumbers,
    bool? showLanguageSelector,
    int? tabSize,
  }) {
    return CodeBlockConfig(
      theme: theme == _sentinel ? this.theme : theme as String?,
      fontSize: fontSize ?? this.fontSize,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      showLanguageSelector: showLanguageSelector ?? this.showLanguageSelector,
      tabSize: tabSize ?? this.tabSize,
    );
  }
}

const Object _sentinel = Object();

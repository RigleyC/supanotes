/// Canonical string constants for all built-in block types.
///
/// All built-in block type identifiers are defined here as static constants.
/// Custom block types registered via the plugin system should follow the same
/// naming convention — lowercase with no spaces.
abstract final class BlockTypes {
  static const String paragraph = 'paragraph';

  static const String heading1 = 'heading1';
  static const String heading2 = 'heading2';
  static const String heading3 = 'heading3';

  static const String bulletList = 'bulletList';
  static const String numberedList = 'numberedList';
  static const String todo = 'todo';

  static const String quote = 'quote';
  static const String callout = 'callout';
  static const String code = 'code';
  static const String divider = 'divider';

  static const String image = 'image';
  static const String video = 'video';
  static const String youtube = 'youtube';
  static const String file = 'file';

  static const String link = 'link';
}

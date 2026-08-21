/// User-facing messages for the share intake feature. Long or interpolated
/// strings live here per project convention; simple labels stay inline.
library;

abstract final class ShareStrings {
  static String linkSavedIn(String noteTitle) => 'Link salvo em $noteTitle';
  static const sharedTextHasNoUrl = 'O texto compartilhado não contém uma URL.';
  static const deliveryFailed =
      'Não foi possível salvar o link compartilhado. Tente novamente.';
}

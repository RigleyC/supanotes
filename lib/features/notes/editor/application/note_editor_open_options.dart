import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';

class NoteEditorOpenOptions {
  const NoteEditorOpenOptions({
    this.requestInitialFocus = false,
    this.attachmentDelivery,
  });

  const NoteEditorOpenOptions.newNote()
    : requestInitialFocus = true,
      attachmentDelivery = null;

  final bool requestInitialFocus;
  final AttachmentDelivery? attachmentDelivery;
}

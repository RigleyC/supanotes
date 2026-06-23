import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class NoteLinkTapHandler extends ContentTapDelegate {
  NoteLinkTapHandler(
    this.document,
    this.composer, {
    required this.onNoteTap,
  }) {
    composer.isInInteractionMode.addListener(notifyListeners);
  }

  final Document document;
  final MutableDocumentComposer composer;
  final void Function(String noteId) onNoteTap;

  @override
  void dispose() {
    composer.isInInteractionMode.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    if (!composer.isInInteractionMode.value) {
      return null;
    }
    final noteId = _getNoteIdAtPosition(hoverPosition);
    return noteId != null ? SystemMouseCursors.click : null;
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    if (!composer.isInInteractionMode.value) {
      return TapHandlingInstruction.continueHandling;
    }

    final tapPosition = details.documentLayout.getDocumentPositionNearestToOffset(details.layoutOffset);
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }

    final noteId = _getNoteIdAtPosition(tapPosition);
    if (noteId != null) {
      onNoteTap(noteId);
      return TapHandlingInstruction.halt;
    }

    return TapHandlingInstruction.continueHandling;
  }

  String? _getNoteIdAtPosition(DocumentPosition position) {
    final nodePosition = position.nodePosition;
    if (nodePosition is! TextNodePosition) {
      return null;
    }

    final textNode = document.getNodeById(position.nodeId);
    if (textNode is! TextNode) {
      return null;
    }

    final tappedAttributions = textNode.text.getAllAttributionsAt(nodePosition.offset);
    for (final tappedAttribution in tappedAttributions) {
      if (tappedAttribution is LinkAttribution) {
        final uri = tappedAttribution.launchableUri;
        if (uri.scheme == 'note') {
          return uri.toString().replaceFirst('note://', '');
        }
      }
    }

    return null;
  }
}

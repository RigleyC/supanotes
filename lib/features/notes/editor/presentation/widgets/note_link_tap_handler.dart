import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

class NoteLinkTapHandler extends ContentTapDelegate {
  NoteLinkTapHandler(
    this.document,
    this.composer, {
    required this.onNoteTap,
    this.allowExternalLinks = false,
  }) {
    composer.isInInteractionMode.addListener(notifyListeners);
  }

  final Document document;
  final DocumentComposer composer;
  final void Function(String noteId) onNoteTap;
  final bool allowExternalLinks;

  @override
  void dispose() {
    composer.isInInteractionMode.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    final uri = _getLinkAtPosition(hoverPosition);
    if (uri == null) return null;
    if (uri.scheme == 'note' || allowExternalLinks) {
      return SystemMouseCursors.click;
    }
    return null;
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final tapPosition = details.documentLayout
        .getDocumentPositionNearestToOffset(details.layoutOffset);
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }

    final uri = _getLinkAtPosition(tapPosition);
    if (uri == null) return TapHandlingInstruction.continueHandling;

    if (uri.scheme == 'note') {
      onNoteTap(uri.toString().replaceFirst('note://', ''));
      return TapHandlingInstruction.halt;
    }

    if (allowExternalLinks) {
      unawaited(launchUrl(uri));
      return TapHandlingInstruction.halt;
    }

    return TapHandlingInstruction.continueHandling;
  }

  Uri? _getLinkAtPosition(DocumentPosition position) {
    final nodePosition = position.nodePosition;
    if (nodePosition is! TextNodePosition) {
      return null;
    }

    final textNode = document.getNodeById(position.nodeId);
    if (textNode is! TextNode) {
      return null;
    }

    final tappedAttributions = textNode.text.getAllAttributionsAt(
      nodePosition.offset,
    );
    for (final tappedAttribution in tappedAttributions) {
      if (tappedAttribution is LinkAttribution) {
        final uri = tappedAttribution.launchableUri;
        return uri;
      }
    }

    return null;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:url_launcher/url_launcher.dart';

class NoteLinkTapHandler extends ContentTapDelegate {
  NoteLinkTapHandler(
    this.document, {
    required this.onNoteTap,
    this.webOnly = false,
    this.allowInternalNoteLinks = true,
  });

  final Document document;
  final void Function(String noteId) onNoteTap;
  final bool webOnly;
  final bool allowInternalNoteLinks;

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    final uri = _getLinkAtPosition(hoverPosition);
    if (uri == null || !_isAllowed(uri)) return null;
    return SystemMouseCursors.click;
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
      if (!allowInternalNoteLinks) {
        return TapHandlingInstruction.continueHandling;
      }
      onNoteTap(uri.toString().replaceFirst('note://', ''));
      return TapHandlingInstruction.halt;
    }

    if (webOnly && !_isWebUri(uri)) {
      return TapHandlingInstruction.continueHandling;
    }
    unawaited(launchUrl(uri));
    return TapHandlingInstruction.halt;
  }

  bool _isWebUri(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  bool _isAllowed(Uri uri) {
    if (uri.scheme == 'note') return allowInternalNoteLinks;
    return !webOnly || _isWebUri(uri);
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

    if (nodePosition.offset < 0 ||
        nodePosition.offset >= textNode.text.length) {
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

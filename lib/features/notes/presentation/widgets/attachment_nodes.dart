import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

// ignore: must_be_immutable
class ImageAttachmentNode extends BlockNode with ChangeNotifier {
  ImageAttachmentNode({
    required this.id,
    required this.url,
    required this.fileName,
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? {};

  @override
  final String id;
  final String url;
  final String fileName;
  final Map<String, dynamic> _metadata;

  @override
  String? getMetadataValue(String key) => _metadata[key] as String?;

  void putMetadataValue(String key, Object? value) {
    _metadata[key] = value;
    notifyListeners();
  }

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed ? url : null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return ImageAttachmentNode(
      id: id, url: url, fileName: fileName,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return ImageAttachmentNode(
      id: id, url: url, fileName: fileName, metadata: newMetadata,
    );
  }

  ImageAttachmentNode copy() => ImageAttachmentNode(
      id: id, url: url, fileName: fileName, metadata: Map.from(_metadata));

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is ImageAttachmentNode && other.url == url;
}

// ignore: must_be_immutable
class FileAttachmentNode extends BlockNode with ChangeNotifier {
  FileAttachmentNode({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? {};

  @override
  final String id;
  final String url;
  final String fileName;
  final String mimeType;
  final Map<String, dynamic> _metadata;

  bool get isVideo => mimeType.startsWith('video/');

  @override
  String? getMetadataValue(String key) => _metadata[key] as String?;

  void putMetadataValue(String key, Object? value) {
    _metadata[key] = value;
    notifyListeners();
  }

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed ? url : null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return FileAttachmentNode(
      id: id, url: url, fileName: fileName, mimeType: mimeType,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return FileAttachmentNode(
      id: id, url: url, fileName: fileName, mimeType: mimeType,
      metadata: newMetadata,
    );
  }

  FileAttachmentNode copy() => FileAttachmentNode(
      id: id, url: url, fileName: fileName, mimeType: mimeType,
      metadata: Map.from(_metadata));

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is FileAttachmentNode && other.url == url;
}

// ignore: must_be_immutable
class RichLinkNode extends BlockNode with ChangeNotifier {
  RichLinkNode({
    required this.id,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.domain,
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? {};

  @override
  final String id;
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? domain;
  final Map<String, dynamic> _metadata;

  @override
  String? getMetadataValue(String key) => _metadata[key] as String?;

  void putMetadataValue(String key, Object? value) {
    _metadata[key] = value;
    notifyListeners();
  }

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed ? url : null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return RichLinkNode(
      id: id, url: url, title: title, description: description,
      imageUrl: imageUrl, domain: domain,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return RichLinkNode(
      id: id, url: url, title: title, description: description,
      imageUrl: imageUrl, domain: domain, metadata: newMetadata,
    );
  }

  RichLinkNode copy() => RichLinkNode(
      id: id, url: url, title: title, description: description,
      imageUrl: imageUrl, domain: domain, metadata: Map.from(_metadata));

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is RichLinkNode && other.url == url;
}

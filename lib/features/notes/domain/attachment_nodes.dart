import 'package:super_editor/super_editor.dart';

abstract class AttachmentNode extends BlockNode {
  AttachmentNode({Map<String, dynamic>? metadata})
      : super(metadata: metadata);

  String get url;

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed ? url : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other.runtimeType == runtimeType &&
      other is AttachmentNode &&
      other.url == url;
}

class ImageAttachmentNode extends AttachmentNode {
  ImageAttachmentNode({
    required this.id,
    required this.url,
    required this.fileName,
    super.metadata,
  });

  @override
  final String id;
  @override
  final String url;
  final String fileName;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      ImageAttachmentNode(
        id: id, url: url, fileName: fileName,
        metadata: {...metadata, ...newProperties},
      );

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      ImageAttachmentNode(
        id: id, url: url, fileName: fileName, metadata: newMetadata,
      );

  ImageAttachmentNode copy() => ImageAttachmentNode(
        id: id, url: url, fileName: fileName,
        metadata: Map.from(metadata),
      );
}

class FileAttachmentNode extends AttachmentNode {
  FileAttachmentNode({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    super.metadata,
  });

  @override
  final String id;
  @override
  final String url;
  final String fileName;
  final String mimeType;

  bool get isVideo => mimeType.startsWith('video/');

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      FileAttachmentNode(
        id: id, url: url, fileName: fileName, mimeType: mimeType,
        metadata: {...metadata, ...newProperties},
      );

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      FileAttachmentNode(
        id: id, url: url, fileName: fileName, mimeType: mimeType,
        metadata: newMetadata,
      );

  FileAttachmentNode copy() => FileAttachmentNode(
        id: id, url: url, fileName: fileName, mimeType: mimeType,
        metadata: Map.from(metadata),
      );
}

class RichLinkNode extends AttachmentNode {
  RichLinkNode({
    required this.id,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.domain,
    super.metadata,
  });

  @override
  final String id;
  @override
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? domain;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      RichLinkNode(
        id: id, url: url, title: title, description: description,
        imageUrl: imageUrl, domain: domain,
        metadata: {...metadata, ...newProperties},
      );

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      RichLinkNode(
        id: id, url: url, title: title, description: description,
        imageUrl: imageUrl, domain: domain, metadata: newMetadata,
      );

  RichLinkNode copy() => RichLinkNode(
        id: id, url: url, title: title, description: description,
        imageUrl: imageUrl, domain: domain,
        metadata: Map.from(metadata),
      );
}

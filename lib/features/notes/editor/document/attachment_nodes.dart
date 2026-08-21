import 'package:super_editor/super_editor.dart';

abstract class AttachmentNode extends BlockNode {
  AttachmentNode({super.metadata});

  @override
  String get id;

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed ? id : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other.runtimeType == runtimeType &&
      other is AttachmentNode &&
      other.id == id;
}

class DocumentAttachmentNode extends AttachmentNode {
  DocumentAttachmentNode({required this.id, super.metadata});

  @override
  final String id;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      DocumentAttachmentNode(id: id, metadata: {...metadata, ...newProperties});

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      DocumentAttachmentNode(id: id, metadata: newMetadata);

  DocumentAttachmentNode copy() =>
      DocumentAttachmentNode(id: id, metadata: Map.from(metadata));
}

class RichLinkNode extends AttachmentNode {
  RichLinkNode({
    required this.id,
    this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.domain,
    this.previewStatus,
    this.faviconUrl,
    this.siteName,
    super.metadata,
  });

  @override
  final String id;
  final String? url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? domain;
  final String? previewStatus;
  final String? faviconUrl;
  final String? siteName;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      RichLinkNode(
        id: id,
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        domain: domain,
        previewStatus: previewStatus,
        faviconUrl: faviconUrl,
        siteName: siteName,
        metadata: {...metadata, ...newProperties},
      );

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      RichLinkNode(
        id: id,
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        domain: domain,
        previewStatus: previewStatus,
        faviconUrl: faviconUrl,
        siteName: siteName,
        metadata: newMetadata,
      );

  RichLinkNode copy() => RichLinkNode(
    id: id,
    url: url,
    title: title,
    description: description,
    imageUrl: imageUrl,
    domain: domain,
    previewStatus: previewStatus,
    faviconUrl: faviconUrl,
    siteName: siteName,
    metadata: Map.from(metadata),
  );
}

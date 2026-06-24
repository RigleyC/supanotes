import 'dart:convert';

import 'package:markdown/markdown.dart' as md hide Document;
import 'package:super_editor/super_editor.dart';

import '../domain/attachment_nodes.dart';

final List<DocumentNodeMarkdownSerializer> attachmentNodeSerializers = [
  const _DocumentAttachmentSerializer(),
  const _RichLinkSerializer(),
];

final List<md.BlockSyntax> attachmentBlockSyntaxes = [
  _AttachmentBlockSyntax(),
];

final List<ElementToNodeConverter> attachmentElementConverters = [
  const _AttachmentElementConverter(),
];

class _DocumentAttachmentSerializer
    extends NodeTypedDocumentNodeMarkdownSerializer<DocumentAttachmentNode> {
  const _DocumentAttachmentSerializer();

  @override
  String doSerialization(
    Document document,
    DocumentAttachmentNode node, {
    NodeSelection? selection,
  }) {
    final data = {'id': node.id};
    return '--- <!-- attachment:doc ${jsonEncode(data)} -->';
  }
}

class _RichLinkSerializer
    extends NodeTypedDocumentNodeMarkdownSerializer<RichLinkNode> {
  const _RichLinkSerializer();

  @override
  String doSerialization(
    Document document,
    RichLinkNode node, {
    NodeSelection? selection,
  }) {
    final data = {
      if (node.url != null) 'url': node.url,
      if (node.title != null) 'title': node.title,
      if (node.description != null) 'description': node.description,
      if (node.imageUrl != null) 'image': node.imageUrl,
      if (node.domain != null) 'domain': node.domain,
    };
    return '--- <!-- attachment:link ${jsonEncode(data)} -->';
  }
}

class _AttachmentBlockSyntax extends md.BlockSyntax {
  static final _pattern =
      RegExp(r'^---\s+<!--\s*attachment:(doc|img|file|link)\s+(.+?)\s*-->$');

  @override
  RegExp get pattern => _pattern;

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = _pattern.firstMatch(parser.current.content);
    parser.advance();

    final type = match!.group(1)!;
    final jsonStr = match.group(2)!;
    return md.Element('attachment-block', [])
      ..attributes['type'] = type
      ..attributes['data'] = jsonStr;
  }
}

class _AttachmentElementConverter implements ElementToNodeConverter {
  const _AttachmentElementConverter();

  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.tag != 'attachment-block') return null;

    final type = element.attributes['type'];
    final jsonStr = element.attributes['data'];
    if (type == null || jsonStr == null) return null;

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      switch (type) {
        case 'doc':
        case 'img':
        case 'file':
          final id = data['id'] as String? ?? Editor.createNodeId();
          return DocumentAttachmentNode(id: id);
        case 'link':
          return RichLinkNode(
            id: data['id'] as String? ?? Editor.createNodeId(),
            url: data['url'] as String?,
            title: data['title'] as String?,
            description: data['description'] as String?,
            imageUrl: data['image'] as String?,
            domain: data['domain'] as String?,
          );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

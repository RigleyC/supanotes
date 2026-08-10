class ShareLinkDocument {
  const ShareLinkDocument({required this.title, required this.blocks});

  final String title;
  final List<ShareLinkBlock> blocks;

  factory ShareLinkDocument.fromJson(Map<String, dynamic> json) {
    final rawDocument = json['document'];
    if (rawDocument is! Map) {
      throw const FormatException('Share link response has no document');
    }
    final document = Map<String, dynamic>.from(rawDocument);
    final rawBlocks = document['blocks'];
    if (rawBlocks is! List) {
      throw const FormatException('Share link document has no blocks');
    }
    final rawTitle = json['title'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      throw const FormatException('Share link response has no title');
    }
    final blocks = rawBlocks
        .map((rawBlock) {
          if (rawBlock is! Map) {
            throw const FormatException(
              'Share link document contains an invalid block',
            );
          }
          return ShareLinkBlock.fromJson(Map<String, dynamic>.from(rawBlock));
        })
        .toList(growable: false);
    return ShareLinkDocument(title: rawTitle, blocks: blocks);
  }
}

class ShareLinkBlock {
  const ShareLinkBlock({
    required this.id,
    required this.type,
    required this.delta,
    required this.metadata,
  });

  final String id;
  final String type;
  final List<Map<String, dynamic>> delta;
  final Map<String, dynamic> metadata;

  String get text =>
      delta.map((operation) => operation['insert']).whereType<String>().join();

  factory ShareLinkBlock.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    final rawId = json['id'];
    final rawType = json['type'];
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Share link block has no id');
    }
    if (rawType is! String || rawType.isEmpty) {
      throw const FormatException('Share link block has no type');
    }
    if (rawDelta is! List) {
      throw const FormatException('Share link block has no delta');
    }
    final delta = rawDelta
        .map((rawOperation) {
          if (rawOperation is! Map) {
            throw const FormatException(
              'Share link block contains an invalid delta',
            );
          }
          return Map<String, dynamic>.from(rawOperation);
        })
        .toList(growable: false);
    final rawMetadata = json['metadata'];
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const FormatException('Share link block has invalid metadata');
    }
    return ShareLinkBlock(
      id: rawId,
      type: rawType,
      delta: delta,
      metadata: rawMetadata == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(rawMetadata),
    );
  }
}

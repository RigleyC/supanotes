class ShareLinkDocument {
  const ShareLinkDocument({required this.title, required this.blocks});

  final String title;
  final List<ShareLinkBlock> blocks;

  factory ShareLinkDocument.fromJson(Map<String, dynamic> json) {
    final rawDocument = json['document'];
    final document = rawDocument is Map<String, dynamic>
        ? rawDocument
        : const <String, dynamic>{};
    final rawBlocks = document['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks
              .whereType<Map<String, dynamic>>()
              .map(ShareLinkBlock.fromJson)
              .toList(growable: false)
        : const <ShareLinkBlock>[];
    return ShareLinkDocument(
      title: json['title'] as String? ?? 'Nota compartilhada no SupaNotes',
      blocks: blocks,
    );
  }
}

class ShareLinkBlock {
  const ShareLinkBlock({required this.type, required this.text});

  final String type;
  final String text;

  factory ShareLinkBlock.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    final text = rawDelta is List
        ? rawDelta
              .whereType<Map<String, dynamic>>()
              .map((op) => op['insert'])
              .whereType<String>()
              .join()
        : '';
    return ShareLinkBlock(
      type: json['type'] as String? ?? 'paragraph',
      text: text,
    );
  }
}

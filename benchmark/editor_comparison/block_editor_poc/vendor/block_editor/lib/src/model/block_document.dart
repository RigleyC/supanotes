library;

import 'package:meta/meta.dart';

import 'block_node.dart';

@immutable
final class BlockDocument {
  const BlockDocument(this.blocks);

  factory BlockDocument.empty() {
    return BlockDocument([BlockNode(type: 'paragraph')]);
  }

  factory BlockDocument.fromJson(Map<String, dynamic> json) {
    final list = json['blocks'] as List<dynamic>;
    return BlockDocument(
      list.map((e) => BlockNode.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  final List<BlockNode> blocks;

  bool get isEmpty => blocks.isEmpty;
  bool get isNotEmpty => blocks.isNotEmpty;

  BlockNode? findById(String id) => _findById(blocks, id);

  static BlockNode? _findById(List<BlockNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _findById(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  List<BlockNode> flatten() {
    final result = <BlockNode>[];
    _flatten(blocks, result);
    return result;
  }

  static void _flatten(List<BlockNode> nodes, List<BlockNode> result) {
    for (final node in nodes) {
      result.add(node);
      _flatten(node.children, result);
    }
  }

  BlockDocument copyWith({List<BlockNode>? blocks}) {
    return BlockDocument(blocks ?? List.of(this.blocks));
  }

  Map<String, dynamic> toJson() {
    return {'blocks': blocks.map((b) => b.toJson()).toList()};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BlockDocument || other.blocks.length != blocks.length) {
      return false;
    }
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i] != other.blocks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(blocks);

  @override
  String toString() => 'BlockDocument(${blocks.length} blocks)';
}

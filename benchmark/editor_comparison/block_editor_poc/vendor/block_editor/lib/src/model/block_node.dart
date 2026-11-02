library;

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'text_delta.dart';

const _uuid = Uuid();

@immutable
final class BlockNode {
  BlockNode({
    String? id,
    required this.type,
    Map<String, dynamic>? attributes,
    List<BlockNode>? children,
    this.delta,
  }) : id = id ?? _uuid.v4(),
       attributes = Map.unmodifiable(attributes ?? const {}),
       children = List.unmodifiable(children ?? const []);

  factory BlockNode.fromJson(Map<String, dynamic> json) {
    return BlockNode(
      id: json['id'] as String?,
      type: json['type'] as String,
      attributes: (json['attributes'] as Map<String, dynamic>?),
      children: (json['children'] as List<dynamic>?)
          ?.map((e) => BlockNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      delta: json['delta'] != null
          ? TextDelta.fromJson(json['delta'] as List<dynamic>)
          : null,
    );
  }

  final String id;
  final String type;
  final Map<String, dynamic> attributes;
  final List<BlockNode> children;
  final TextDelta? delta;

  BlockNode copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? attributes,
    List<BlockNode>? children,
    TextDelta? delta,
  }) {
    return BlockNode(
      id: id ?? this.id,
      type: type ?? this.type,
      attributes: attributes ?? Map.of(this.attributes),
      children: children ?? List.of(this.children),
      delta: delta ?? this.delta,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      if (attributes.isNotEmpty) 'attributes': attributes,
      if (children.isNotEmpty)
        'children': children.map((c) => c.toJson()).toList(),
      if (delta != null) 'delta': delta!.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BlockNode) return false;
    if (other.id != id || other.type != type || other.delta != delta) {
      return false;
    }
    if (other.attributes.length != attributes.length) return false;
    for (final key in attributes.keys) {
      if (other.attributes[key] != attributes[key]) return false;
    }
    if (other.children.length != children.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (children[i] != other.children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    Object.hashAll(attributes.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(children),
    delta,
  );

  @override
  String toString() => 'BlockNode(id: $id, type: $type)';
}

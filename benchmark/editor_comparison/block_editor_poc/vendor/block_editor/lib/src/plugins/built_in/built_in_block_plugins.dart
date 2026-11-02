library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.paragraph].
final class ParagraphBlock extends BlockPlugin {
  /// Creates a [ParagraphBlock].
  ParagraphBlock();

  @override
  String get blockType => BlockTypes.paragraph;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => ParagraphWidget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Text',
    group: 'Basic',
    icon: const Icon(Icons.notes),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.heading1].
final class H1Block extends BlockPlugin {
  /// Creates an [H1Block].
  H1Block();

  @override
  String get blockType => BlockTypes.heading1;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => H1Widget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Heading 1',
    group: 'Basic',
    icon: const Icon(Icons.title),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.heading2].
final class H2Block extends BlockPlugin {
  /// Creates an [H2Block].
  H2Block();

  @override
  String get blockType => BlockTypes.heading2;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => H2Widget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Heading 2',
    group: 'Basic',
    icon: const Icon(Icons.text_fields),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.heading3].
final class H3Block extends BlockPlugin {
  /// Creates an [H3Block].
  H3Block();

  @override
  String get blockType => BlockTypes.heading3;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => H3Widget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Heading 3',
    group: 'Basic',
    icon: const Icon(Icons.short_text),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.bulletList].
final class BulletListBlock extends BlockPlugin {
  /// Creates a [BulletListBlock].
  BulletListBlock();

  @override
  String get blockType => BlockTypes.bulletList;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => BulletListWidget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    attributes: node.attributes,
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Bullet List',
    group: 'Basic',
    icon: const Icon(Icons.format_list_bulleted),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.numberedList].
final class NumberedListBlock extends BlockPlugin {
  /// Creates a [NumberedListBlock].
  NumberedListBlock();

  @override
  String get blockType => BlockTypes.numberedList;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => NumberedListWidget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    attributes: node.attributes,
    number: node.attributes['number'] as int? ?? 1,
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Numbered List',
    group: 'Basic',
    icon: const Icon(Icons.format_list_numbered),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.todo].
final class TodoBlock extends BlockPlugin {
  /// Creates a [TodoBlock].
  TodoBlock();

  @override
  String get blockType => BlockTypes.todo;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => TodoWidget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    checked: node.attributes['checked'] as bool? ?? false,
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'To-do',
    group: 'Basic',
    icon: const Icon(Icons.check_box_outlined),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.quote].
final class QuoteBlock extends BlockPlugin {
  /// Creates a [QuoteBlock].
  QuoteBlock();

  @override
  String get blockType => BlockTypes.quote;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => QuoteWidget(
    blockId: node.id,
    delta: node.delta ?? TextDelta.empty(),
    selection: selection,
    onEvent: onEvent,
  );

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Quote',
    group: 'Basic',
    icon: const Icon(Icons.format_quote),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

/// [BlockPlugin] for [BlockTypes.divider].
final class DividerBlock extends BlockPlugin {
  /// Creates a [DividerBlock].
  DividerBlock();

  @override
  String get blockType => BlockTypes.divider;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => DividerWidget(blockId: node.id, onEvent: onEvent);

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Divider',
    group: 'Basic',
    icon: const Icon(Icons.horizontal_rule),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

import 'package:flutter/material.dart';

enum SlashOptionType {
  h1,
  h2,
  h3,
  task,
  bulletList,
  numberedList,
  quote,
  divider,
  image,
  file,
}

class SlashCommandOption {
  final SlashOptionType type;
  final String label;
  final IconData icon;
  final List<String> aliases;

  const SlashCommandOption({
    required this.type,
    required this.label,
    required this.icon,
    required this.aliases,
  });

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (label.toLowerCase().contains(q)) return true;
    return aliases.any((alias) => alias.toLowerCase().contains(q));
  }
}

const List<SlashCommandOption> defaultSlashCommandOptions = [
  SlashCommandOption(
    type: SlashOptionType.h1,
    label: 'Título 1',
    icon: Icons.title,
    aliases: ['h1', 'titulo1', 'heading1', 't1'],
  ),
  SlashCommandOption(
    type: SlashOptionType.h2,
    label: 'Título 2',
    icon: Icons.text_fields,
    aliases: ['h2', 'titulo2', 'heading2', 't2'],
  ),
  SlashCommandOption(
    type: SlashOptionType.h3,
    label: 'Título 3',
    icon: Icons.text_format,
    aliases: ['h3', 'titulo3', 'heading3', 't3'],
  ),
  SlashCommandOption(
    type: SlashOptionType.task,
    label: 'Tarefa',
    icon: Icons.check_box_outlined,
    aliases: ['task', 'tarefa', 'todo', 'check', 'checkbox'],
  ),
  SlashCommandOption(
    type: SlashOptionType.bulletList,
    label: 'Lista com marcadores',
    icon: Icons.format_list_bulleted,
    aliases: ['bullet', 'lista', 'ul', 'marcadores'],
  ),
  SlashCommandOption(
    type: SlashOptionType.numberedList,
    label: 'Lista numerada',
    icon: Icons.format_list_numbered,
    aliases: ['numbered', 'numerada', 'ol', 'numero'],
  ),
  SlashCommandOption(
    type: SlashOptionType.quote,
    label: 'Citação',
    icon: Icons.format_quote,
    aliases: ['quote', 'citacao', 'blockquote'],
  ),
  SlashCommandOption(
    type: SlashOptionType.divider,
    label: 'Divisor',
    icon: Icons.horizontal_rule,
    aliases: ['divider', 'divisor', 'hr', 'linha'],
  ),
  SlashCommandOption(
    type: SlashOptionType.image,
    label: 'Imagem',
    icon: Icons.image_outlined,
    aliases: ['image', 'imagem', 'foto', 'pic'],
  ),
  SlashCommandOption(
    type: SlashOptionType.file,
    label: 'Arquivo',
    icon: Icons.attach_file,
    aliases: ['file', 'arquivo', 'anexo', 'attachment'],
  ),
];

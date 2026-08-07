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
  final String group;
  final String? description;

  const SlashCommandOption({
    required this.type,
    required this.label,
    required this.icon,
    required this.aliases,
    this.group = 'Geral',
    this.description,
  });

  bool matches(String query) {
    return query.isEmpty || matchScore(query) > 0;
  }

  /// Scores exact and prefix matches above broader substring matches.
  int matchScore(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return 0;

    var bestScore = 0;
    for (final value in [label, ...aliases]) {
      final normalizedValue = value.toLowerCase();
      final score = normalizedValue == normalizedQuery
          ? 3
          : normalizedValue.startsWith(normalizedQuery)
          ? 2
          : normalizedValue.contains(normalizedQuery)
          ? 1
          : 0;
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }
}

const List<SlashCommandOption> defaultSlashCommandOptions = [
  SlashCommandOption(
    type: SlashOptionType.h1,
    label: 'Título 1',
    icon: Icons.title,
    aliases: ['h1', 'titulo1', 'heading1', 't1'],
    group: 'Estilo',
    description: 'Título grande',
  ),
  SlashCommandOption(
    type: SlashOptionType.h2,
    label: 'Título 2',
    icon: Icons.text_fields,
    aliases: ['h2', 'titulo2', 'heading2', 't2'],
    group: 'Estilo',
    description: 'Título médio',
  ),
  SlashCommandOption(
    type: SlashOptionType.h3,
    label: 'Título 3',
    icon: Icons.text_format,
    aliases: ['h3', 'titulo3', 'heading3', 't3'],
    group: 'Estilo',
    description: 'Título pequeno',
  ),
  SlashCommandOption(
    type: SlashOptionType.task,
    label: 'Tarefa',
    icon: Icons.check_box_outlined,
    aliases: ['task', 'tarefa', 'todo', 'check', 'checkbox'],
    group: 'Listas',
    description: 'Tarefa com checkbox',
  ),
  SlashCommandOption(
    type: SlashOptionType.bulletList,
    label: 'Lista com marcadores',
    icon: Icons.format_list_bulleted,
    aliases: ['bullet', 'lista', 'ul', 'marcadores'],
    group: 'Listas',
    description: 'Lista sem ordem',
  ),
  SlashCommandOption(
    type: SlashOptionType.numberedList,
    label: 'Lista numerada',
    icon: Icons.format_list_numbered,
    aliases: ['numbered', 'numerada', 'ol', 'numero'],
    group: 'Listas',
    description: 'Lista com números',
  ),
  SlashCommandOption(
    type: SlashOptionType.quote,
    label: 'Citação',
    icon: Icons.format_quote,
    aliases: ['quote', 'citacao', 'blockquote'],
    group: 'Blocos',
    description: 'Bloco de citação',
  ),
  SlashCommandOption(
    type: SlashOptionType.divider,
    label: 'Divisor',
    icon: Icons.horizontal_rule,
    aliases: ['divider', 'divisor', 'hr', 'linha'],
    group: 'Blocos',
    description: 'Linha horizontal',
  ),
  SlashCommandOption(
    type: SlashOptionType.image,
    label: 'Imagem',
    icon: Icons.image_outlined,
    aliases: ['image', 'imagem', 'foto', 'pic'],
    group: 'Mídia',
    description: 'Adicionar uma imagem',
  ),
  SlashCommandOption(
    type: SlashOptionType.file,
    label: 'Arquivo',
    icon: Icons.attach_file,
    aliases: ['file', 'arquivo', 'anexo', 'attachment'],
    group: 'Mídia',
    description: 'Adicionar um arquivo',
  ),
];

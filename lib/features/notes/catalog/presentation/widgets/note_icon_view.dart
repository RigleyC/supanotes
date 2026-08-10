import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_catalog.dart';

class NoteIconView extends StatelessWidget {
  const NoteIconView({super.key, required this.icon, this.size = 20});

  final NoteIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (icon.isEmoji) {
      return Semantics(
        label: 'Ícone ${icon.value}',
        child: Text(icon.value, style: TextStyle(fontSize: size)),
      );
    }
    final theme = Theme.of(context);
    return Semantics(
      label: 'Ícone ${catalogIconLabelFor(icon.value)}',
      child: Icon(
        catalogIconFor(icon.value),
        size: size,
        color: noteIconColorFor(icon.colorKey!).resolve(theme.brightness),
      ),
    );
  }
}

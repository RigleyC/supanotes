import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';

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
    return Semantics(
      label: 'Ícone ${catalogIconLabels[icon.value] ?? icon.value}',
      child: Icon(
        icon.catalogIcon,
        size: size,
        color: icon.colorFor(Theme.of(context).colorScheme),
      ),
    );
  }
}

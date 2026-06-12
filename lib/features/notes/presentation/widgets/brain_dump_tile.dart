import 'package:flutter/material.dart';

class BrainDumpTile extends StatelessWidget {
  const BrainDumpTile({super.key, required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.inbox_outlined, color: scheme.onSurfaceVariant),
      title: Text(title),
      onTap: onTap,
    );
  }
}

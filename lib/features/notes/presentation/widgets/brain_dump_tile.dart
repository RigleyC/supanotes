import 'package:flutter/material.dart';

import 'package:supanotes/shared/widgets/theme_svg.dart';

class BrainDumpTile extends StatelessWidget {
  const BrainDumpTile({super.key, required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const ThemeSvg('assets/icons/IconTrashPaper.svg'),
      title: Text(title),
      onTap: onTap,
    );
  }
}

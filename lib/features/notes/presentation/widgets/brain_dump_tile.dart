import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BrainDumpTile extends StatelessWidget {
  const BrainDumpTile({super.key, required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: SvgPicture.asset(
        'assets/icons/IconTrashPaper.svg',
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          isDark ? Colors.white : Colors.black,
          BlendMode.srcIn,
        ),
      ),
      title: Text(title),
      onTap: onTap,
    );
  }
}

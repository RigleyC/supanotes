import 'package:flutter/material.dart';

class AdaptiveSliverNavBar extends StatelessWidget {
  const AdaptiveSliverNavBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    if (title == null) {
      return SliverAppBar(actions: actions, leading: leading, pinned: true);
    }

    return SliverAppBar.medium(
      title: title!,
      actions: actions,
      leading: leading,
      pinned: true,
    );
  }
}

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
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
    if (PlatformInfo.isIOS && title != null) {
      return CupertinoSliverNavigationBar(
        largeTitle: title,
        middle: title,
        leading: leading,
        trailing: _buildTrailing(),
      );
    }

    if (title == null) {
      return SliverAppBar(
        actions: actions,
        leading: leading,
      );
    }

    return SliverAppBar.medium(
      title: title!,
      actions: actions,
      leading: leading,
    );
  }

  Widget? _buildTrailing() {
    if (actions == null || actions!.isEmpty) return null;
    if (actions!.length == 1) return actions!.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions!,
    );
  }
}

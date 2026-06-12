import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

class QuickActionFabs extends StatelessWidget {
  const QuickActionFabs({
    super.key,
    required this.smallIcon,
    required this.smallTooltip,
    required this.onSmallPressed,
    this.smallIconSize = 20,
    this.smallFabKey,
    this.smallHeroTag,
    required this.primaryIcon,
    required this.primaryTooltip,
    required this.onPrimaryPressed,
    this.primaryIconSize = 22,
    this.primaryFabKey,
    this.primaryHeroTag,
  });

  final String smallIcon;
  final String smallTooltip;
  final VoidCallback onSmallPressed;
  final double smallIconSize;
  final Key? smallFabKey;
  final String? smallHeroTag;

  final String primaryIcon;
  final String primaryTooltip;
  final VoidCallback onPrimaryPressed;
  final double primaryIconSize;
  final Key? primaryFabKey;
  final String? primaryHeroTag;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.white : Colors.black;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          key: smallFabKey,
          heroTag: smallHeroTag,
          tooltip: smallTooltip,
          onPressed: onSmallPressed,
          backgroundColor: bgColor,
          shape: const CircleBorder(),
          child: SvgPicture.asset(
            smallIcon,
            width: smallIconSize,
            height: smallIconSize,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.black : Colors.white,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FloatingActionButton(
          key: primaryFabKey,
          heroTag: primaryHeroTag,
          tooltip: primaryTooltip,
          onPressed: onPrimaryPressed,
          backgroundColor: bgColor,
          shape: const CircleBorder(),
          child: SvgPicture.asset(
            primaryIcon,
            width: primaryIconSize,
            height: primaryIconSize,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.black : Colors.white,
              BlendMode.srcIn,
            ),
          ),
        ),
      ],
    );
  }
}

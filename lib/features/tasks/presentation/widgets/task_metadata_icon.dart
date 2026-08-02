import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const taskCalendarIconAsset = 'assets/icons/calendar.svg';

class TaskMetadataCalendarIcon extends StatelessWidget {
  const TaskMetadataCalendarIcon({
    super.key,
    required this.color,
    this.size = 20,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      taskCalendarIconAsset,
      width: size,
      height: size,
      colorMapper: _TaskCalendarColorMapper(color),
    );
  }
}

class _TaskCalendarColorMapper extends ColorMapper {
  const _TaskCalendarColorMapper(this.themeColor);

  final Color themeColor;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color svgColor,
  ) {
    return svgColor == const Color(0xFF000000) ? themeColor : svgColor;
  }
}

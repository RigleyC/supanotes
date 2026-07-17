import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows a platform-adaptive time picker.
/// Uses standard Material [showTimePicker] on Android/Desktop, and a
/// [CupertinoPicker] modal sheet on iOS.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return _showCupertinoTimePicker(context, initialTime);
  }
  return showTimePicker(context: context, initialTime: initialTime);
}

Future<TimeOfDay?> _showCupertinoTimePicker(
  BuildContext context,
  TimeOfDay initial,
) async {
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (_) {
      final hourController = FixedExtentScrollController(
        initialItem: initial.hour,
      );
      final minuteController = FixedExtentScrollController(
        initialItem: initial.minute,
      );
      return Container(
        height: 260,
        color: CupertinoColors.systemBackground,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Cancelar'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                CupertinoButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop(
                      TimeOfDay(
                        hour: hourController.selectedItem,
                        minute: minuteController.selectedItem,
                      ),
                    );
                  },
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: hourController,
                      itemExtent: 32,
                      onSelectedItemChanged: (_) {},
                      children: List.generate(
                        24,
                        (i) =>
                            Center(child: Text(i.toString().padLeft(2, '0'))),
                      ),
                    ),
                  ),
                  const Text(':'),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: minuteController,
                      itemExtent: 32,
                      onSelectedItemChanged: (_) {},
                      children: List.generate(
                        60,
                        (i) =>
                            Center(child: Text(i.toString().padLeft(2, '0'))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

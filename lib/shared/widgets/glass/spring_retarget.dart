import 'package:motor/motor.dart';

/// Retargets [controller] to [target] with [motion]. The motion is only set
/// when it changes, because setting one restarts the running simulation.
void springTo<T extends Object>(
  MotionController<T> controller,
  Motion motion,
  T target,
) {
  if (controller.motion != motion) controller.motion = motion;
  controller.animateTo(target);
}

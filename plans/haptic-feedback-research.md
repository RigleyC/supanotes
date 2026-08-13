# Haptic Feedback Research — SupaNotes

Research date: 2026-08-13

## Scope

This note supports a read-only diagnosis of haptic and related feedback in SupaNotes.
It covers:

- the meaning of standard haptic patterns on Apple platforms;
- the current Flutter API behavior on iOS and Android;
- Android and Material guidance for frequency, strength, consistency, and accessibility;
- the risks of excessive or duplicated feedback; and
- questions that need device testing or a product decision.

The research used only primary or platform-authority sources. No source code,
runtime configuration, or tests were changed. No secrets were read.

### Local baseline

This is a code inventory, not a user-perception result:

- `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
  calls `HapticFeedback.lightImpact()` at the start of the completion/reopen
  update handler and `HapticFeedback.mediumImpact()` before the task long-press
  callback.
- `lib/features/notes/editor/presentation/widgets/note_toolbar.dart` calls
  `HapticFeedback.selectionClick()` for formatting, list, task, indentation,
  and divider commands, including insert-at-end paths.
- Task and toolbar controls already contain Flutter `Semantics` nodes.

This inventory does not prove that users receive duplicate feedback. Runtime
behavior still needs testing on physical devices.

## Sources

All links below are direct links to official documentation or first-party
technical material. No aggregator or third-party article was used.

### Apple

- [Human Interface Guidelines: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [UIKit: UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator)
- [UIKit: UIImpactFeedbackGenerator](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator)
- [UIKit: UISelectionFeedbackGenerator](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator)
- [UIKit: UINotificationFeedbackGenerator](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator)
- [Core Haptics](https://developer.apple.com/documentation/corehaptics)

### Flutter

- [HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)
- [HapticFeedback.selectionClick](https://api.flutter.dev/flutter/services/HapticFeedback/selectionClick.html)
- [HapticFeedback.lightImpact](https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html)
- [HapticFeedback.mediumImpact](https://api.flutter.dev/flutter/services/HapticFeedback/mediumImpact.html)
- [HapticFeedback.heavyImpact](https://api.flutter.dev/flutter/services/HapticFeedback/heavyImpact.html)
- [HapticFeedback.vibrate](https://api.flutter.dev/flutter/services/HapticFeedback/vibrate.html)
- [HapticFeedback.successNotification](https://api.flutter.dev/flutter/services/HapticFeedback/successNotification.html)
- [HapticFeedback.warningNotification](https://api.flutter.dev/flutter/services/HapticFeedback/warningNotification.html)
- [HapticFeedback.errorNotification](https://api.flutter.dev/flutter/services/HapticFeedback/errorNotification.html)
- [Feedback](https://api.flutter.dev/flutter/widgets/Feedback-class.html)
- [Feedback.forTap](https://api.flutter.dev/flutter/widgets/Feedback/forTap.html)
- [Feedback.forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html)
- [SystemSound](https://api.flutter.dev/flutter/services/SystemSound-class.html)
- [SystemSoundType](https://api.flutter.dev/flutter/services/SystemSoundType.html)
- [Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html)
- [SemanticsService](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html)
- [SemanticsService.announce](https://api.flutter.dev/flutter/semantics/SemanticsService/announce.html)

### Android and Material

- [Android: Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- [Android: Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)
- [Android: HapticFeedbackConstants API reference](https://developer.android.com/reference/android/view/HapticFeedbackConstants)
- [Material Design 3: States](https://m3.material.io/foundations/interaction/states/overview)
- [Material Design: Gestures](https://m2.material.io/design/interaction/gestures.html)

### First-party technical material checked

- [Apple WWDC19: Designing Audio-Haptic Experiences](https://developer.apple.com/videos/play/wwdc2019/810/)
- [Apple WWDC21: Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278/)

These sessions reinforce causality, harmony, and utility. They are useful for
custom audio-haptic work, but the HIG, UIKit, Flutter, and Android documents
are sufficient for the current SupaNotes diagnosis.

## Confirmed facts

### Apple meaning and design rules

1. Apple groups standard UIKit feedback into three relevant categories:
   impact for a physical impact or snap, selection for movement through discrete
   values, and notification for success, failure, or warning. This meaning is
   defined by [`UIFeedbackGenerator`](https://developer.apple.com/documentation/uikit/uifeedbackgenerator),
   [`UIImpactFeedbackGenerator`](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator),
   [`UISelectionFeedbackGenerator`](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator),
   and [`UINotificationFeedbackGenerator`](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator).

2. Apple asks apps to use standard patterns according to their documented
   meanings and to keep a clear cause-and-effect relationship. Haptics should
   complement visual and audio feedback, remain short for discrete events, and
   be optional or muteable. Apple also warns against frequent or long-running
   haptics because they can become tiring or distract from the task. Source:
   [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics).

3. Supported iOS controls such as switches, sliders, and pickers can provide
   Apple-designed haptics by default. A custom Flutter control must not assume
   that it receives the same built-in behavior. Source:
   [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics).

4. Apple accessibility guidance says to pair haptics with matching audio cues
   when useful, and to provide visual and other alternatives. Haptics must not
   be the only channel for important information. Source:
   [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

5. UIKit feedback generators are concrete classes. `prepare()` can prepare a
   generator before the event, but the event still needs to call the matching
   generator method. Source:
   [UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator)
   and [UIImpactFeedbackGenerator](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator).

### Flutter behavior

1. Flutter's `HapticFeedback` API intentionally calls default platform behavior.
   It is not a precise control API for the system haptic module. Source:
   [HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html).

2. The same Dart method does not have the same platform meaning on iOS and
   Android. The documented mappings are:

   | Flutter method | iOS mapping | Android mapping | Source |
   |---|---|---|---|
   | `selectionClick()` | `UISelectionFeedbackGenerator`, iOS 10+ | `HapticFeedbackConstants.CLOCK_TICK` | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/selectionClick.html), [Apple](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `lightImpact()` | `UIImpactFeedbackGenerator` light, iOS 10+ | `VIRTUAL_KEY` | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html), [Apple](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `mediumImpact()` | `UIImpactFeedbackGenerator` medium, iOS 10+ | `KEYBOARD_TAP` | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/mediumImpact.html), [Apple](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `heavyImpact()` | `UIImpactFeedbackGenerator` heavy, iOS 10+ | `CONTEXT_CLICK`, API 23+; no effect below API 23 | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/heavyImpact.html), [Apple](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `vibrate()` | default system vibration | platform long-press feedback | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/vibrate.html), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `successNotification()` | `UINotificationFeedbackGenerator` success | `CONFIRM`, API 30+; no effect below API 30 | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/successNotification.html), [Apple](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `warningNotification()` | `UINotificationFeedbackGenerator` warning | `KEYBOARD_TAP`, API 30+; no effect below API 30 | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/warningNotification.html), [Apple](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
   | `errorNotification()` | `UINotificationFeedbackGenerator` error | `REJECT`, API 30+; no effect below API 30 | [Flutter](https://api.flutter.dev/flutter/services/HapticFeedback/errorNotification.html), [Apple](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator), [Android](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |

3. Flutter's `Feedback` class provides platform-specific acoustic and/or haptic
   feedback for common gestures. `Feedback.forTap` plays the Android click
   system sound and is a no-op on iOS. `Feedback.forLongPress` triggers the
   platform-typical Android vibration, and on iOS it triggers a heavy impact
   together with the click system sound. Both methods send a semantic gesture
   event before the platform feedback. Sources:
   [Feedback](https://api.flutter.dev/flutter/widgets/Feedback-class.html),
   [forTap](https://api.flutter.dev/flutter/widgets/Feedback/forTap.html), and
   [forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html).

4. `SystemSound` is a separate API for short system sounds. `click` means a
   button press, `tick` means a picker value change and is ignored except on
   iOS, and `alert` is ignored on mobile. Source:
   [SystemSoundType](https://api.flutter.dev/flutter/services/SystemSoundType.html).

5. Flutter `Semantics` annotates the widget tree for assistive technologies.
   `SemanticsService` exposes platform accessibility events and says to prefer
   implicit announcements from `Semantics` when possible. The older
   `SemanticsService.announce` method is deprecated, and Flutter documents that
   Android announcement events can disrupt TalkBack speech. Sources:
   [Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html),
   [SemanticsService](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html),
   and [announce](https://api.flutter.dev/flutter/semantics/SemanticsService/announce.html).

### Android and Material behavior

1. Android recommends `View.performHapticFeedback` with action-oriented
   `HapticFeedbackConstants` for normal interaction feedback. This path does
   not need the `VIBRATE` permission, honors the user's touch-feedback setting,
   and has platform fallback behavior for the constants. Sources:
   [Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)
   and [HapticFeedbackConstants](https://developer.android.com/reference/android/view/HapticFeedbackConstants).

2. Android states that frequent events should use very subtle feedback and that
   stronger feedback should be reserved for more important events. It also
   recommends consistency with the Android system and the app's own patterns.
   Source:
   [Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles).

3. Android recommends clear or rich haptics over buzzy haptics. If the choice is
   between a buzzy touch vibration and no haptic, Android says to choose no
   haptic. Android also discourages legacy one-shot vibration APIs for normal
   touch feedback. Source:
   [Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles).

4. Android notes that some events, including long press, can already have
   default haptics when a view handles the event. Source:
   [Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).

5. Material Design 3 defines visible interaction states such as pressed,
   focused, selected, dragged, and disabled, and asks teams to apply them
   consistently. Material also notes that long press can expose extra actions
   but is not easily discoverable. Sources:
   [Material states](https://m3.material.io/foundations/interaction/states/overview)
   and [Material gestures](https://m2.material.io/design/interaction/gestures.html).

## Implications for Flutter, iOS, and Android

### Recommended product rule

Define the meaning of the event first, then select one feedback owner and one
platform-appropriate pattern. Do not select a Flutter method only because its
name sounds close to the action. This follows Apple's documented meanings and
Flutter's different iOS/Android mappings. Sources:
[Apple UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator),
[Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html),
and [Android Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles).

### Flutter

- Keep one owner for each gesture. A manual `HapticFeedback` call, a
  `Feedback` wrapper, and a component's built-in feedback can overlap. This is
  a runtime risk to verify, not a confirmed current defect. Flutter documents
  the gesture wrappers and Android documents default long-press feedback.
  Sources: [Flutter Feedback](https://api.flutter.dev/flutter/widgets/Feedback-class.html)
  and [Android event feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).
- Treat `selectionClick()` as a candidate for a control whose value changes
  through discrete choices. It is a weak fit for every toolbar command because
  Apple defines selection feedback for movement through a series of values, and
  Android receives `CLOCK_TICK`. This is a design inference from the documented
  meanings, not a device measurement. Sources:
  [Apple selection feedback](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator),
  [Flutter selectionClick](https://api.flutter.dev/flutter/services/HapticFeedback/selectionClick.html),
  and [Android constants](https://developer.android.com/reference/android/view/HapticFeedbackConstants).
- For a long press, use one platform feedback path at the moment the gesture is
  accepted. Do not add a second manual pulse if the chosen Flutter or component
  path already provides it. Keep a visible pressed/activated state because
  haptics do not make a long-press affordance discoverable by themselves.
  Sources: [Flutter forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html),
  [Android event feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback),
  and [Material gestures](https://m2.material.io/design/interaction/gestures.html).
- Keep `Semantics` state and action labels independent from haptics. A checked
  task must remain understandable when haptics are disabled or unavailable.
  Prefer implicit semantic state changes over routine explicit announcements.
  Sources: [Flutter Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html)
  and [SemanticsService](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html).
- Use the standard Flutter calls first. Custom native channels, Core Haptics,
  or Android compositions are not justified by the current editor use cases
  alone. They add device capability and fallback decisions. Sources:
  [Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html),
  [Apple Core Haptics](https://developer.apple.com/documentation/corehaptics),
  and [Android custom effects](https://developer.android.com/develop/ui/views/haptics/custom-haptic-effects).

### iOS

- Use impact only for an impact-like event, selection for a discrete value
  change, and notification for a meaningful success, failure, or warning.
  Source: [UIKit feedback generators](https://developer.apple.com/documentation/uikit/uifeedbackgenerator).
- Match the haptic with the visual state and any sound. Keep pulses short and
  causal. Provide a way to mute or disable app haptics, and do not make an
  important state visible only through touch. Source:
  [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
  and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- Do not add custom Core Haptics patterns for ordinary editor commands until a
  standard pattern fails a tested product need. Core Haptics is appropriate for
  a deliberately designed, multimodal interaction, not as a default replacement
  for a standard pulse. Sources:
  [Core Haptics](https://developer.apple.com/documentation/corehaptics)
  and [WWDC21 Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278/).

### Android

- Prefer the action-oriented platform behavior exposed by Flutter's standard
  haptic calls. Do not assume iOS semantics carry over: for example,
  `selectionClick()` maps to `CLOCK_TICK`, while `mediumImpact()` maps to
  `KEYBOARD_TAP`. Sources:
  [Flutter selectionClick](https://api.flutter.dev/flutter/services/HapticFeedback/selectionClick.html),
  [Flutter mediumImpact](https://api.flutter.dev/flutter/services/HapticFeedback/mediumImpact.html),
  and [HapticFeedbackConstants](https://developer.android.com/reference/android/view/HapticFeedbackConstants).
- Honor system touch-feedback settings and avoid a custom vibration permission
  path for ordinary interaction feedback. Source:
  [Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).
- Test the API-level behavior of any notification-style call. Flutter documents
  no effect for `successNotification`, `warningNotification`, and
  `errorNotification` below API 30, and no effect for `heavyImpact` below API
  23. Sources: [Flutter HapticFeedback methods](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)
  and the individual method pages linked in the mapping table above.
- Avoid legacy one-shot vibration for editor feedback. If a custom effect is
  ever needed, define a capability and fallback policy first. Source:
  [Android Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
  and [Android custom effects](https://developer.android.com/develop/ui/views/haptics/custom-haptic-effects).

## Risks of excessive haptics

| Risk | Evidence and SupaNotes implication |
|---|---|
| Sensory fatigue | Android says frequent vibration can annoy users, numb the hands, distract them, and make them turn off all haptics. The many toolbar call sites need a frequency test, not only a code review. [Android principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles) |
| Meaning becomes unclear | Apple says a haptic needs a clear causal relationship and a stable meaning. Using `selectionClick()` for unrelated formatting and insertion actions can weaken that association. This is an inference from the source and the local inventory. [Apple Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) |
| Duplicate feedback | A custom task long press may combine a manual haptic with default platform or Flutter feedback. The sources confirm that those paths can exist; the actual SupaNotes overlap is still an open device-test question. [Flutter forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html), [Android event feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback) |
| Cross-platform mismatch | Flutter maps the same method to different native meanings and API levels. A pulse that feels correct on iOS can feel like a clock tick, keyboard tap, or context click on Android. [Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html), [Android constants](https://developer.android.com/reference/android/view/HapticFeedbackConstants) |
| Accessibility gap | A haptic is not a semantic label or a visible state. If a task completion or error is communicated only by vibration, the experience fails when haptics are disabled, unavailable, or not perceived. [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Flutter Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html) |
| Dissonance with visual or audio feedback | Apple and Android both require harmony between visual, audio, and haptic timing. A late, early, or stronger-than-the-animation pulse can feel like a broken interaction. [Apple Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [Android principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles) |
| Physical disruption | Apple warns that haptic force can disrupt experiences involving the camera, gyroscope, or microphone. This is a general platform risk; it is not evidence of a current SupaNotes defect. [Apple Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) |
| No-op or uneven support | Flutter documents platform and API-level no-op cases. Android also varies by device capability. Critical product state must remain correct without a haptic. [Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html), [Android API reference](https://developer.android.com/develop/ui/views/haptics/haptics-apis) |

## Open questions

1. What is the reported symptom: too strong, too frequent, duplicated, late,
   missing, or semantically wrong? Which screen, gesture, OS version, device,
   and accessibility setting reproduce it?
2. Does the task long press receive any default feedback from the native view,
   Flutter gesture wrapper, or shared component in addition to the explicit
   `mediumImpact()` call? Verify on a physical Android device and iPhone. The
   platform documentation confirms that default paths can exist, but it does
   not describe this app's runtime composition. Sources:
   [Flutter forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html)
   and [Android event feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).
3. Is task completion a frequent toggle confirmation or a rare meaningful
   success? This decides whether it needs a light state-change pulse, no pulse,
   or an outcome notification. The source meanings do not decide the product
   priority. Sources: [Apple notification feedback](https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator)
   and [Android haptics principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles).
4. Should toolbar formatting and insertion commands have haptics at all, or
   only pickers and controls whose values move through discrete choices? This
   needs a product decision and a short usability test. Source:
   [Apple selection feedback](https://developer.apple.com/documentation/uikit/uiselectionfeedbackgenerator).
5. Does SupaNotes need an app-level haptic setting, in addition to platform
   settings? Apple says haptics should be optional; Android standard APIs honor
   the system touch-feedback setting. Sources:
   [Apple Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
   and [Android event feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback).
6. What Android API range and device classes are in the supported product
   matrix? Flutter has documented no-op behavior for some calls on older APIs,
   and haptic actuators differ by device. Sources:
   [Flutter HapticFeedback methods](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)
   and [Android Haptics API reference](https://developer.android.com/develop/ui/views/haptics/haptics-apis).
7. With VoiceOver and TalkBack enabled, do the current semantic state changes
   and explicit pulses remain useful, or do they compete with spoken feedback?
   Test task completion, long press, and toolbar actions. Prefer semantic state
   updates over explicit announcement events. Sources:
   [Flutter SemanticsService](https://api.flutter.dev/flutter/semantics/SemanticsService-class.html)
   and [Flutter announce guidance](https://api.flutter.dev/flutter/semantics/SemanticsService/announce.html).
8. Do the visual animation, persistence result, and any audio cue complete at
   the same moment as the haptic? Apple and Android both require this timing to
   be designed as one feedback experience. Sources:
   [Apple WWDC19](https://developer.apple.com/videos/play/wwdc2019/810/)
   and [Android principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles).
